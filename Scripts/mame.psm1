# TODO: Use Get-MameListXmlLookup in Get-MameRomList and Get-MameRoms

function Get-MameListXmlLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MamePath
    )

    try {
        $resolvedMamePath = (Resolve-Path $MamePath -ErrorAction Stop).Path
    }
    catch {
        Write-Warning "Mame EXE not found at $MamePath"
        exit 1
    }
    Write-Verbose "MAME path: $resolvedMamePath"

    if (-not (Test-Path -LiteralPath $resolvedMamePath -PathType Leaf)) {
        Write-Warning "Mame path is not a file: $resolvedMamePath"
        exit 1
    }

    # Parse output of "mame.exe -listxml", with caching keyed by MAME version string.
    $mameVersion = & $resolvedMamePath -version
    if ($mameVersion -match '\((\w+)\)') {
        # e.g. "mame0287"
        $cacheKey = $matches[1]
    }
    else {
        Write-Warning "Could not determine MAME version from '$resolvedMamePath'. Verify it is a valid MAME executable."
        exit 1
    }

    Write-Verbose "MAME version: $mameVersion"
    $cacheFile = Join-Path $env:TEMP "mame_listxml_$cacheKey.clixml"

    if (Test-Path $cacheFile) {
        Write-Verbose "Loading ROM list from cache: $cacheFile"
        $list = Import-Clixml $cacheFile
        return $list
    }

    Write-Verbose "Cache not found. Running '$resolvedMamePath -listxml' ..."

    # Output format:
    #
    # <?xml version="1.0"?>
    # <!DOCTYPE mame [
    # <!ELEMENT mame (machine+)>
    $list = [xml](& $resolvedMamePath -listxml)
    $list | Export-Clixml $cacheFile
    return $list
}

<#
.SYNOPSIS
List installed MAME ROMs, suitable for filtering.

.DESCRIPTION
Parses a MAME "listxml" DAT file and correlates it with ROM ZIP files
in a folder, returning objects with metadata suitable for filtering.

Prerequisite: MAME DAT file from "mame.exe -listxml", e.g.
advmame106.xml file from "MAME config files" at:
https://MAME.github.io/docs/download.html

.EXAMPLE
$roms = Get-MameRoms -DatFile 'advmame106.xml' -RomFolder 'D:\roms'

$roms |
    Sort-Object Description |
    Format-Table `
        @{Name='Description';Expression={$_.Description.Substring(0,[Math]::Min($_.Description.Length,40))}},`
        @{Name='Manufacturer';Expression={$_.Manufacturer.Substring(0,[Math]::Min($_.Manufacturer.Length,24))}},`
        Year, Rom

.EXAMPLE
Filter by runnable, cloneof empty, <=6 buttons, horizontal orientation, joystick control:

$roms |
    Where-Object {
        $_.cloneof -eq $null -and
        $_.buttons -le 6 -and
        $_.orientation -eq 'horizontal' -and
        ($_.control -like '*joy*' -or $_.control -eq 'stick')
    }

.EXAMPLE
List all required BIOS:
$roms | Where-Object RomOf | Select-Object -Unique RomOf

.EXAMPLE
List ROMs requiring more than 5 buttons:
$roms | Where-Object Buttons -gt 5 | Select-Object Rom,Buttons

.EXAMPLE
List clones:
$roms | Where-Object CloneOf -ne $null | Select-Object Rom,CloneOf
#>
function Get-MameRoms {

    [CmdletBinding()]
    param(
        # Path to MAME ROMs.
        [Parameter(Mandatory = $false)]
        [string]$RomFolder = 'roms',

        # MAME "listxml" file.
        [Parameter(Mandatory = $false)]
        [string]$DatFile = 'advmame106.xml'
    )

    if (-not (Test-Path -LiteralPath $RomFolder -PathType Container)) {
        Write-Warning "RomFolder not found: $RomFolder"
        return
    }

    # Load XML
    try {
        $advmame = [xml](Get-Content -LiteralPath $DatFile -ErrorAction Stop)
    }
    catch {
        Write-Warning "Unable to read DAT file: $DatFile"
        return
    }

    # Determine XML structure
    if ($advmame.mame.game) {
        $games = $advmame.mame.game | Where-Object { $_.runnable -eq 'yes' }
    }
    elseif ($advmame.datafile.game) {
        $games = $advmame.datafile.game
    }
    else {
        Write-Warning "Unexpected XML format: $DatFile"
        return
    }

    # Build lookup table
    $hash = @{}
    foreach ($g in $games) {
        $hash[$g.name] = [PSCustomObject]@{
            Rom          = $g.name
            CloneOf      = $g.cloneof
            RomOf        = $g.romof
            Description  = $g.Description
            Manufacturer = $g.Manufacturer
            Buttons      = $g.input.buttons
            Control      = $g.input.control
            Players      = $g.input.players
            Orientation  = $g.video.orientation
            Resolution   = '{0}x{1}' -f $g.video.width, $g.video.height
            Year         = $g.year
            Driver       = $g.driver
        }
    }

    # Iterate ROM folder
    Get-ChildItem -LiteralPath $RomFolder -File -Filter '*.zip' | ForEach-Object {
        $info = $hash[$_.BaseName]

        if ($info) {
            # Warn about driver issues
            if ($info.Driver -and $info.Driver.status -ne 'good') {
                $attribs = $info.Driver.Attributes |
                Where-Object { $_.Name -notin 'status', 'palettesize', 'savestate' -and $_.Value -ne 'good' } |
                ForEach-Object { '{0}: {1}' -f $_.Name, $_.Value }

                Write-Warning ("Driver issue: {0} ({1}) {{ {2} }}" -f $info.Rom, $info.Description, ($attribs -join '; '))
            }

            $info
        }
        else {
            Write-Warning "Unknown ROM: $_"
        }
    }
}

<#
.SYNOPSIS
Checks GitHub for the latest MAME release and updates the local installation.

.DESCRIPTION
Compares the local MAME version (from mame.exe -version) with the latest
GitHub release. If a newer version exists, downloads the self‑extracting
binary and extracts it using 7‑Zip.

.PARAMETER Path
Directory containing mame.exe. Defaults to the current directory.

.EXAMPLE
Invoke-MameUpdate

.EXAMPLE
Invoke-MameUpdate -Path 'D:\MAME' -Confirm
#>
function Invoke-MameUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path = (Resolve-Path '.'))

    $mameExe = (Join-Path $Path 'mame.exe')

    # Ensure 7z exists
    $null = Get-Command -Name '7z.exe' -CommandType Application -ErrorAction Stop

    # If mame.exe doesn't exist, prompt for fresh install
    if (-not (Test-Path -LiteralPath $mameExe -PathType Leaf)) {
        $choice = Read-Host 'MAME is not installed. Install latest version? (y/n)'
        if ($choice -ne 'y') {
            return
        }
        $output = '0.0 (mame0)'
    }
    else {
        $output = & $mameExe -version
        if ($LASTEXITCODE -ne 0) {
            Write-Host -ForegroundColor Red "mame.exe exited with code $LASTEXITCODE."
            return
        }
    }

    if ($output -notmatch '(?<friendly>\d+\.\d+)\s+\((?<version>mame\d+)\)') {
        Write-Host -ForegroundColor Red "Unable to determine local MAME version from output: $output"
        return
    }

    $localFriendly = $matches['friendly']
    $localVersion = $matches['version']

    Write-Verbose "Local MAME version: $localFriendly ($localVersion)"

    # Query GitHub API
    $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/mamedev/mame/releases/latest' -ErrorAction Stop
    $remoteVersion = $response.tag_name  # e.g. mame0276

    Write-Verbose "Latest available version: $remoteVersion"

    if ($localVersion -eq $remoteVersion) {
        Write-Host -ForegroundColor Green "MAME ($localVersion) is already up to date."
        return
    }

    # Find Windows x64 self‑extracting binary
    $asset = $response.assets | Where-Object name -like 'mame*_x64.exe' | Select-Object -First 1
    if (-not $asset) {
        throw "Unable to locate Windows x64 MAME binary in latest release."
    }

    $url = $asset.browser_download_url

    if (-not $PSCmdlet.ShouldProcess("MAME in $Path", "Update from $localVersion to $remoteVersion")) {
        return
    }

    # Download new version to a temp .exe file
    $tempFile = Join-Path ([IO.Path]::GetTempPath()) "$remoteVersion`_x64.exe"
    Write-Verbose "Downloading $remoteVersion to $tempFile ..."
    Invoke-WebRequest -Uri $url -OutFile $tempFile -ErrorAction Stop

    # Extract
    Write-Verbose "Extracting into $Path ..."
    try {
        $proc = Start-Process -FilePath '7z.exe' `
            -ArgumentList 'x', '-bso0', '-y', "-o$Path", $tempFile `
            -Wait -NoNewWindow -PassThru -Confirm:$false

        if ($proc.ExitCode -ne 0) {
            Write-Host -ForegroundColor Red "7z.exe exited with code $($proc.ExitCode)."
            return
        }
    }
    finally {
        Write-Verbose 'Cleaning up temporary file...'
        Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue -Confirm:$false
    }

    Write-Host -ForegroundColor Green "MAME updated successfully to $remoteVersion."
}

<#
.SYNOPSIS
Returns a filtered list of runnable base MAME machines from mame.exe -listxml output.

.DESCRIPTION
Runs mame.exe -listxml, filters to runnable non-clone/non-ROMOF machine entries,
and emits objects containing core metadata (description, controls, players,
orientation, resolution, year, and driver).

.PARAMETER MameExe
Path to MAME executable. Defaults to ./mame.exe.

.EXAMPLE
Get-MameRomList

.EXAMPLE
$m = Get-MameRomList -MameExe 'G:\MAME\mame.exe'

Get-Content 'D:\temp\Top 250 Greatest Arcade Games of All Time.txt' `
| Where-Object { $_.Trim() -ne "" } `
| ForEach-Object {
  $query = $_ # [regex]::Escape($_)
  $machines = $m | Where-Object Description -eq $query
  if (-not $machines) { $machines = $m | Where-Object Description -imatch "^$query(?: \([^)]*\))?" }
  if ($machines.Count -eq 0) { Write-Host -ForegroundColor Red "No match for '$query'" }
  else {
    if ($machines.Count -gt 1) { Write-Host -ForegroundColor Yellow "$($machines.Count) matches for '$query':" }
    $machines | ForEach-Object { '{0} ({1}, {2}) [{3}]' -f $_.Description, $_.Manufacturer, $_.Year, $_.Rom }
  }
}

.EXAMPLE
Get-MameRomList | Group-Object Control | Sort-Object -Descending Count

#>
function Get-MameRomList {
    [CmdletBinding()]
    param([string]$MameExe = './mame.exe')

    if (-not (Get-Command -Name $MameExe -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Warning "MAME executable not found: $MameExe"
        return
    }

    try {
        $mamexml = [xml](& $MameExe -listxml)
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "mame.exe -listxml exited with code $LASTEXITCODE."
            return
        }
    }
    catch {
        Write-Warning "Unable to parse $MameExe -listxml: $_"
        return
    }

    if (-not $mamexml.mame.machine) {
        Write-Warning "Unexpected XML format from $MameExe -listxml"
        return
    }

    if ($mamexml.mame.mameconfig -ne 10) {
        Write-Warning "Unexpected MAME config version from $MameExe -listxml: $($mamexml.mame.mameconfig)"
        # Continue, as it might still work.
    }

    # Best attempt to filter out non-arcade machines
    $machines = $mamexml.mame.machine `
    | Where-Object {
        $null -eq $_.cloneof -and
        $_.isbios -ne 'yes' -and
        $_.ismechanical -ne 'yes' -and
        $null -eq $_.softwarelist -and
        $_.runnable -ne 'no' -and
        $_.isdevice -ne 'yes' -and
        $null -ne $_.display -and
        $_.display.type -notin @('lcd', 'svg') -and
        $null -ne $_.input -and
        $_.input.players -ne 0 -and
        $null -ne $_.input.control -and
        @($_.input.control)[0].type -notin @('keyboard', 'keypad', 'gambling')

        # Removed to allow romof="neogeo": $null -eq $_.romof -and `
        # Removed to allow Allow status="preliminary", "imperfect": $_.driver.status -in @('good') -and `
    }

    foreach ($g in $machines) {
        [PSCustomObject]@{
            Rom          = $g.name
            Description  = $g.Description
            Manufacturer = $g.Manufacturer
            Year         = $g.year
            Players      = $g.input.players
            Control      = @($g.input.control)[0].type
            Buttons      = @($g.input.control)[0].buttons
            Resolution   = '{0}x{1}' -f $g.display.width, $g.display.height
            Rotate       = $g.display.rotate
        }
    }
}

<#
.SYNOPSIS
    Reads a mame "folder.ini" format file and displays contained names and sections with descriptions.
.NOTES
    Description will be empty if the name is not supported by the specified mame.exe

    "mame -listfull" output will be cached based on the MAME version, e.g. "mame_listfull_mame0287.clixml"

.EXAMPLE
    .\Convert-MameIniToText.ps1 -Verbose `
      -IniPath 'G:\mame\folders\TOP MAME ARCADE GAMES.ini' `
      -MamePath G:\mame\mame.exe `
      | Where-Object Section -eq 'ROOT_FOLDER' `
      | Select-Object -Property @{Name='Entry'; Expression={"$($_.Description) [$($_.Name)]"}} `
      | Sort-Object Entry
#>
function Convert-MameIniToText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$IniPath,
        [Parameter(Mandatory)][string]$MamePath
    )

    function Get-IniContent {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory)][string]$FilePath
        )

        $section = ''

        switch -Regex -File $FilePath {
            "^\[(.+)\]" {
                $section = $matches[1]
            }
            # Ignore comments
            "^(;.*)$" {
            }
            # Key. Note that typically an ini would be in format "(.+?)\s*=(.*)"
            "^(\w+)" {
                $name = $matches[1]
                # Ignore "FOLDER_SETTINGS" section, as it's folder config, not ROM names.
                if ($section -ne 'FOLDER_SETTINGS') {
                    [PSCustomObject]@{
                        Section = $section
                        Name    = $name
                    }
                }
            }
        }
    }

    function Get-MameListFullLookup {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$MamePath
        )

        try {
            $resolvedMamePath = (Resolve-Path $MamePath -ErrorAction Stop).Path
        }
        catch {
            Write-Warning "Mame EXE not found at $MamePath"
            exit 1
        }
        Write-Verbose "MAME path: $resolvedMamePath"

        if (-not (Test-Path -LiteralPath $resolvedMamePath -PathType Leaf)) {
            Write-Warning "Mame path is not a file: $resolvedMamePath"
            exit 1
        }

        # Parse output of "mame.exe -listfull", with caching keyed by MAME version string.
        $mameVersion = & $resolvedMamePath -version
        if ($mameVersion -match '\((\w+)\)') {
            $cacheKey = $matches[1]
        }
        else {
            Write-Warning "Could not determine MAME version from '$resolvedMamePath'. Verify it is a valid MAME executable."
            exit 1
        }

        Write-Verbose "MAME version: $mameVersion"
        $cacheFile = Join-Path $env:TEMP "mame_listfull_$cacheKey.clixml"

        if (Test-Path $cacheFile) {
            Write-Verbose "Loading ROM list from cache: $cacheFile"
            $list = Import-Clixml $cacheFile
            Write-Verbose "Loaded $($list.Count) ROMs from cache"
            return $list
        }

        Write-Verbose "Cache not found. Running '$resolvedMamePath -listfull' ..."

        # Output format:
        #
        # Name:             Description:
        # 005               "005"
        # 005a              "005 (earlier version?)"
        # 100lions          "100 Lions (10219211, NSW/ACT)"
        $list = @{}
        # "-Skip 1" to skip "Name:             Description:" header.
        & $resolvedMamePath -listfull | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '^(\S+)\s+"(.+)"') {
                $list[$matches[1]] = $matches[2]
            }
        }

        Write-Verbose "Parsed $($list.Count) ROMs. Saving cache to: $cacheFile"
        $list | Export-Clixml $cacheFile
        return $list
    }

    try {
        $IniPath = (Resolve-Path $IniPath -ErrorAction Stop).Path
    }
    catch {
        Write-Warning "Ini file not found at $IniPath"
        exit 1
    }
    Write-Verbose "INI path: $IniPath"

    $list = Get-MameListFullLookup -MamePath $MamePath -Verbose:$VerbosePreference

    #
    # Parse "folder.ini" file.
    #
    Write-Verbose "Parsing INI file: $IniPath"

    Get-IniContent -FilePath $IniPath -Verbose:$VerbosePreference `
    | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            Section     = $_.Section
            Description = if ($list.ContainsKey($_.Name)) { $list[$_.Name] } else { '' }
        }
    }
}

Export-ModuleMember -Function `
    Get-MameListXmlLookup, Get-MameRoms, Invoke-MameUpdate, `
    Get-MameRomList, Convert-MameIniToText

