if ($env:VSCODE_INJECTION) {
    Write-Host -ForegroundColor Yellow 'Running inside VSCode Terminal.'
    return
}

if ($host.Name -ne 'ConsoleHost') {
    Write-Host -ForegroundColor Yellow 'Not running in consolehost.'
    return
}

#   ___             _   _
#  | __|  _ _ _  __| |_(_)___ _ _  ___
#  | _| || | ' \/ _|  _| / _ \ ' \(_-<
#  |_| \_,_|_||_\__|\__|_\___/_||_/__/
#
#

<#
.SYNOPSIS
    Display a table of console colors.
.DESCRIPTION
    Shows combinations of foreground and background ConsoleColor values.
    Use -ShowAll to iterate over all colors; otherwise a curated subset is shown.
.PARAMETER ShowAll
    Display every possible color value, not just the reduced palette.
#>
function Show-ColorTable {
    Param([switch]$ShowAll)
    if (-not $ShowAll) {
        # Inspired by https://windowsterminalthemes.dev
        $fgColors = @('Black', 'DarkGray', 'DarkRed', 'Red', 'DarkGreen', 'Green', `
                'DarkYellow', 'Yellow', 'DarkBlue', 'Blue', 'DarkMagenta', 'Magenta', `
                'DarkCyan', 'Cyan', 'Gray', 'White')
        $bgColors = @('Black', 'DarkGray', 'DarkRed', 'DarkGreen', 'DarkYellow', `
                'DarkBlue', 'DarkMagenta', 'DarkCyan', 'Gray', 'Black' )
        foreach ($fgcolor in $fgColors) {
            foreach ($bgcolor in $bgColors) {
                Write-Host -NoNewLine -ForegroundColor $fgcolor -BackgroundColor $bgcolor 'gYw'
                Write-Host -NoNewline ' '
            }
            Write-Host ''
        }
    }
    else {
        $colors = [enum]::GetValues([ConsoleColor])
        foreach ($bgcolor in $colors) {
            foreach ($fgcolor in $colors) {
                $fg, $bg = ($fgcolor -replace 'Dark', 'Dk'), ($bgcolor -replace 'Dark', 'Dk')
                Write-Host -ForegroundColor $fgcolor -BackgroundColor $bgcolor -NoNewLine "|$fg"
            }
            Write-Host " on $bg"
        }
    }
}

<#
.SYNOPSIS
    Download the latest PowerShell MSI release.
.DESCRIPTION
    Queries the GitHub releases API for the latest PowerShell release and
    downloads the x64 MSI installer to the specified folder.
.PARAMETER Folder
    Destination directory where the MSI will be saved.
#>
function DownloadLatestPS {
    param([Parameter(Mandatory = $true)] [string]$Folder)

    # Speed up Invoke-WebRequest calls
    $oldpp = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $json = (Invoke-WebRequest -uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest').Content | ConvertFrom-Json
    $psUri = [uri]($json.assets | Where-Object name -Like 'PowerShell-*-win-x64.msi').browser_download_url

    "Downloading: $($psUri.AbsoluteUri)"

    Invoke-WebRequest $psUri.AbsoluteUri -OutFile (Join-Path $Folder $psuri.Segments[-1])
    $ProgressPreference = $oldpp
}

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
    Terminate a process gracefully or forcefully.
.DESCRIPTION
    Attempts to close the main window of the named process. If -Force is
    specified and the process remains, Stop-Process is invoked to kill it.
.PARAMETER Name
    Name of the process to terminate.
.PARAMETER Force
    Forcefully stop the process if it does not exit gracefully.
#>
function Invoke-Kill {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [switch]$Force
    )

    $process = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if ($process.Count -eq 0) {
        'Process not found'
    }
    elseif ($process.Count -eq 1) {
        $description = $process.Description
        $processId = $process.Id
        $mainWindowTitle = $process.MainWindowTitle
        # try gracefully first
        $process.CloseMainWindow() | Out-Null
        if ($Force -and -not $process.HasExited) {
            Stop-Process -Force -Name $Name
        }
        if ($process.HasExited) {
            'process {0} ({1}) - ''{2}'' killed' -f $description, $processId, $mainWindowTitle
        }
    }
    else {
        'Multiple instances running: {0}' -f ($process.Id -join ' ')
    }
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
    Wrapper around cwRsync for Windows.
.DESCRIPTION
    Converts Windows-style paths to cygwin format, locates the cwRsync
    installation via Scoop, and runs rsync over SSH to a remote host.
.PARAMETER Source
    Local path to sync.
.PARAMETER Destination
    Remote destination path.
.PARAMETER User
    SSH username.
.PARAMETER Hostname
    Remote host address or name.
#>
function rsync {
    param(
        [Parameter(Mandatory = $True)] [string]$Source,
        [Parameter(Mandatory = $True)] [string]$Destination,
        [Parameter(Mandatory = $True)] [string]$User,
        [Parameter(Mandatory = $True)] $Hostname
    )

    # Use cwrsync
    $cwrsync_path = scoop.ps1 prefix cwrsync
    if (-not $cwrsync_path) {
        'cwrsync not found'
        return
    }
    $cwrsync_path += '\bin'

    # https://www.itefix.net/content/rsync-does-not-recognize-windows-paths-correct-manner
    $Source = $Source -replace '\\', '/'
    if ($Source -match '^[A-Za-z]:') {
        $Source = '/cygdrive/{0}{1}' -f $Source[0], $Source.Substring(2)
    }

    $Destination = "$User@${Hostname}:$Destination"

    "Source: $Source"
    "Destination: $Destination"

    & "$cwrsync_path\rsync.exe" --rsh="$cwrsync_path/ssh.exe" --progress --human-readable --verbose --recursive --dirs $Source $Destination
}

<#
.SYNOPSIS
    Retrieve metadata from JJazzLab .sng files in the current directory.
.DESCRIPTION
    Parses each .sng XML file and outputs selected song metadata properties.
#>
function Get-JJazzLabMeta {
    foreach ($file in (Get-ChildItem -File '*.sng')) { ([xml](Get-Content $file)).Song | Select-Object @{Name = 'BaseName'; Expression = { $file.BaseName } }, spName, spTempo, spComments }
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
function Invoke-Sha256Hash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$Files
    )

    begin {}
    process {
        foreach ($file in $Files) {
            $target = (Resolve-Path $file).Path
            Write-Verbose "Hashing $file"
            # Get-ChildItem -Recurse -File | ForEach-Object {
            '{0} *{1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLower(), (Resolve-Path -Relative $target).Substring(2) -replace '\\', '/'
        }
    }
    end {}
    clean {}

}

<#
.SYNOPSIS
    Create a backup archive using 7-Zip.
.DESCRIPTION
    Uses 7z.exe to recursively add files from a source path into a
    timestamped archive with certain performance-focused options.
.PARAMETER SourcePath
    Root directory to back up.
.PARAMETER DestinationPath
    Directory where the archive will be created (default: current folder).
#>
function Invoke-7zBackup {
    param (
        # Root of path to back up recursively, e.g. 'F:\'
        [Parameter(Mandatory)][string]$SourcePath,
        # Backup path, e.g. 'D:\BACKUP'
        [string]$DestinationPath = '.'
    )

    Get-Command '7z.exe' -CommandType Application -ErrorAction Stop | Out-Null

    $filename = 'Backup {0}' -f (Get-Date -Format '(yyyy-dd-mm)')

    $arguments = @(
        'a',
        # "-mx=1" reduces compression to the minimum (faster)
        '-mx=1',
        # "-ms=off" turns off solid mode (faster)
        '-ms=off',
        # "-mf=off" turns off special compression for exe files (faster)
        '-mf=off',
        # "-v4g" uses 4GB volumes
        '-v4g',
        # -x[r[-|0]][m[-|2]][w[-]]{@listfile|!wildcard} : eXclude filenames
        '-x!"System Volume Information"',
        '-x!"$RECYCLE.BIN"',
        '-x!"$RECYCLER"',
        '-x!"$WINDOWS.~BT"',
        # -r[-|0] : Recurse subdirectories for name search
        '-r',
        # <archive_name>
        ('"{ 0 }"' -f (Join-Path $DestinationPath $filename)),
        # <file_names>
        (Join-Path $SourcePath '*')
    )

    Start-Process -FilePath '7z.exe' -ArgumentList $arguments -NoNewWindow -Wait
}

<#
.SYNOPSIS
    Update qBittorrent IP filter list from iblocklist.
.DESCRIPTION
    Downloads and installs the latest ipfilter.dat from a fixed URL,
    optionally skipping if the local file is up to date. Detects qBittorrent
    profile location automatically.
.PARAMETER Force
    Force download even if the local file appears current.
#>
function Invoke-IpFilterUpdate {
    [CmdletBinding()]
    param ([switch]$Force)

    [uri]$BlockListUri = 'http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=dat&archiveformat=zip'

    # try default install location
    $BlockListPathResolved = Resolve-Path "$env:AppData\qBittorrent"  -ErrorAction SilentlyContinue
    if (-not $BlockListPathResolved) {
        # try scoop install path
        $BlockListPathResolved = Resolve-Path '~\scoop\apps\qbittorrent\current\profile\qBittorrent'  -ErrorAction SilentlyContinue
    }
    if ($BlockListPathResolved) {
        $ipFilterPath = Join-Path -Path $BlockListPathResolved -ChildPath 'ipfilter.dat'
        Write-Host " `e[1;34m*`e[0m Blocklist path: `e[1;35m$ipFilterPath`e[0m"

        if (-not $Force) {
            Write-Host " `e[1;34m*`e[0m Checking blocklist date on server."
            $response = Invoke-WebRequest -Uri $BlockListUri -Method Head -UserAgent 'curl/8.7.1'
            $lmServer = [datetime]($response.Headers['Last-Modified'][0])
            $lmLastWriteTime = (Get-ItemProperty -LiteralPath $ipFilterPath -Name LastWriteTime -ErrorAction SilentlyContinue).LastWriteTime
            $updateNeeded = $true
            if ($lmLastWriteTime) {
                $lmLocal = [datetime]$lmLastWriteTime
                Write-Host (" `e[1;33m*`e[0m Server: `e[1;36m{0:yyyy-MM-dd}`e[0m; Local: `e[1;36m{1:yyyy-MM-dd}`e[0m" -f $lmServer, $lmLocal)
                # Only update if local is at least a day older than server
                if (($lmLocal - $lmServer).Days -eq 0) {
                    $updateNeeded = $false
                }
            }
        }
        else {
            # -Force specified
            Write-Host " `e[1;33m!`e[0m Force specified, forcing update."
            $updateNeeded = $true
        }

        if ($updateNeeded) {
            # ZIP file contains a single file, "ydxerpxkpcfqjaybcssw.txt"
            $tempIpFilterPath = Join-Path -Path $BlockListPathResolved -ChildPath 'ipfilter.dat.zip'
            Write-Host " `e[1;34m*`e[0m Downloading new filter to `e[1;35m$tempIpFilterPath`e[0m"
            $response = Invoke-WebRequest -Uri $BlockListUri -UserAgent 'curl/8.7.1' -OutFile $tempIpFilterPath
            Write-Host " `e[1;34m*`e[0m Expanding to `e[1;35m$BlockListPathResolved`e[0m"
            Expand-Archive -DestinationPath $BlockListPathResolved -LiteralPath $tempIpFilterPath
            Remove-Item -LiteralPath $ipFilterPath -ErrorAction SilentlyContinue
            Write-Host " `e[1;34m*`e[0m Renaming to `e[1;35mipfilter.dat`e[0m"
            Rename-Item -NewName 'ipfilter.dat' -LiteralPath (Join-Path -Path $BlockListPathResolved 'ydxerpxkpcfqjaybcssw.txt')
            Remove-Item -LiteralPath $tempIpFilterPath
            Write-Host " `e[1;32m✓`e[0m Blocklist updated."
        }
        else {
            Write-Host " `e[1;32m✓`e[0m Everything is up to date!"
        }
    }
    else {
        Write-Warning " `e[1;31m!`e[0m Cant determine qBittorrent path."
    }
}

<#
.SYNOPSIS
    Convert audio/video files to MP3 using ffmpeg.
.DESCRIPTION
    Wraps ffmpeg.exe to encode an input file to MP3 with variable bitrate
    quality settings. Supports pipeline input of file names and optional
    output filename specification.
.PARAMETER Quality
    Numeric quality level (0–9) controlling bitrate; lower is higher quality.
.PARAMETER InputFile
    Path of the source file to convert. Can be piped in.
.PARAMETER OutputFile
    Destination MP3 file; if omitted, derived from input name.
.PARAMETER Force
    Overwrite existing output without prompting.
#>
function ConvertTo-Mp3 {
    [CmdletBinding()]
    param (
        # "transparent results":
        # 0 = 245 kbit/sec avg.
        # 1 = 225 kbit/sec avg..
        # 2 = 190 kbit/sec avg. (170-210 kbit/sec). See https://trac.ffmpeg.org/wiki/Encode/MP3
        # 3 = 175 kbit/sec avg.
        [ValidateRange(0, 9)][int]$Quality = 2,
        # Input file name. Can also use "-FullName" for piping from "Get-ChildItem -File"
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $InputFile,
        # Output file name. If not specified, uses <name>.mp3 in current directory.
        [Parameter(Position = 1)]
        [string] $OutputFile,
        # Force overwriting files that exist.
        [switch]$Force
    )

    begin {
        $count = 0
    }

    process {
        # Don't modify $OutputFile, as we will check it against null with each new file.
        $Destination = $OutputFile

        if (-not $OutputFile) {
            $Destination = ('{0}.mp3' -f (Split-Path -Path $InputFile -LeafBase))
        }

        if ((Split-Path -Path $Destination -Extension) -ne '.mp3') {
            throw 'Extension must be .mp3'
        }

        'Converting "{0}" to "{1}".' -f (Split-Path -Path $InputFile -Leaf), (Split-Path -Path $Destination -Leaf)

        # -hide_banner  Suppress printing banner.
        # -loglevel     Set logging level and flags used by the library.
        # -stats        Log encoding progress/statistics as "info"-level log
        # -i            input file url
        # -vn           blocks all video streams of a file from being filtered or being automatically selected or mapped for any output.
        # -codec:a      Select an encoder. "a" is stream_specifier, followed by codec name.
        # -qscale:a     Specify codec-dependent fixed quality scale (VBR). "a" is stream_specifier, followed by q value.
        $ffmpeg_args = `
            '-hide_banner', `
            '-loglevel', 'error', `
            '-stats', `
            '-i', """$InputFile""", `
            '-vn', `
            '-codec:a', 'libmp3lame', `
            '-qscale:a', $Quality

        if ($Force) {
            $ffmpeg_args += '-y'
        }

        # Output filename must be last argument.
        $ffmpeg_args += """$Destination"""

        # ffmpeg always seems to return 0 in ExitCode, so no way to check for failures, even with "-PassThru".
        Start-Process -FilePath 'ffmpeg.exe' -ArgumentList $ffmpeg_args -NoNewWindow -Wait

        $count++
    }

    end {
        "Processed $count files."
    }
}

<#
.SYNOPSIS
    Format a PowerShell script file using PowerShell-Beautifier.
.DESCRIPTION
    Installs the PowerShell-Beautifier module if needed and runs
    Edit-DTWBeautifyScript with four-space indentation.
.PARAMETER Path
    Path to the script to format.
#>
function Format-PowerShell {
    # .DESCRIPTION
    # format powershell script
    Param([Parameter(Mandatory, Position = 0)][string]$Path)

    Install-Module -Name PowerShell-Beautifier

    Edit-DTWBeautifyScript -SourcePath (Resolve-Path -LiteralPath $Path).Path -IndentType FourSpaces
}

<#
.SYNOPSIS
    Decode an ATP SafeLink URL.
.DESCRIPTION
    Parses the query string of the given URI and returns the original URL
    and data parameters in a PSCustomObject.
.PARAMETER Uri
    The SafeLink URI to decode.
#>
function Convert-SafeLink {
    [CmdletBinding()]
    Param([Parameter(Mandatory, Position = 0, ValueFromPipeline)][Uri]$Uri)

    if ($Uri.Query) {
        $query = @{}
        # Split query into Name, Unescaped Value pairs.
        $Uri.Query.Substring(1) -split '&' | ForEach-Object {
            $key, $value = $_.Split('=')
            $query[$key] = [URI]::UnescapeDataString($value)
        }

        [PSCustomObject]@{
            'Host' = $Uri.Host
            'Uri'  = $query['url']
            'Data' = $query['data']
        }
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

#######################################################################################################################
#             _
#  _ __  __ _(_)_ _
# | '  \/ _` | | ' \
# |_|_|_\__,_|_|_||_|
#

'download', 'filesystem', 'git', 'messages', 'musescore', 'normalize', 'pdf', 'prompt', 'transcribe', 'update', 'vscode' `
| ForEach-Object {
    "Loading functions from $_.ps1"
    . "$PSScriptRoot\$_.ps1"
}


# See also $env:USERPROFILE\OneDrive\Documents\PowerShell\profile.ps1
Write-BoxedMessage -Message "Profile loaded from $PSScriptRoot`nPowerShell $((Get-Host).Version)"

# Use emacs key bindings.
# Set-PSReadLineOption -EditMode Emacs
# Make TAB completion more like bash - Use up,  down arrow to complete command.
Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

if ((Get-Command -Name 'fzf.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
    # PSFzf: https://github.com/kelleyma49/PSFzf
    'PSFzf' | ForEach-Object {
        if (-not (Get-Module -Name $_ -ListAvailable -ErrorAction SilentlyContinue)) {
            "Installing $_"
            Install-Module -Name $_ -Force
        }
    }

    'Enabling Ctrl+T, Ctrl+R completion'
    # Reverse Search Through PSReadline History (default chord: Ctrl+r)
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    # Set-Location Based on Selected Directory (default chord: Alt+c)
    $commandOverride = [ScriptBlock] { param($Location) Write-Host $Location }
    Set-PsFzfOption -AltCCommand $commandOverride
    # Tab Expansion
    # Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
}

Invoke-WingetUpdate

# Add Winget package paths to PATH
$wingetPackagesPath = "$env:LocalAppData\Microsoft\Winget\Packages"
"Adding Winget paths from $wingetPackagesPath"
Get-ChildItem -LiteralPath $wingetPackagesPath -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue `
| Group-Object DirectoryName `
| ForEach-Object {
    $exes = $_.Group | ForEach-Object { "`e[1m{0}`e[22m" -f (Split-Path -Leaf $_) }
    '  {0}: {1}' -f [IO.Path]::GetRelativePath("$env:LocalAppData\Microsoft\Winget\Packages", $_.Name), ($exes -join ', ')
    $env:Path += ";$($_.Name)"
}

# Invoke-ScoopUpdate

# -----------------------------------------------------------------------------
# zoxide, needs to come AFTER setting prompt!

if ((Get-Command -Name 'zoxide.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
    'Adding zoxide completion'
    Invoke-Expression -Command $(zoxide.exe init powershell | Out-String)
}


