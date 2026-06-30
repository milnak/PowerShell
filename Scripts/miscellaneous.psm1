# Functions that should be moved to their own files.

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
    Push the profile directory onto the location stack.
#>
function Push-ProfileLocation {
    Push-Location -LiteralPath (Split-Path -LiteralPath $PROFILE)
}

<#
.SYNOPSIS
Generates a GUID in various C/C++/Registry/Attribute formats.

.PARAMETER Type
Specifies the output format:
Ole, Define, Struct, Registry, AttributeBracket, AttributeBrace

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
    Reads text lines from the pipeline in alternating pairs:
    chord line, then lyric line. Non-whitespace chord tokens are inserted into
    the lyric line at matching column positions using ChordPro tags, e.g. [G].
.PARAMETER InputObject
    Input text from the pipeline. Each incoming object is treated as one line.
    Multi-line strings are split into individual lines.
.EXAMPLE
    Get-Clipboard | Convert-UltimateGuitarToChopro

    Converts clipboard text piped in as lines.
.EXAMPLE
    song.txt
    ========
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

    Get-Content .\song.txt | Convert-UltimateGuitarToChopro
#>
function Convert-UltimateGuitarToChopro {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [AllowEmptyString()]
        [string]$InputObject
    )

    begin {
        $content = New-Object System.Collections.Generic.List[string]
    }

    process {
        if ($null -eq $InputObject) {
            return
        }

        if ($InputObject -match "`r|`n") {
            [Regex]::Split($InputObject, "`r?`n") | ForEach-Object { $content.Add($_) }
        }
        else {
            $content.Add($InputObject)
        }
    }

    end {
        if ($content.Count % 2 -ne 0) {
            Write-Host -ForegroundColor Red "The input does not have an even number of lines."
            return 1
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
                $chord = "[$($entry.Value)] "
                if ($pos -ge $result.Length) {
                    $result = $result.PadRight($pos) + $chord
                }
                else {
                    $result = $result.Insert($pos, $chord)
                }
            }
            $result
        }
    }
}

function Convert-ChordProToPdf {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,

        #  chordii, modern1, modern2, modern3, dark, nashville
        # keyboard, ukulele
        # inline, lyricsonly, musejazz
        [string]$Style = 'modern3'
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

        chordpro.exe `
            --config="$Style" `
            --2-up `
            --no-csv `
            --strict `
            --no-chord-grids `
            --output="$itemName.pdf" `
            $resolvedItem
    }

    end {
    }
}

Export-ModuleMember -Function `
    Show-ColorTable, rsync, Get-JJazzLabMeta, Invoke-7zBackup, Update-IpFilter, `
    Format-PowerShell, Convert-SafeLink, Push-ProfileLocation, New-GuidFormat, `
    Convert-UltimateGuitarToChopro, Convert-ChordProToPdf

