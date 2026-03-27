<#
.SYNOPSIS
    Download best quality video and audio into default container.
.NOTES
    yt-dlp now supports preset aliases: '-f mp3', '-f aac', '-t mp4', '-t mkv'
.PARAMETER Audio
    Download audio only. Requires -Format.
.PARAMETER Video
    Download video with best available audio.
.PARAMETER Uri
    URL of the media to download.
.PARAMETER Format
    Audio format to extract when using -Audio (e.g. mp3, flac, wav).
#>
function Invoke-YtDlp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Audio')]
        [switch]$Audio,

        [Parameter(Mandatory = $true, ParameterSetName = 'Video')]
        [switch]$Video,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        # Audio parameters
        [Parameter(Mandatory = $true, ParameterSetName = 'Audio')]
        [ValidateSet('best', 'aac', 'alac', 'flac', 'm4a', 'mp3', 'opus', 'vorbis', 'wav')]
        [string]$Format
    )

    begin {
        Get-Command -Name 'yt-dlp.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
    # If the Uri is a Facebook redirect, then parse the redirect query string to get the actual URL
    if (([Uri]$Uri).Host -like '*.facebook.com') {
        $Uri = [Web.HttpUtility]::ParseQueryString([Uri]([Web.HttpUtility]::UrlDecode($Uri)))[0]
        Write-Warning "Facebook Uri redirects to: $Uri"
    }

    # Common args
    $ytdlp_args = `
        '--windows-filenames', `
        '--ignore-config', `
        '--progress', `
        '--no-simulate', `
        # '--progress-template', '"download:[download] %(progress.downloaded_bytes)s/%(progress.total_bytes)s ETA:%(progress.eta)s"', `
        '--output-na-placeholder', 'NA',
    '--no-playlist'

    if ($Audio) {
        $ytdlp_args += `
            '--extract-audio', `
            '--audio-format', $Format
    }
    elseif ($Video) {
        # '--format', 'bestvideo[ext=mp4][vcodec^=avc]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best[ext=mp4]/best'

        $ytdlp_args += `
            '--format', '"bv*+ba"', '--embed-metadata'
    }

    # Cookies (if file exists)
    $cookieFile = Resolve-Path -LiteralPath '~/cookies.txt' -ErrorAction SilentlyContinue
    if ($cookieFile) {
        Write-Warning "Using cookies file $cookieFile"
        $ytdlp_args += '--cookies', """$cookieFile"""
    }

    if ($Uri -like '*list=*') {
        # Playlist arguments
        $response = Read-Host "Playlist detected - are you sure? ('`e[1myes`e[0m' to confirm)"
        if ($response -ne 'yes') {
            return
        }

        # To get name of playlist:
        # yt-dlp.exe --no-warnings --playlist-start 1 --playlist-end 1 --print '%(channel)s/%(playlist_title)s' $Uri

        $ytdlp_args += `
            '--print', '"[%(playlist_index)d/%(n_entries+1)d] %(title).200s"', `
            '--output', '"%(channel)s/%(playlist_title)s/%(title).200s [%(id)s].%(ext)s"'
    }
    else {
        # Single file download arguments
        $ytdlp_args += `
            '--print', '"%(title).200s [%(id)s]"' , `
            '--output', '"%(title).200s [%(id)s].%(ext)s"'
    }

    $ytdlp_args += """$Uri"""
    Write-Verbose ('Arguments: {0}' -f ($ytdlp_args -join ' '))
    Start-Process -FilePath 'yt-dlp.exe' -ArgumentList $ytdlp_args -NoNewWindow -Wait
    }
}


<#
.SYNOPSIS
    Download file (including torrents) using ARIA.
.DESCRIPTION
    Wraps aria2c.exe with sensible defaults for concurrent HTTP/FTP downloads
    and BitTorrent. Supports resuming interrupted downloads, split connections,
    and magnet links or torrent files in addition to plain URIs.
.PARAMETER Source
    The URI, magnet link, or path to a torrent/metalink file to download.
.EXAMPLE
    Invoke-Aria -Source 'https://example.com/file.zip'
.EXAMPLE
    Invoke-Aria -Source 'magnet:?xt=urn:btih:...'
#>
function Invoke-Aria {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source
    )

    begin {
        Get-Command -Name 'aria2c.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
    # Can also use "aria2.conf" file.

    $ariaArgs = @()

    ## Basic Options
    $ariaArgs += `
        '--continue=true', `
        '--max-concurrent-downloads=5'

    ## HTTP/FTP Options
    $ariaArgs += `
        '--max-connection-per-server=4', `
        '--max-tries=50', `
        '--min-split-size=20M', `
        '--retry-wait=30', `
        '--split=4'

    ## BitTorrent Specific Options
    $ariaArgs += `
        '--enable-dht=true', `
        '--seed-time=0'

    ## Advanced Options
    $ariaArgs += `
        '--allow-piece-length-change=true', `
        '--console-log-level=warn', `
        '--disk-cache=32M', `
        '--disable-ipv6=true', `
        '--file-allocation=none', `
        '--summary-interval=120'

    ## URI/MAGNET/TORRENT_FILE/METALINK_FILE
    $ariaArgs += `
        $Source

    Start-Process -FilePath 'aria2c.exe' -ArgumentList $ariaArgs -NoNewWindow -Wait
    }
}

<#
.SYNOPSIS
Downloads a webpage (and its requisites) into a timestamped folder using wget.

.PARAMETER Domain
The domain name to download, e.g. "example.com".

.PARAMETER WgetCommand
Path or name of the wget executable. Defaults to "wget.exe".

.EXAMPLE
Get-WebPage -Domain "example.com"

.EXAMPLE
Get-WebPage -Domain "mysite.org" -WgetCommand "C:\Tools\wget.exe"
#>

function Get-WebPage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Domain,

        [string]$WgetCommand = 'wget.exe'
    )

    # Validate wget exists
    try {
        $null = Get-Command -Name $WgetCommand -CommandType Application -ErrorAction Stop
    }
    catch {
        throw "wget command not found: $WgetCommand"
    }

    # Build target folder name
    $TargetPath = '{0}_{1}' -f $Domain, (Get-Date -Format 'yyMMdd')

    if (Test-Path -LiteralPath $TargetPath) {
        throw "Target path '$TargetPath' already exists."
    }

    # Create folder
    $null = New-Item -ItemType Directory -Path $TargetPath -ErrorAction Stop

    Push-Location $TargetPath
    try {
        # Build wget arguments
        $wgetArgs = @(
            '--exclude-domains=googleapis.com,youtube.com'
            '--span-hosts'
            '--convert-links'
            '--level=inf'
            '--no-verbose'
            '--page-requisites'
            '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Safari/537.36 Edge/15.15063'
            "http://$Domain"
        )

        # Run wget
        $process = Start-Process -FilePath $WgetCommand `
            -ArgumentList $wgetArgs `
            -NoNewWindow `
            -Wait `
            -PassThru

        if ($process.ExitCode -ne 0) {
            throw "wget failed with exit code $($process.ExitCode)"
        }
    }
    finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
Download binaries by extension from a web page.
#>
function Get-WebPageBinaries {
    [CmdletBinding()]
    param(
        # Uri of page to download from.
        [Parameter(Mandatory)] [uri]$Uri,
        # Extensions to download
        [string[]]$Extensions = @('htm', 'html', 'zip', 'pdf', 'mp3', 'mid'),
        # Maximum recursion depth, 0=infinite
        [int]$Depth = 1
    )

    begin {
        Get-Command -Name 'wget.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
    wget.exe `
        --verbose `
        --no-parent `
        --recursive `
        --level=$Depth `
        --continue `
        --timestamping `
        --execute robots=off `
        --accept=$($Extensions -join ',') `
        --user-agent='Mozilla/5.0 (iPhone; CPU iPhone OS 9_1 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) CriOS/52.0.2725.0 Mobile/13B143 Safari/601.1.46' `
        $Uri
    } # end process
}

<#
.SYNOPSIS
    Download the latest PowerShell MSI release.
.DESCRIPTION
    Queries the GitHub releases API for the latest PowerShell release and
    downloads the x64 MSI installer to the specified folder. Progress
    preference is suppressed during download for performance.
.PARAMETER Folder
    Destination directory where the MSI will be saved. Must already exist.
.EXAMPLE
    DownloadLatestPS -Folder 'C:\Downloads'
#>
function DownloadLatestPS {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string]$Folder)

    # Speed up Invoke-WebRequest calls
    $oldpp = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        $json = (Invoke-WebRequest -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -ErrorAction Stop).Content | ConvertFrom-Json
    }
    catch {
        throw "Failed to query GitHub releases API: $_"
    }

    $psUri = [uri]($json.assets | Where-Object name -Like 'PowerShell-*-win-x64.msi').browser_download_url

    "Downloading: $($psUri.AbsoluteUri)"

    try {
        Invoke-WebRequest $psUri.AbsoluteUri -OutFile (Join-Path $Folder $psuri.Segments[-1]) -ErrorAction Stop
    }
    catch {
        throw "Failed to download PowerShell MSI from '$($psUri.AbsoluteUri)': $_"
    }
    finally {
        $ProgressPreference = $oldpp
    }
}


<#
.SYNOPSIS
    Install the latest PowerShell release for the current architecture.
.DESCRIPTION
    Queries the PowerShell metadata API to determine the latest release version,
    compares it to the running version, and silently downloads and launches the
    MSI installer if an update is available.
#>
function Update-PowerShell {
    [CmdletBinding()]
    param()
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { $architecture = "x64" }
        "x86" { $architecture = "x86" }
        default { throw "PowerShell package for OS architecture '$_' is not supported." }
    }

    $metadata = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/metadata.json'
    # e.g. "ReleaseTag          : v7.6.0"
    $release = [version]($metadata.ReleaseTag -replace '^v', '')
    $psversion = $PSVersionTable.PSVersion

    if ($psversion -ge $release) {
        Write-Host -ForegroundColor Green "Current PowerShell version $psversion is up to date."
        return
    }

    $packageName = "PowerShell-${release}-win-${architecture}.msi"
    $packagePath = "v${release}/${packageName}"
    Write-Host "Downloading PowerShell: $packagePath"
    $downloadUri = "https://github.com/PowerShell/PowerShell/releases/download/$packagePath"
    $outFile = Join-Path -Path $env:tmp -ChildPath $packageName

    $prevProgressPreference = $global:ProgressPreference
    $global:ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $downloadUri -OutFile $outFile
    }
    finally {
        $global:ProgressPreference = $prevProgressPreference
    }

    Write-Host "Installing PowerShell: $outFile"
    msiexec.exe /i $outFile /passive
}
