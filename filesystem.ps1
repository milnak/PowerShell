<#
.SYNOPSIS
Creates a temporary folder and cds into it.
Outputs the path to allow for assigning to a variable.
#>
function mdcdtemp {
    [CmdletBinding()]
    $tempPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    Push-Location -LiteralPath $tempPath
    $tempPath
}


<#
.SYNOPSIS
Moves an item to the recycle bin.
.EXAMPLE
 Get-Item * |Remove-ItemToRecycleBin -Verbose -Confirm
#>
function Remove-ItemToRecycleBin {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)][ValidateNotNullOrEmpty()]
        [string[]]$Paths
    )

    begin {
        $shell = New-Object -ComObject 'Shell.Application'
    }

    process {
        foreach ($path in $Paths) {
            if (Test-Path -LiteralPath $path) {
                if ($PSCmdlet.ShouldProcess($path, 'Move to Recycle Bin')) {
                    Write-Verbose "Removing to Recycle Bin: $path"
                    $item = Get-Item -LiteralPath $path
                    $directoryPath = Split-Path -Path $item -Parent
                    $shell.Namespace($directoryPath).ParseName($item.Name).InvokeVerb('delete')
                }
            }
            else {
                Write-Warning "Path not found: $path"
            }
        }
    }

    end {}
}


<#
.SYNOPSIS
Removes a folder recursively.
.DESCRIPTION
Force removes a folder recursively, prompting first.
#>
function rmrf {
    param([Parameter(Mandatory = $true)] [string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $response = Read-Host "Really remove '$PATH'? ('`e[1myes`e[0m' to confirm)"
        if ($response -eq 'yes') {
            Remove-Item -Force -Recurse -LiteralPath $Path
        }
    }
    else {
        Write-Warning "Path not found or not folder."
    }
}


<#
.SYNOPSIS
Recursive file find.
.DESCRIPTION
By default will return all files starting in current folder tree.
#>
function rff {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [ValidateNotNullOrEmpty()] [string]$Filter = '*',
        [Parameter(Position = 1)] [ValidateNotNullOrEmpty()] [string]$Path = '.'
    )

    Get-ChildItem -Recurse -File -Filter $Filter -LiteralPath $Path | Select-Object -ExpandProperty FullName
}


<#
.SYNOPSIS
Recursive Grep
.DESCRIPTION
By default will start in current folder
#>
function rgrep {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$Pattern,
        [Parameter(Position = 1)] [string]$Files = '.'
    )
    Get-ChildItem -Recurse -File -Filter $Files | Select-String -Pattern $Pattern
}

<#
.SYNOPSIS
    Compute SHA256 hashes similar to UNIX sha256sum.
.DESCRIPTION
    Takes file paths from pipeline or arguments, outputs lowercase hash and
    relative path, separated by ' *' like the UNIX tool.
.PARAMETER Files
    One or more file paths to hash.
#>
function Get-FileSha256Hash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File
    )

    begin {}
    process {
        $target = (Resolve-Path $File).Path
        Write-Verbose "Hashing $File"
        # Get-ChildItem -Recurse -File | ForEach-Object {
        '{0} *{1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLower(), (Resolve-Path -Relative $target).Substring(2) -replace '\\', '/'
    }
    end {}
    clean {}

}


<#
.SYNOPSIS
Similar to Get-FileHash but also returns Base64 encoded value in 'HashBase64' field.
#>
function Get-FileHashBase64 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path,
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5', IgnoreCase)]
        [string]$Algorithm = 'SHA256'
    )

    begin {
        $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        Write-Verbose "Get-FileHashBase64 begin : $Algorithm"
    }

    process {
        foreach ($file in $Path) {
            $resolvedFile = Resolve-Path -LiteralPath $file
            Write-Verbose "Get-FileHashBase64 process $resolvedFile"
            $hash = $hashAlgorithm.ComputeHash([IO.File]::OpenRead($resolvedFile))
            [PSCustomObject]@{
                'Algorithm'  = $Algorithm
                'Hash'       = [BitConverter]::ToString($hash) -replace '-', ''
                'HashBase64' = [Convert]::ToBase64String($hash)
                'Path'       = $resolvedFile
            }
        }
    }

    end {
        $hashAlgorithm.Dispose()
        Write-Verbose 'Get-FileHashBase64 end'
    }
}


<#
.SYNOPSIS
Use sysinternals "du" to show child folder sizes.
#>
function Invoke-DU {
    [CmdletBinding()]
    param ([ValidateNotNullOrEmpty()] [string]$Path = '.')

    begin {
        Get-Command -Name 'du.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
        du.exe -nobanner -c -l 1 $Path
        | ConvertFrom-Csv
        | Sort-Object -Descending { [uint64]$_.DirectorySizeOnDisk }
        | Select-Object -First 15 @{ Name = 'Size'; Expression = { '{0,15:N0}' -f [uint64]$_.DirectorySizeOnDisk } }, Path
    }
}


<#
.SYNOPSIS
    Take ownership of a file or folder.
.NOTES
    takeown.exe and icacls.exe (both included in Windows) need to be in $env:PATH

    If a folder is specified, all files and subfolders of that folder will change ownership.
.EXAMPLE
    Set-SelfOwnership 'd:\temp\v.ps1'

    Set-SelfOwnership -Confirm 'd:\temp\v.ps1'

    Get-ChildItem  'd:\temp\g*' | Set-SelfOwnership -WhatIf  -Verbose
#>
function Set-SelfOwnership {
    # Support -Confirm, -WhatIf
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path
    )

    begin {
        Write-Verbose 'Set-SelfOwnership begin'

        # Ensure admin
        If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Admin privileges required'
        }

        # Check for required apps.
        'takeown', 'icacls' | ForEach-Object {
            Get-Command -Name "$_.exe" -CommandType Application -ErrorAction Stop | Out-Null
        }
    }

    process {
        foreach ($item in $Path) {
            Write-Verbose "Taking ownership of $item"
            $ResolvedPath = Resolve-Path -LiteralPath $item -ErrorAction Stop
            if ($PSCmdlet.ShouldProcess($ResolvedPath, 'Take Ownership')) {
                if (Test-Path -LiteralPath $ResolvedPath -PathType Container) {
                    takeown.exe /f $ResolvedPath /r /d y
                    if ($LASTEXITCODE -ne 0) {
                        throw "takeown.exe $ResolvedPath failed: $LASTEXITCODE"
                    }
                }
                else {
                    takeown.exe /f $ResolvedPath
                    if ($LASTEXITCODE -ne 0) {
                        throw "takeown $ResolvedPath failed: $LASTEXITCODE"
                    }
                }

                icacls.exe $ResolvedPath /grant administrators:F /t
                if ($LASTEXITCODE -ne 0) {
                    throw "icacls $ResolvedPath failed: $LASTEXITCODE"
                }
            }
        }
    }

    end {
        Write-Verbose 'Set-SelfOwnership end'
    }
}


<#
.SYNOPSIS
Display disk information in human readable format.
#>
function Get-DiskUsage {
    [CmdletBinding()]
    param()
    Get-Volume `
    | Where-Object DriveLetter -ne $null `
    | Sort-Object DriveLetter `
    | Select-Object -Property DriveLetter, FileSystemLabel, `
    @{Label = 'FreeGb'; Expression = { ($_.SizeRemaining / 1GB).ToString('F2') } }, `
    @{Label = 'TotalGb'; Expression = { ($_.Size / 1GB).ToString('F2') } }, `
    @{Label = 'Used %'; Expression = {
            $pct = 100 - ($_.SizeRemaining / $_.Size) * 100
            $blocks = [Math]::Floor($pct / 10)
            '{0,6:F2}% {1}{2}' -f $pct, ('■' * $blocks), ('□' * (10 - $blocks))
        }
    } `
    | Format-Table
}


function Get-ChildItemTree {
    param(
        [string]$Path = (Get-Location).Path,
        # Display the names of the files in each folder.
        [switch]$ShowFiles,
        # Use ASCII instead of extended characters.
        [switch]$UseAscii
    )

    if ($UseAscii) {
        $pipe = '|'
        $tee = '+'
        $elbow = '\'
        $dash = '-'
    }
    else {
    $pipe = [char]0x2502    # │
    $tee = [char]0x251C     # ├
    $elbow = [char]0x2514   # └
    $dash = [char]0x2500    # ─
    }

    function Show-TreeDir {
        param(
            [string]$Dir,
            [string]$Prefix = ""
        )

        $subdirs = @(Get-ChildItem -Path $Dir -Directory  -Force | Sort-Object Name)
        $hasDirs = $subdirs.Count -gt 0

        if ($ShowFiles) {
            $files = @(Get-ChildItem -Path $Dir -File -Force | Sort-Object Name)

            # Files listed first; use │ continuation when subdirs follow
            $fileIndent = if ($hasDirs) { "$pipe   " } else { "    " }
            foreach ($f in $files) {
                Write-Output "$Prefix$fileIndent$($f.Name)"
            }

            # Blank separator between files and directories
            if ($files.Count -gt 0 -and $hasDirs) {
                Write-Output "$Prefix$pipe"
            }
        }

        # Subdirectories
        for ($i = 0; $i -lt $subdirs.Count; $i++) {
            $isLast = ($i -eq $subdirs.Count - 1)
            $connector = if ($isLast) { "$elbow$([string]$dash * 3)" } else { "$tee$([string]$dash * 3)" }
            $childPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix$pipe   " }

            Write-Output "$Prefix$connector$($subdirs[$i].Name)"
            Show-TreeDir -Dir $subdirs[$i].FullName -Prefix $childPrefix
        }
    }

    # Print root label (drive + relative path like Windows tree)
    $root = (Resolve-Path $Path -ErrorAction Stop).Path
    $cwd = (Get-Location -ErrorAction Stop).Path
    $drive = Split-Path $cwd -Qualifier
    if ($root -eq $cwd) {
        Write-Output "${drive}."
    }
    else {
        Write-Output "$drive$((Split-Path $root -NoQualifier).TrimStart('\'))"
    }

    Show-TreeDir -Dir $root
}

Set-Alias -Name tree -Value Get-ChildItemTree
