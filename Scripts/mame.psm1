<#
.SYNOPSIS
Returns cached MAME machine metadata as XML.

.DESCRIPTION
Resolves the MAME executable and reads its version using -version. Loads
previously exported XML from a version-specific CLIXML cache, or runs
-listxml and caches the parsed XML when no cache exists.

.PARAMETER MamePath
Required path to the MAME executable.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
System.Xml.XmlDocument
The MAME listxml document.

.EXAMPLE
# Display in "mame -listfull" format.
$xml = Get-MameListXmlLookup -MamePath 'G:\MAME\mame.exe' -Verbose
$xml.mame.machine | Select-Object name, description | ForEach-Object { '{0,-17} "{1}"' -f $_.name, $_.description }
}

.NOTES
Cache files are stored in $env:TEMP as mame_listxml_<version>.clixml.
The executable is required even when a cache exists. An invalid executable
path or an unrecognized version causes return 1.
#>
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
        return 1
    }
    Write-Verbose "MAME path: $resolvedMamePath"

    if (-not (Test-Path -LiteralPath $resolvedMamePath -PathType Leaf)) {
        Write-Warning "Mame path is not a file: $resolvedMamePath"
        return 1
    }

    # Parse output of "mame.exe -listxml", with caching keyed by MAME version string.
    $mameVersion = & $resolvedMamePath -version
    if ($mameVersion -match '\((\w+)\)') {
        # e.g. "mame0287"
        $cacheKey = $matches[1]
    }
    else {
        Write-Warning "Could not determine MAME version from '$resolvedMamePath'. Verify it is a valid MAME executable."
        return 1
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
Loads cached MAME "listxml" output and correlates it with ROM ZIP files
directly in a folder, returning matching metadata objects. Supports modern
machine entries and legacy game entries. Warns about unmatched ZIP files
and drivers whose status is not good.

.PARAMETER RomFolder
Directory containing ROM ZIP files. Defaults to the roms directory under
the current directory. Subdirectories are not searched.

.PARAMETER MameExe
Path to MAME executable. Defaults to ./mame.exe.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject
Objects with Rom, CloneOf, RomOf, Description, Manufacturer, Buttons,
Control, Players, Orientation, Resolution, Year, and Driver properties.

.EXAMPLE
$roms = Get-MameRoms -MameExe 'F:\MAME\mame.exe' -RomFolder 'F:\mame\roms'

$roms |
    Sort-Object Description |
    Format-Table `
        @{Name='Description';Expression={$_.Description.Substring(0,[Math]::Min($_.Description.Length,40))}},`
        @{Name='Manufacturer';Expression={$_.Manufacturer.Substring(0,[Math]::Min($_.Manufacturer.Length,24))}},`
        Year, Rom

.EXAMPLE
Filter the previously loaded ROMs to non-clones with at most six buttons,
horizontal orientation, and joystick or stick controls:

$roms |
    Where-Object {
        $_.cloneof -eq $null -and
        $_.buttons -le 6 -and
        $_.orientation -eq 'horizontal' -and
        ($_.control -like '*joy*' -or $_.control -eq 'stick')
    }

.EXAMPLE
List distinct ROM dependencies, including BIOS dependencies:

$roms | Where-Object RomOf | Select-Object -Unique RomOf

.EXAMPLE
List ROMs requiring more than 5 buttons:

$roms | Where-Object Buttons -gt 5 | Select-Object Rom,Buttons

.EXAMPLE
List clones

$roms | Where-Object CloneOf -ne $null | Select-Object Rom,CloneOf

.NOTES
Uses Get-MameListXmlLookup and its version-specific XML cache in $env:TEMP.
Modern machine entries with runnable="no" are excluded; legacy mame game
entries must have runnable="yes". Clones and ROM dependencies are retained.
#>
function Get-MameRoms {

    [CmdletBinding()]
    param(
        # Path to MAME ROMs.
        [Parameter(Mandatory = $false)]
        [string]$RomFolder = 'roms',

        [Parameter(Mandatory = $false)]
        [string]$MameExe = './mame.exe'
    )

    if (-not (Test-Path -LiteralPath $RomFolder -PathType Container)) {
        Write-Warning "RomFolder not found: $RomFolder"
        return
    }

    # Load XML
    try {
        $advmame = Get-MameListXmlLookup -MamePath $MameExe
    }
    catch {
        Write-Warning "Unable to load MAME XML from ${MameExe}: $_"
        return
    }

    # Determine XML structure
    if ($advmame.mame.machine) {
        $games = $advmame.mame.machine | Where-Object { $_.runnable -ne 'no' }
    }
    elseif ($advmame.mame.game) {
        $games = $advmame.mame.game | Where-Object { $_.runnable -eq 'yes' }
    }
    elseif ($advmame.datafile.game) {
        $games = $advmame.datafile.game
    }
    else {
        Write-Warning "Unexpected XML format from $MameExe"
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
            Buttons      = if ($g.display) { @($g.input.control)[0].buttons } else { $g.input.buttons }
            Control      = if ($g.display) { @($g.input.control)[0].type } else { $g.input.control }
            Players      = $g.input.players
            Orientation  = if ($g.display) { if (@($g.display)[0].rotate -in '90', '270') { 'vertical' } else { 'horizontal' } } else { $g.video.orientation }
            Resolution   = if ($g.display) { '{0}x{1}' -f @($g.display)[0].width, @($g.display)[0].height } else { '{0}x{1}' -f $g.video.width, $g.video.height }
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
GitHub release tag. If the tags differ, downloads the latest Windows x64
self-extracting binary and extracts it using 7-Zip. Prompts to install
MAME if the executable is missing. Reports progress and results to the host.

.PARAMETER Path
Directory containing mame.exe. Defaults to the current directory.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
None. This function does not return objects.

.EXAMPLE
Invoke-MameUpdate

.EXAMPLE
Invoke-MameUpdate -Path 'D:\MAME' -Confirm

.EXAMPLE
Invoke-MameUpdate -Path 'D:\MAME' -WhatIf

.NOTES
Requires 7z.exe on PATH, internet access to GitHub, and write access to the
installation directory and temporary folder. Supports -WhatIf and -Confirm
for downloading and extracting the release; version checks and any initial
installation prompt occur before ShouldProcess. Removes the downloaded
installer after the extraction attempt.
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

    Write-Host "Local MAME version is $localFriendly ($localVersion)"

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
Returns a filtered list of runnable, non-clone MAME arcade candidates.

.DESCRIPTION
Loads XML through Get-MameListXmlLookup and applies best-effort arcade
filters. Excludes clones, BIOS entries, mechanical machines, devices,
software-list machines, explicitly non-runnable entries, LCD/SVG displays,
and entries lacking display or player/control information. Excludes entries
whose first control is a keyboard, keypad, or gambling control. ROM
dependencies and imperfect or preliminary drivers are allowed.

.PARAMETER MameExe
Path to MAME executable. Defaults to ./mame.exe.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject
Objects with Rom, Description, Manufacturer, Year, Players, Control,
Buttons, Resolution, and Rotate properties. Control and Buttons describe
the first input control; Rotate is the display rotation in degrees.

.EXAMPLE
Get-MameRomList

.EXAMPLE
$m = Get-MameRomList -MameExe 'F:\MAME\mame.exe'

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

.NOTES
Uses a version-specific XML cache in $env:TEMP. Requires mame.machine XML
entries. Warns when mameconfig is not 10 but continues processing.
#>
function Get-MameRomList {
    [CmdletBinding()]
    param([string]$MameExe = './mame.exe')

    try {
        $mamexml = Get-MameListXmlLookup -MamePath $MameExe
    }
    catch {
        Write-Warning "Unable to load MAME XML from ${MameExe}: $_"
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
Returns MAME folder.ini entries with their sections and descriptions.

.DESCRIPTION
Parses section headings and machine names from a MAME folder.ini file.
Looks up descriptions using cached mame.exe -listfull output and returns
one object per entry. Ignores semicolon comments and FOLDER_SETTINGS entries.

.PARAMETER IniPath
Required path to the MAME folder.ini file.

.PARAMETER MamePath
Required path to the MAME executable used to look up descriptions.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject
Objects with Name, Section, and Description properties.

.EXAMPLE
Convert-MameIniToText -Verbose `
    -IniPath 'G:\mame\folders\TOP MAME ARCADE GAMES.ini' `
    -MamePath 'G:\mame\mame.exe' `
    | Where-Object Section -eq 'ROOT_FOLDER' `
    | Select-Object -Property @{Name='Entry'; Expression={"$($_.Description) [$($_.Name)]"}} `
    | Sort-Object Entry

.NOTES
Description is empty when the specified MAME version does not recognize a
name. Cache files are stored in $env:TEMP as mame_listfull_<version>.clixml.
An unresolved INI path, an invalid executable path, or an unrecognized MAME
version causes return 1.
#>
function Convert-MameIniToText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$IniPath,
        [Parameter(Mandatory)][string]$MamePath
    )

    <#
    .SYNOPSIS
    Returns section and machine-name entries from a MAME folder.ini file.

    .DESCRIPTION
    Tracks bracketed section headings and reads the leading word characters
    from entry lines. Ignores semicolon comments, blank lines, and entries
    in the FOLDER_SETTINGS section. Entries before any heading have an empty
    Section value.

    .PARAMETER FilePath
    Required path to the INI file to parse.

    .INPUTS
    None. This function does not accept pipeline input.

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    Objects with Section and Name properties.

    .EXAMPLE
    Get-IniContent -FilePath 'G:\mame\folders\favorites.ini'

    .NOTES
    Internal helper available only within Convert-MameIniToText.
    #>
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

    <#
    .SYNOPSIS
    Returns a cached lookup of MAME machine names to descriptions.

    .DESCRIPTION
    Resolves the executable and reads its version using -version. Imports
    a version-specific CLIXML cache if present; otherwise runs -listfull,
    parses machine names and quoted descriptions, and caches the hashtable.

    .PARAMETER MamePath
    Required path to the MAME executable.

    .INPUTS
    None. This function does not accept pipeline input.

    .OUTPUTS
    System.Collections.Hashtable
    A lookup keyed by machine name with description strings as values.

    .EXAMPLE
    $lookup = Get-MameListFullLookup -MamePath 'G:\mame\mame.exe'
    $lookup['pacman']

    .NOTES
    Internal helper available only within Convert-MameIniToText.
    Cache files are stored in $env:TEMP as mame_listfull_<version>.clixml.
    The executable is required even when a cache exists. An invalid
    executable path or an unrecognized version causes return 1.
    #>
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
            return 1
        }
        Write-Verbose "MAME path: $resolvedMamePath"

        if (-not (Test-Path -LiteralPath $resolvedMamePath -PathType Leaf)) {
            Write-Warning "Mame path is not a file: $resolvedMamePath"
            return 1
        }

        # Parse output of "mame.exe -listfull", with caching keyed by MAME version string.
        $mameVersion = & $resolvedMamePath -version
        if ($mameVersion -match '\((\w+)\)') {
            $cacheKey = $matches[1]
        }
        else {
            Write-Warning "Could not determine MAME version from '$resolvedMamePath'. Verify it is a valid MAME executable."
            return 1
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
        return 1
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
    Convert-MameIniToText, `
    Get-MameListXmlLookup, `
    Get-MameRomList, `
    Get-MameRoms, `
    Invoke-MameUpdate
