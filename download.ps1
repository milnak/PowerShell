<#
.SYNOPSIS
Download best quality video and audio into default container.
.NOTES
yt-dlp now supports preset aliases: '-f mp3', '-f aac', '-t mp4', '-t mkv'
#>
function Invoke-YtDlp {

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


<#
.SYNOPSIS
Download file (including torrents) using ARIA
#>
function Invoke-Aria {
    param([Parameter(Mandatory)] [string]$Source)
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
}

function Update-PowerShell {
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
        $response = Invoke-WebRequest -Uri $downloadUri -OutFile $outFile
    }
    finally {
        $global:ProgressPreference = $prevProgressPreference
    }

    Write-Host "Installing PowerShell: $outFile"
    msiexec.exe /i $outFile /passive
}
