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
Invoke-MameUpdate -Path 'D:\MAME'
#>
function Update-MAME {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $mameExe = './mame.exe'

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
        Write-Host -ForegroundColor Green 'MAME is already up to date.'
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
