<#
.SYNOPSIS
    Normalize audio volume of media files using ffmpeg.

.DESCRIPTION
    Runs ffmpeg's volumedetect filter to determine the peak volume of each
    input file. If the peak is above 0 dB, computes a gain to normalize the
    audio and creates a normalized copy. Optionally replaces the original
    file in-place when the `-InPlace` switch is provided.

    The function supports the common -WhatIf/-Confirm powershell verbs and
    requires ffmpeg.exe to be available on the PATH.

.PARAMETER Path
    One or more file paths to normalize. Can be piped in or supplied as
    positional arguments.

.PARAMETER InPlace
    When present, original files are replaced with the normalized output.

.EXAMPLE
    Get-ChildItem '*.mp3' | Invoke-Normalize -InPlace
#>
function Invoke-Normalize {
    # Support -Confirm (ShouldProcess), -WhatIf
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,

        [switch]$InPlace
    )

    begin {
        # Ensure ffmpeg is available before processing any files
        Get-Command -Name 'ffmpeg.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
        Write-Verbose ('-' * 79)
        $resolveditem = Resolve-Path -LiteralPath $File -ErrorAction Stop
        $itemname = Split-Path -Path $File -Leaf | Split-Path -LeafBase
        $itemextension = Split-Path -Path $File -Leaf | Split-Path -Extension
        Write-Verbose "Resolved item: $resolveditem"
        Write-Verbose "Name: $itemname; Extension: $itemextension"

        if (-not $PSCmdlet.ShouldProcess($resolveditem, 'Normalize')) {
            continue
        }

        $ffmpeg_args = `
            # Overwrite output files.
            '-y', `
            # Don't show banner
            '-hide_banner', `
            # disable console itneraction
            '-nostdin', `
            # Input file
            '-i', """$resolveditem""", `
            # set audio filters
            '-af', '"volumedetect"', `
            # disable video
            '-vn', `
            # disable subtitle
            '-sn', `
            # disable data
            '-dn', `
            # force format
            '-f', 'null', `
            # No output file
            '-'

        $startinfo = New-Object System.Diagnostics.ProcessStartInfo
        $startinfo.FileName = 'ffmpeg.exe'
        # FFMPEG writes to stderr!
        $startinfo.RedirectStandardError = $true
        $startinfo.RedirectStandardOutput = $false
        $startinfo.UseShellExecute = $false
        $startinfo.Arguments = $ffmpeg_args
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $startinfo
        Write-Verbose "Running ffmpeg with arguments: $($ffmpeg_args -join ' ')"
        $proc.Start() | Out-Null
        Write-Verbose 'ReadToEnd...'
        $out = $proc.StandardError.ReadToEnd()
        Write-Verbose 'WaitForExit...'
        $proc.WaitForExit()
        Write-Verbose "ffmpeg exited with code $($proc.ExitCode)"
        if ($proc.ExitCode -ne 0) {
            Write-Warning "ffmpeg failed with code $($proc.ExitCode)"
            $out
            continue
        }

        # Write-verbose $out
        # e.g. "[Parsed_volumedetect_0 @ 0000021cc88cbc00] max_volume: 0.0 dB"
        if ($out -notmatch 'max_volume: (?<max_volume>-?[\d\.]+) dB') {
            Write-Warning "Unable to determine max_volume of $resolveditem"
            continue
        }

        # Gain is inverse of reported max_volume
        $gain = - [decimal]$matches['max_volume']
        if ($gain -le 1.0) {
            Write-Output "No gain adjustment required for $resolveditem"
            continue
        }

        $tempfile = Join-Path -Path (Split-Path -LiteralPath $resolveditem -Parent) -ChildPath "$itemname-normalized$($itemextension)"
        Write-Output "Applying gain of $gain dB to $resolveditem"

        $ffmpeg_args = `
            # Overwrite output files.
            '-y', `
            # Don't show banner
            '-hide_banner', `
            # disable console itneraction
            '-nostdin', `
            # Input file
            '-i', """$resolveditem""", `
            # set audio filters
            '-af', """volume=$($gain)dB""", `
            # Output file
            """$tempfile"""

        $startinfo = New-Object System.Diagnostics.ProcessStartInfo
        $startinfo.FileName = 'ffmpeg.exe'
        # FFMPEG writes to stderror!
        $startinfo.RedirectStandardError = $true
        $startinfo.RedirectStandardOutput = $false
        $startinfo.UseShellExecute = $false
        $startinfo.Arguments = $ffmpeg_args
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $startinfo
        Write-Verbose "Running ffmpeg with arguments: $($ffmpeg_args -join ' ')"
        $proc.Start() | Out-Null
        Write-Verbose 'ReadToEnd...'
        $out = $proc.StandardError.ReadToEnd() -split "`r`n"
        Write-Verbose 'WaitForExit...'
        $proc.WaitForExit()
        Write-Verbose "ffmpeg exited with code $($proc.ExitCode)"
        if ($proc.ExitCode -ne 0) {
            Write-Warning "ffmpeg failed with code $($proc.ExitCode)"
            $out
            Remove-Item $tempfile -ErrorAction SilentlyContinue
            continue
        }

        if ($InPlace) {
            $backupItem = "$itemname-backup$itemextension"
            Rename-Item -LiteralPath $resolveditem -NewName $backupItem -ErrorAction Stop
            Move-Item -LiteralPath $tempfile -Destination $resolveditem -Force -ErrorAction Stop
            Remove-Item -LiteralPath $backupItem -ErrorAction SilentlyContinue
        }
    }

    end {}
}

<#
.SYNOPSIS
    Generate a media metadata report from a directory of audio files.
.DESCRIPTION
    Scans a directory recursively for MP3 and FLAC files and extracts metadata
    (artist, album, title, year, genre, track, bitrate, duration, size) using
    ffprobe. Returns grouped objects by default, or a full HTML report when
    -HtmlOutput is specified.
.PARAMETER Path
    Directory to scan for audio files.
.PARAMETER HtmlOutput
    When present, outputs a self-contained HTML report string instead of
    grouped PSCustomObjects.
.EXAMPLE
    Convert-MediaInfoToHtml -Path 'D:\Music\Album' | Format-Table
.EXAMPLE
    Convert-MediaInfoToHtml -Path 'D:\Music' -HtmlOutput | Set-Content report.html
#>
function Convert-MediaInfoToHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$HtmlOutput
    )

    begin {
        Get-Command -Name 'ffprobe.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
    function Format-Size {
        param(
            [Parameter(Mandatory)][double]$Bytes
        )

        switch ([math]::Max($Bytes, 0)) {
            { $_ -ge 1GB } { return "{0:N1} GB" -f ($Bytes / 1GB) }
            { $_ -ge 1MB } { return "{0:N1} MB" -f ($Bytes / 1MB) }
            { $_ -ge 1KB } { return "{0:N1} KB" -f ($Bytes / 1KB) }
            default { return "$Bytes B" }
        }
    }

    # Collect metadata
    $files = Get-ChildItem -Path $Path -File -Recurse -Include '*.mp3', '*.flac' |
    ForEach-Object {
        $metadata = ffprobe.exe -loglevel quiet `
            -show_entries stream=bit_rate `
            -show_format `
            -print_format json `
            $_.FullName | ConvertFrom-Json

        [PSCustomObject]@{
            Name          = $_.Name
            DirectoryName = $_.DirectoryName
            Artist        = $metadata.format.tags.artist
            Album         = $metadata.format.tags.album
            Title         = $metadata.format.tags.title
            Year          = $metadata.format.tags.date
            Genre         = $metadata.format.tags.genre
            Track         = [int]$metadata.format.tags.track
            Size          = [double]$metadata.format.size
            Duration      = [TimeSpan]::FromSeconds([Math]::Round($metadata.format.duration))
            BitRate       = @($metadata.streams.bit_rate)[0] / 1000
        }
    }

    if (-not $HtmlOutput) {
        return $files | Sort-Object Track | Group-Object DirectoryName
    }

    # Prepare totals
    $TotalCount = $files.Count
    $TotalDurationSeconds = ($files.Duration.TotalSeconds | Measure-Object -Sum).Sum
    $TotalSize = ($files.Size | Measure-Object -Sum).Sum
    $TotalTimeSpan = [TimeSpan]::FromSeconds($TotalDurationSeconds)

    # Build HTML rows
    $rows = foreach ($group in $files | Sort-Object Track | Group-Object DirectoryName) {

        # Directory header row
        @"
<tr bgcolor="#E9E3C7">
    <td colspan="10"><font face="Verdana" size="2">$($group.Name)</font></td>
</tr>
"@

        # File rows
        foreach ($item in $group.Group) {
            @"
<tr bgcolor="#C4CEDF">
    <td><font face="Verdana" size="2">$($item.Name)</font></td>
    <td><font face="Verdana" size="2">$($item.Artist)</font></td>
    <td><font face="Verdana" size="2">$($item.Album)</font></td>
    <td><font face="Verdana" size="2">$($item.Title)</font></td>
    <td><font face="Verdana" size="2">$($item.Year)</font></td>
    <td><font face="Verdana" size="2">$($item.Genre)</font></td>
    <td align="right"><font face="Verdana" size="2">$($item.Track)</font></td>
    <td align="right"><font face="Verdana" size="2">$($item.BitRate)</font></td>
    <td align="right"><font face="Verdana" size="2">$($item.Duration.ToString('mm\:ss'))</font></td>
    <td align="right"><font face="Verdana" size="2">$(Format-Size $item.Size)</font></td>
</tr>
"@
        }
    }

    # Totals row
    $totalRow = @"
<tr bgcolor="#E9E3C7">
    <td colspan="10" align="center">
        <b><font face="Verdana" size="2">
            Total files: $TotalCount &nbsp;&nbsp;
            Total duration: $('{0}:{1:d2}:{2:d2}' -f ($TotalTimeSpan.Days*24 + $TotalTimeSpan.Hours), $TotalTimeSpan.Minutes, $TotalTimeSpan.Seconds) &nbsp;&nbsp;
            Total size: $(Format-Size $TotalSize)
        </font></b>
    </td>
</tr>
"@

    # Final HTML
    @"
<html>
<head>
<title>Music files report</title>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
</head>

<body bgcolor="#5E7CB0" text="#000000">
<table width="100%" border="0" align="center" cellpadding="2" cellspacing="2" bgcolor="#A2B6D7">

<tr bgcolor="#CCCCCC">
    <td><b><font face="Verdana" size="2">File name</font></b></td>
    <td><b><font face="Verdana" size="2">Artist</font></b></td>
    <td><b><font face="Verdana" size="2">Album</font></b></td>
    <td><b><font face="Verdana" size="2">Title</font></b></td>
    <td><b><font face="Verdana" size="2">Year</font></b></td>
    <td><b><font face="Verdana" size="2">Genre</font></b></td>
    <td align="right"><b><font face="Verdana" size="2">#</font></b></td>
    <td align="right"><b><font face="Verdana" size="2">Bitrate</font></b></td>
    <td align="right"><b><font face="Verdana" size="2">Duration</font></b></td>
    <td align="right"><b><font face="Verdana" size="2">File size</font></b></td>
</tr>

$rows
$totalRow

</table>

<p align="center">
    <a href="https://learn.microsoft.com/en-us/powershell/" target="_blank">
        <font face="Verdana" size="1">Report generated with PowerShell</font>
    </a>
</p>

</body>
</html>
"@
    } # end process
}


<#
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
    [CmdletBinding(SupportsShouldProcess)]
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
        Get-Command -Name 'ffmpeg.exe' -CommandType Application -ErrorAction Stop | Out-Null
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

        if ($PSCmdlet.ShouldProcess($InputFile, 'Convert to MP3')) {
            # ffmpeg always seems to return 0 in ExitCode, so no way to check for failures, even with "-PassThru".
            Start-Process -FilePath 'ffmpeg.exe' -ArgumentList $ffmpeg_args -NoNewWindow -Wait
        }

        $count++
    }

    end {
        "Processed $count files."
    }
}
