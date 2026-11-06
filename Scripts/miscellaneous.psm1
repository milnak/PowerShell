# Functions that should be moved to their own files.

<#
.SYNOPSIS
    Display a table of console colors.
.DESCRIPTION
    Displays all ConsoleColor foreground/background combinations, a compact
    gYw sample palette, or the terminal's standard and bright foreground colors.
.PARAMETER All
    Display all foreground/background ConsoleColor combinations.
.PARAMETER gYw
    Display gYw samples over a curated background palette.
.PARAMETER Terminal
    Display the standard and bright terminal foreground-color pairs.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None. Writes color samples to the host.
.EXAMPLE
    Show-ColorTable -All
.EXAMPLE
    Show-ColorTable -Terminal
#>
function Show-ColorTable {
    [CmdletBinding(DefaultParameterSetName = 'ShowAll')]

    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All,
        [Parameter(Mandatory = $true, ParameterSetName = 'gYw')]
        [switch]$gYw,
        [Parameter(Mandatory = $true, ParameterSetName = 'Terminal')]
        [switch]$Terminal
    )

    switch ($PSCmdlet.ParameterSetName) {
        'Terminal' {
            Write-Host -ForegroundColor White 'Foreground'

            Write-Host -ForegroundColor Black -NoNewLine "Black`t"
            Write-Host -ForegroundColor DarkGray 'Bright Black'
            Write-Host -ForegroundColor DarkRed -NoNewLine "Red`t"
            Write-Host -ForegroundColor Red 'Bright red'
            Write-Host -ForegroundColor DarkGreen -NoNewLine "Green`t"
            Write-Host -ForegroundColor Green 'Bright green'
            Write-Host -ForegroundColor DarkYellow -NoNewLine "Yellow`t"
            Write-Host -ForegroundColor Yellow 'Bright yellow'
            Write-Host -ForegroundColor DarkBlue -NoNewLine "Blue`t"
            Write-Host -ForegroundColor Blue 'Bright blue'
            Write-Host -ForegroundColor DarkMagenta -NoNewLine "Purple`t"
            Write-Host -ForegroundColor Magenta 'Bright purple'
            Write-Host -ForegroundColor DarkCyan -NoNewLine "Cyan`t"
            Write-Host -ForegroundColor Cyan 'Bright cyan'
            Write-Host -ForegroundColor Gray -NoNewLine "White`t"
            Write-Host -ForegroundColor White 'Bright white'
        }
        'gYw' {
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

        'All' {
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
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Source/destination summaries and native rsync output.
.EXAMPLE
    Invoke-RSync -Source 'C:\Music' -Destination '/backup/music' -User backup -Hostname server
.NOTES
    Requires Scoop's cwrsync package and SSH access to the remote host.
    Recursively copies files; it does not request deletion of remote extras.
#>
function Invoke-RSync {
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
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.Management.Automation.PSCustomObject. BaseName, spName, spTempo,
    and spComments properties from each song.
.EXAMPLE
    Get-JJazzLabMeta | Format-Table
#>
function Get-JJazzLabMeta {
    foreach ($file in (Get-ChildItem -File '*.sng')) {
        ([xml](Get-Content $file)).Song `
        | Select-Object @{
            Name       = 'BaseName'
            Expression = { $file.BaseName }
        }, spName, spTempo, spComments
    }
}

<#
.SYNOPSIS
    Create a backup archive using 7-Zip.
.DESCRIPTION
    Builds a recursive 7-Zip backup command with minimum compression,
    non-solid mode, 4 GB volumes, and exclusions for selected system folders.
    Invokes Start-Process with inherited -WhatIf/-Confirm preferences.
.PARAMETER SourcePath
    Root directory to back up.
.PARAMETER DestinationPath
    Directory where the archive will be created (default: current folder).
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None. 7-Zip writes progress to the console.
.EXAMPLE
    Invoke-7zBackup -SourcePath 'C:\Data' -DestinationPath 'D:\Backups' -WhatIf
.NOTES
    Requires 7z.exe on PATH. The current argument list passes the archive-name
    expression literally instead of expanding the intended date-based path.
#>
function Invoke-7zBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Root of path to back up recursively, e.g. 'F:\'
        [Parameter(Mandatory)][string]$SourcePath,
        # Backup path, e.g. 'D:\BACKUP'
        [string]$DestinationPath = '.'
    )

    Get-Command '7z.exe' -CommandType Application -ErrorAction Stop | Out-Null

    $fileNames = Join-Path $SourcePath '*'
    $archiveName = Join-Path $DestinationPath (Get-Date -Format 'yyyy-MM-dd')

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
        # <archive_name> (quoted)
        '`"$archiveName `"'
        # <file_names>
        $fileNames
    )

    # Start-Process handles WhatIf/Confirm automatically.
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
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None. Writes progress and status to the host.
.EXAMPLE
    Update-IpFilter -Force -WhatIf
.NOTES
    Supports -WhatIf/-Confirm for replacing the filter. Without -Force,
    performs an HTTP HEAD request before ShouldProcess. Writes and expands
    a temporary ZIP in the detected qBittorrent profile directory.
#>
function Update-IpFilter {
    [CmdletBinding(SupportsShouldProcess)]
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
            if ($PSCmdlet.ShouldProcess($BlockListPathResolved, 'Update blocklist')) {
                # ZIP file contains a single file, "ydxerpxkpcfqjaybcssw.txt"
                $tempIpFilterPath = Join-Path -Path $BlockListPathResolved -ChildPath 'ipfilter.dat.zip'
                Write-Host " `e[1;34m*`e[0m Downloading new filter to `e[1;35m$tempIpFilterPath`e[0m"
                $response = Invoke-WebRequest -Uri $BlockListUri -UserAgent 'curl/8.7.1' -OutFile $tempIpFilterPath
                Write-Host " `e[1;34m*`e[0m Expanding to `e[1;35m$BlockListPathResolved`e[0m"
                Expand-Archive -DestinationPath $BlockListPathResolved -LiteralPath $tempIpFilterPath
                Remove-Item -LiteralPath $ipFilterPath -ErrorAction SilentlyContinue
                Write-Host " `e[1;34m*`e[0m Renaming to `e[1;35mipfilter.dat`e[0m"
                Rename-Item -NewName 'ipfilter.dat' -LiteralPath (Join-Path -Path $BlockListPathResolved 'ydxerpxkpcfqjaybcssw.txt') -Confirm:$false
                Remove-Item -LiteralPath $tempIpFilterPath -Confirm:$false
                Write-Host " `e[1;32m✓`e[0m Blocklist updated."
            }
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
    Format a PowerShell script file using PowerShell-Beautifier.
.DESCRIPTION
    Calls Install-Module for PowerShell-Beautifier on every invocation and runs
    Edit-DTWBeautifyScript with four-space indentation.
.PARAMETER Path
    Literal path to the script to rewrite.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    Any output emitted by Install-Module or Edit-DTWBeautifyScript.
.EXAMPLE
    Format-PowerShell -Path '.\Scripts\messages.psm1'
.NOTES
    Can contact the configured module repository and prompt for installation.
    Formats the source file in place; does not support -WhatIf.
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
    SafeLink URI to decode. Accepts URI values or strings from the pipeline.
.INPUTS
    System.Uri, or URI strings.
.OUTPUTS
    System.Management.Automation.PSCustomObject. Host, decoded Uri, and Data
    properties. Returns nothing when the input has no query string.
.EXAMPLE
    Convert-SafeLink -Uri 'https://example.com/?url=https%3A%2F%2Fexample.org&data=value'
.NOTES
    Decodes query values locally; does not navigate to or validate the target.
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
    Push the profile directory onto the location stack.
.DESCRIPTION
    Changes to the directory containing the current host's $PROFILE file.
    The prior location can be restored with Pop-Location.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None.
.EXAMPLE
    Push-ProfileLocation
#>
function Push-ProfileLocation {
    Push-Location -LiteralPath (Split-Path -LiteralPath $PROFILE)
}

<#
.SYNOPSIS
Generates a GUID in various C/C++/Registry/Attribute formats.
.DESCRIPTION
Creates a fresh GUID and renders it as an OLE macro, DEFINE_GUID macro,
GUID structure, braced registry value, or language attribute.

.PARAMETER Type
Specifies the output format:
Ole, Define, Struct, Registry, AttributeBracket, AttributeBrace
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. A formatted GUID or code template with placeholder names.

.EXAMPLE
New-GuidFormat Ole

.EXAMPLE
New-GuidFormat Registry
#>
function New-GuidFormat {
    [CmdletBinding()]
    param (
        [ValidateSet('Ole', 'Define', 'Struct', 'Registry', 'AttributeBracket', 'AttributeBrace')]
        [Parameter(Mandatory, Position = 0)]
        [string]$Type
    )

    <#
    .SYNOPSIS
    Creates a GUID with its component fields available as strings.
    .DESCRIPTION
    Splits a fresh GUID into the fields needed by C/C++ GUID initializers.
    .INPUTS
    None. This function does not accept pipeline input.
    .OUTPUTS
    System.Management.Automation.PSCustomObject. Guid, Data1, Data2, Data3,
    and Data4_1 through Data4_8 properties.
    .EXAMPLE
    $parts = New-GuidObject
    .NOTES
    Local helper for New-GuidFormat; each call generates a new identifier.
    #>
    function New-GuidObject {
        $guid = (New-Guid).Guid
        $m = Select-String `
            -InputObject $guid `
            -Pattern '([0-9A-Fa-f]{8})-([0-9A-Fa-f]{4})-([0-9A-Fa-f]{4})-([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})'

        [PSCustomObject]@{
            Guid    = $guid.ToUpper()
            Data1   = $m.Matches.Groups[1].Value
            Data2   = $m.Matches.Groups[2].Value
            Data3   = $m.Matches.Groups[3].Value
            Data4_1 = $m.Matches.Groups[4].Value
            Data4_2 = $m.Matches.Groups[5].Value
            Data4_3 = $m.Matches.Groups[6].Value
            Data4_4 = $m.Matches.Groups[7].Value
            Data4_5 = $m.Matches.Groups[8].Value
            Data4_6 = $m.Matches.Groups[9].Value
            Data4_7 = $m.Matches.Groups[10].Value
            Data4_8 = $m.Matches.Groups[11].Value
        }
    }

    switch ($Type) {
        'Ole' {
            $guid = New-GuidObject
            "// {{{0}}}`nIMPLEMENT_OLECREATE(<<class>>, <<external_name>>,`n0x{1}, 0x{2}, 0x{3}, 0x{4}, 0x{5}, 0x{6}, 0x{7}, 0x{8}, 0x{9}, 0x{10}, 0x{11});" -f `
                $guid.Guid, $guid.Data1, $guid.Data2, $guid.Data3,
            $guid.Data4_1, $guid.Data4_2, $guid.Data4_3, $guid.Data4_4,
            $guid.Data4_5, $guid.Data4_6, $guid.Data4_7, $guid.Data4_8
        }

        'Define' {
            $guid = New-GuidObject
            "// {{{0}}}`nDEFINE_GUID(<<name>>,`n0x{1}, 0x{2}, 0x{3}, 0x{4}, 0x{5}, 0x{6}, 0x{7}, 0x{8}, 0x{9}, 0x{10}, 0x{11});" -f `
                $guid.Guid, $guid.Data1, $guid.Data2, $guid.Data3,
            $guid.Data4_1, $guid.Data4_2, $guid.Data4_3, $guid.Data4_4,
            $guid.Data4_5, $guid.Data4_6, $guid.Data4_7, $guid.Data4_8
        }

        'Struct' {
            $guid = New-GuidObject
            "/* {{{0}}} */`nstatic const GUID <<name>> =`n{{ 0x{1}, 0x{2}, 0x{3}, {{ 0x{4}, 0x{5}, 0x{6}, 0x{7}, 0x{8}, 0x{9}, 0x{10}, 0x{11} }} }};" -f `
                $guid.Guid, $guid.Data1, $guid.Data2, $guid.Data3,
            $guid.Data4_1, $guid.Data4_2, $guid.Data4_3, $guid.Data4_4,
            $guid.Data4_5, $guid.Data4_6, $guid.Data4_7, $guid.Data4_8
        }

        'Registry' {
            '{{{0}}}' -f (New-GuidObject).Guid
        }

        'AttributeBracket' {
            '[Guid("{0}")]' -f (New-GuidObject).Guid
        }

        'AttributeBrace' {
            '<Guid("{0}")>' -f (New-GuidObject).Guid
        }
    }
}

<#
.SYNOPSIS
    Convert Ultimate Guitar-style chord/lyric pairs into ChordPro format.
.DESCRIPTION
    Reads the clipboard as text, removes blank lines, and processes alternating
    chord and lyric lines. Inserts non-whitespace chord tokens into each lyric
    line at their original column positions using ChordPro tags such as [G].
.INPUTS
    None. Text is read from the clipboard, not the pipeline.
.OUTPUTS
    System.String. One ChordPro lyric line per chord/lyric pair.

.EXAMPLE
             A
    Blame it all on my roots
      Bbdim
    I showed up in boots
        Bm
    And ruined your black tie affair
        E
    The last one to know, the last one to show
              A
    I was the last one you thought you'd see there

    # Copy alternating chord and lyric lines to the clipboard first.
    Convert-UltimateGuitarToChopro
.NOTES
    Requires Get-Clipboard. An odd number of nonblank lines reports an error
    to the host and produces no converted lines.
#>
function Convert-UltimateGuitarToChopro {
    [CmdletBinding()]
    param(
        #     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        #     [AllowEmptyString()]
        #     [string]$InputObject
    )

    begin {
        $InputObject = Get-Clipboard -Raw
        $content = New-Object System.Collections.Generic.List[string]
    }

    process {
        if ($null -eq $InputObject) {
            return
        }

        if ($InputObject -match "`r|`n") {
            [Regex]::Split($InputObject, "`r?`n") | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($_)) {
                    $content.Add($_)
                    Write-Verbose "Added line: $_"
                }
            }
        }
        else {
            $content.Add($InputObject)
            Write-Verbose "Added line: $InputObject"
        }
    }

    end {
        if ($content.Count % 2 -ne 0) {
            Write-Host -ForegroundColor Red "The input does not have an even number of lines."
            return
        }

        for ($i = 0; $i -lt $content.Count; $i += 2) {
            $chordLine = $content[$i]
            $chordIndex = @{}
            $chords = ($chordLine | Select-String -Pattern '\S+' -AllMatches).Matches
            if ($chords.Count -ne 0) {
                $chords | ForEach-Object { $chordIndex[$_.Index] = $_.Value }
            }
            $lyricLine = $content[$i + 1]
            Write-Verbose "$chordLine`n$lyricLine"

            $result = $lyricLine
            foreach ($entry in ($chordIndex.GetEnumerator() | Sort-Object { [int]$_.Name } -Descending)) {
                Write-Verbose "Inserting chord $($entry.Value) at position $($entry.Name)"
                $pos = [int]$entry.Name
                $chord = "[$($entry.Value)]"
                if ($pos -ge $result.Length) {
                    # Add chord to end of line
                    $result = $result.PadRight($pos) + $chord
                }
                else {
                    # Insert chord at the specified position
                    $result = $result.Insert($pos, $chord)
                }
            }
            $result
        }
    }
}

<#
.SYNOPSIS
    Convert ChordPro files to PDF.
.DESCRIPTION
    Runs chordpro.exe for each input file and writes a PDF in the current
    directory using the selected ChordPro configuration style.
.PARAMETER File
    Path to a ChordPro file. Accepts paths and FileInfo objects from the pipeline.
.PARAMETER Style
    ChordPro configuration style to use. The default is modern3.
.PARAMETER NoChords
    Generate lyrics-only output by passing --lyrics-only to chordpro.exe.
.EXAMPLE
    Get-ChildItem '*.cho' | Convert-ChordProToPdf -Style modern3 -NoChords -Verbose
.INPUTS
    System.String, or objects with FullName or Path properties.
.OUTPUTS
    System.String. Any standard output emitted by chordpro.exe.
.NOTES
    Requires chordpro.exe on PATH. Supports -WhatIf/-Confirm. Uses letter
    paper, strict parsing, and no chord diagrams; output is <base-name>.pdf.
#>
function Convert-ChordProToPdf {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,

        # Style to apply
        [ValidateSet('chordii', 'modern1', 'modern2', 'modern3', 'dark', 'nashville', 'keyboard', 'ukulele', 'inline', 'lyricsonly', 'musejazz')]
        [string]$Style = 'modern3',

        # Do not include chords in output
        [switch]$NoChords
    )

    begin {
        # Ensure chordpro is available before processing any files
        Get-Command -Name 'chordpro.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
        $resolvedItem = Resolve-Path -LiteralPath $File -ErrorAction Stop

        if (-not $PSCmdlet.ShouldProcess($resolvedItem, 'Convert to PDF')) {
            return
        }

        $itemName = Split-Path -Path $File -Leaf | Split-Path -LeafBase

        # --meta=KEY=VALUE
        $arguments = @(
            "--config=$Style"
            '--no-a2crd'
            '--no-csv'
            '--strict'
            '--diagrams=none'
            '--page-size=letter'
            "--output=$itemName.pdf"
        )
        if ($NoChords) {
            $arguments += '--lyrics-only'
        }
        $arguments += $resolvedItem.Path

        Write-Verbose "Running chordpro.exe with arguments: $($arguments -join ' ')"
        chordpro.exe @arguments
    }

    end {
    }
}

<#
.SYNOPSIS
    Back up MobileSheets app data to an rclone remote.
.DESCRIPTION
    Copies the MobileSheets LocalState content directory to a dated folder
    on an rclone remote.
    Supports WhatIf/Confirm, validates source and rclone availability, and
    reports completion and elapsed time to the host.
.PARAMETER ContentDirectory
    MobileSheets content folder to back up. Defaults to the installed app's
    LocalState directory under $env:LocalAppData.
.PARAMETER RemoteName
    Name of the configured rclone remote. Defaults to gdrive.
.PARAMETER RemoteBasePath
    Base path on the remote where dated backups are stored. Defaults to
    MobileSheets_Backup; a yyyy-MM-dd subdirectory is appended.
.EXAMPLE
    Invoke-MobileSheetsBackup -Verbose
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Any standard output emitted by rclone.
.NOTES
    Requires rclone.exe and a configured remote. Uses rclone copy rather
    than sync, so remote-only files are not deleted. Repeated runs on the
    same day share a destination. A nonzero rclone exit code throws.
#>
function Invoke-MobileSheetsBackup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ContentDirectory = "$env:LocalAppData\Packages\41730Zubersoft.MobileSheets_ys1c8ct2g6ypr\LocalState",

        [ValidateNotNullOrEmpty()]
        [string]$RemoteName = 'gdrive',

        [ValidateNotNullOrEmpty()]
        [string]$RemoteBasePath = 'MobileSheets_Backup'
    )

    if (-not (Test-Path -LiteralPath $ContentDirectory -PathType Container)) {
        throw "Content directory not found: $ContentDirectory"
    }

    try {
        $rclonePath = (Get-Command 'rclone.exe' -CommandType Application -ErrorAction Stop).Source
    }
    catch {
        throw "Unable to find rclone.exe. Install rclone and ensure it is in PATH. $($_.Exception.Message)"
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd'
    $remotePath = '{0}:{1}/{2}' -f $RemoteName, $RemoteBasePath.Trim('/'), $timestamp

    Write-Host "Backing up MobileSheets content from '$ContentDirectory' to '$remotePath'"

    if (-not $PSCmdlet.ShouldProcess($remotePath, 'Copy MobileSheets content with rclone')) {
        return
    }

    $startedAt = Get-Date

    # rclone copy creates destination directories as needed and copies source contents into them.
    $rcloneArgs = @(
        $ContentDirectory
        $remotePath
        '--progress'
    )
    & $rclonePath copy @rcloneArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "rclone failed with exit code $exitCode while copying to '$remotePath'."
    }

    $finishedAt = Get-Date

    Write-Host "Backup completed successfully in $([math]::Round(($finishedAt - $startedAt).TotalSeconds, 2)) seconds."
}

<#
.SYNOPSIS
    Installs and configures Oh My Posh, Meslo, and a profile theme.
.DESCRIPTION
    Installs Oh My Posh through WinGet when missing, installs the Meslo font
    when needed, updates Windows Terminal's default font, and appends the
    selected theme's initialization command to the current host's profile.
.PARAMETER ThemeName
    Theme filename without .omp.json. Defaults to takuya.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Any native installer or Oh My Posh output.
.EXAMPLE
    Install-OhMyPosh -ThemeName takuya
.NOTES
    Requires WinGet, Windows Terminal's standard package settings path, and
    access to $PROFILE. Theme lookup uses a hard-coded WindowsApps package
    version. Existing initialization lines for other themes are not replaced.
    Changes installed software, terminal settings, and the profile without
    -WhatIf support.
#>
function Install-OhMyPosh {
    # Theme name to use. See https://ohmyposh.dev/docs/themes/
    Param([string]$ThemeName = 'takuya')

    $writeStatus = {
        param(
            [string]$Status,
            [ConsoleColor]$Color,
            [string]$Message
        )

        Write-Host ('  [{0,-7}] ' -f $Status) -NoNewline -ForegroundColor $Color
        Write-Host $Message
    }

    Write-Host "`nOh My Posh setup" -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor DarkGray

    # winget install JanDeDobbeleer.OhMyPosh --source winget
    if (-not (Get-Command -Name 'oh-my-posh.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
        & $writeStatus 'INSTALL' Yellow 'Installing Oh My Posh via winget'
        winget install JanDeDobbeleer.OhMyPosh --source winget
    }
    else {
        & $writeStatus 'OK' Green 'Oh My Posh is already installed'
    }

    # oh-my-posh font install meslo
    if (-not (oh-my-posh font list | Select-String -SimpleMatch 'Meslo')) {
        & $writeStatus 'INSTALL' Yellow 'Installing the Meslo font'
        oh-my-posh font install meslo
    }
    else {
        & $writeStatus 'OK' Green 'Meslo font is already installed'
    }

    # $terminalSettings = "$env:LocalAppData\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalSettings = "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $fontName = 'MesloLGM Nerd Font'
    Get-Content -LiteralPath $terminalSettings -Raw | ConvertFrom-Json | ForEach-Object {
        if (-not $_.profiles.defaults.font.face -or $_.profiles.defaults.font.face -ne $fontName) {
            & $writeStatus 'UPDATE' Yellow "Setting $fontName as the Windows Terminal default"
            $_.profiles.defaults.font.face = $fontName
            $_ | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $terminalSettings
            & $writeStatus 'ACTION' Magenta 'Restart Windows Terminal to apply the font change'
        }
        else {
            & $writeStatus 'OK' Green "$fontName is already the Windows Terminal default"
        }
    }

    $ompThemePath = "$env:ProgramFiles\WindowsApps\ohmyposh.cli_31.4.1.0_x64__96v55e8n804z4\themes"
    $ompThemeFile = Join-Path -Path $ompThemePath -ChildPath "$ThemeName.omp.json"
    if (-not (Test-Path -LiteralPath $ompThemeFile)) {
        & $writeStatus 'ERROR' Red "Theme file not found: $ompThemeFile"
        return
    }

    $ompInitCommand = ('oh-my-posh init pwsh --config "{0}" | Invoke-Expression' -f $ompThemeFile)
    if (-not (Get-Content $PROFILE | Select-String -SimpleMatch $ompInitCommand)) {
        & $writeStatus 'UPDATE' Yellow 'Adding the Oh My Posh initialization command to the profile'
        Add-Content -LiteralPath $PROFILE -Value $ompInitCommand
    }
    else {
        # TODO: Replace existing init if it already exists.
        & $writeStatus 'OK' Green 'The Oh My Posh initialization command is already in the profile'
    }

    Write-Host ('-' * 60) -ForegroundColor DarkGray
    & $writeStatus 'DONE' Cyan "Setup complete (theme: $ThemeName)"
    Write-Host ''
}

Export-ModuleMember -Function `
    Convert-ChordProToPdf, `
    Convert-SafeLink, `
    Convert-UltimateGuitarToChopro, `
    Format-PowerShell, `
    Get-JJazzLabMeta, `
    Install-OhMyPosh, `
    Invoke-7zBackup, `
    Invoke-MobileSheetsBackup, `
    Invoke-RSync, `
    New-GuidFormat, `
    Push-ProfileLocation, `
    Show-ColorTable, `
    Update-IpFilter
