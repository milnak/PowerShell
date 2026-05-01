<#
.SYNOPSIS
    Launch notepad4.
.DESCRIPTION
    Starts the notepad4 executable, forwarding any provided arguments.
#>
function Invoke-notepad {
    Start-Process -NoNewWindow -FilePath 'notepad4.exe' -ArgumentList $args
}


<#
.SYNOPSIS
    Retrieve the install path of a program via its uninstall GUID.
.DESCRIPTION
    Looks in HKCU and then HKLM uninstall registry keys for the given
    ProductId and returns the InstallLocation value.
.PARAMETER ProductId
    GUID or product identifier found in the uninstall registry key.
#>
function Get-UninstallPath {
    param(
        [Parameter(Mandatory = $true)] [string]$ProductId
    )

    $regPath = "/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/$ProductId"

    # Check user location first
    $path = Get-ItemProperty -Path "HKCU:$regPath" -Name 'InstallLocation' -ErrorAction SilentlyContinue
    if (-not $path) {
        # Check system location next
        $path = Get-ItemProperty -Path "HKLM:$regPath" -Name 'InstallLocation' -ErrorAction SilentlyContinue
    }

    $path.InstallLocation
}


<#
.SYNOPSIS
    Temporary PATH environment variable helper.
.DESCRIPTION
    List, add, or remove entries from the current PATH environment variable.
    Changes do not persist beyond the current session.
.PARAMETER List
    Display the current PATH entries.
.PARAMETER Add
    Add a new entry to PATH.
.PARAMETER Top
    When adding, place the new entry at the beginning.
.PARAMETER Remove
    Remove an entry from PATH.
.PARAMETER Path
    The path to add or remove.
#>
function Path {
    param(
        [Parameter(ParameterSetName = 'List')]
        [switch]$List,
        [Parameter(ParameterSetName = 'Add')]
        [switch]$Add,
        [Parameter(ParameterSetName = 'Add')]
        [switch]$Top = $False,
        [Parameter(ParameterSetName = 'Remove')]
        [switch]$Remove,
        [Parameter(ParameterSetName = 'Add', Mandatory = $True, Position = 0)]
        [Parameter(ParameterSetName = 'Remove', Mandatory = $True, Position = 0)]
        [string]$Path
    )

    if ($List) {
        (Get-ChildItem env:PATH).Value -split ';'
        return
    }

    if ($Add) {
        $Path = $Path.TrimEnd('\')
        $paths = (Get-ChildItem env:PATH).Value -split ';'
        if ($paths -notcontains $Path -and $paths -notcontains "$Path\") {
            if ($Top) {
                $env:PATH = "$Path;$env:PATH"
            }
            else {
                $env:PATH = "$env:PATH;$Path"
            }
        }
        return
    }

    if ($Remove) {
        $Path = $Path.TrimEnd('\')
        $newPath = @()
        (Get-ChildItem env:PATH).Value -split ';' | ForEach-Object {
            if ($_ -notlike $Path -and $_ -notlike "$Path\") {
                $newPath += $_
            }
        }
        $env:PATH = $newPath -join ';'
        return
    }
}

<#
.SYNOPSIS
    Retrieve detailed system and Windows product key information.
.DESCRIPTION
    Gathers Windows version, build, architecture, registered owner, and
    decrypts the product key from the registry. Adapted from WinProdKeyFinder.
#>
function Get-SystemInfo {
    # Derived from WinProdKeyFinder: https://github.com/mrpeardotnet/WinProdKeyFinder (DecodeProductKeyWin8AndUp)
    $digitalProductId = (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion').DigitalProductId

    # First byte appears to be length
    if ($digitalProductId[0] -ne $digitalProductId.Length) {
        throw 'Invalid length.'
    }

    $productId = [Text.Encoding]::UTF8.GetString($digitalProductId[8..30])
    $sku = [Text.Encoding]::UTF8.GetString($digitalProductId[36..48])

    $keyOffset = 52
    # decrypt base24 encoded binary data from $digitalProductId[52..66] $key
    $key = $null
    $digits = 'BCDFGHJKMPQRTVWXY2346789'
    For ($i = 24; $i -ge 0; $i--) {
        $index = 0
        For ($j = 14; $j -ge 0; $j--) {
            $index = $index * 256
            $index += $digitalProductId[$keyOffset + $j]
            $digitalProductId[$keyOffset + $j] = [math]::truncate($index / 24)
            $index = $index % 24
        }
        $key = $digits[$index] + $key
    }

    # Replace first character with 'N', split every 5 chars with '-'
    $key = ('N' + $key.Substring(1, $key.Length - 1)) -split '(.{5})' -ne '' -join '-'

    $currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $win32os = Get-WmiObject Win32_OperatingSystem

    [PSCustomObject]@{
        Edition         = $win32os.Caption
        Version         = $currentVersion.DisplayVersion
        OSBuild         = '{0}.{1}' -f $currentVersion.CurrentBuild, $currentVersion.UBR
        OSArch          = $win32os.OSArchitecture

        RegisteredOwner = $currentVersion.RegisteredOwner

        ProductID       = $productId
        Sku             = $sku

        ProductKey      = $key
    }
}

