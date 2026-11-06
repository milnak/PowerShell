<#
.SYNOPSIS
    Normalize audio volume of media files using ffmpeg.

.DESCRIPTION
    Runs ffmpeg's volumedetect filter to determine the peak volume of each
    input file. When the gain needed to reach 0 dB exceeds 1 dB, creates a
    copy named <name>-normalized<extension> beside the input file. Files
    requiring 1 dB or less of gain are skipped.

    Supports -WhatIf and -Confirm. With -InPlace, replaces the original
    after normalization succeeds and removes the temporary backup.

.PARAMETER File
    Path of a media file to normalize. Accepts pipeline strings or objects
    with FullName or Path properties. FullName and Path are parameter aliases.

.PARAMETER InPlace
    When present, original files are replaced with the normalized output.

.INPUTS
    System.String. File paths, or objects with FullName or Path properties.

.OUTPUTS
    System.String. Gain summaries, or ffmpeg diagnostics when processing fails.

.EXAMPLE
    Get-ChildItem '*.mp3' | Invoke-Normalize -InPlace

    Normalizes eligible MP3 files and replaces their originals.

.EXAMPLE
    Invoke-Normalize -File '.\track.flac' -WhatIf

    Previews normalization without running ffmpeg or changing files.

.NOTES
    Requires ffmpeg.exe on PATH, including for -WhatIf. Existing normalized
    output files are overwritten. In-place processing temporarily renames
    the source with a -bak suffix after encoding succeeds.
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
        $resolveditem = Resolve-Path -LiteralPath $File -ErrorAction Stop
        $itemname = Split-Path -Path $File -Leaf | Split-Path -LeafBase
        $itemextension = Split-Path -Path $File -Leaf | Split-Path -Extension
        Write-Verbose "Resolved item: $resolveditem"
        Write-Verbose "Name: $itemname; Extension: $itemextension"

        if (-not $PSCmdlet.ShouldProcess($resolveditem, 'Normalize')) {
            return
        }

        Write-Progress -Activity "Analyzing files" -Status $itemname$itemextension

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
            return
        }

        # Write-verbose $out
        # e.g. "[Parsed_volumedetect_0 @ 0000021cc88cbc00] max_volume: 0.0 dB"
        if ($out -notmatch 'max_volume: (?<max_volume>-?[\d\.]+) dB') {
            Write-Warning "Unable to determine max_volume of $itemname"
            return
        }

        # Gain is inverse of reported max_volume
        $gain = - [decimal]$matches['max_volume']
        Write-Verbose "Calculated gain: $gain dB"
        if ($gain -le 1.0) {
            Write-Verbose "No gain adjustment required for $itemname"
            return
        }
        Write-Progress -Activity "Applying gain" -Status "$itemname$itemextension"

        $tempfile = Join-Path -Path (Split-Path -Path $resolveditem -Parent) -ChildPath "$itemname-normalized$($itemextension)"

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
            return
        }

        Write-Output ("Applied gain of {0:f1} dB to '{1}'" -f $gain, $File)

        if ($InPlace) {
            Write-Verbose "In-place processing for $File"
            $backupItem = "$File-bak"
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
    -HtmlOutput is specified. Files are sorted by track number and grouped
    by directory. The HTML report includes file count, duration, and size totals.

.PARAMETER Path
    Directory to scan for audio files.

.PARAMETER HtmlOutput
    When present, outputs a self-contained HTML report string instead of
    directory groups containing media metadata objects.

.INPUTS
    None. This function does not accept pipeline input.

.OUTPUTS
    Microsoft.PowerShell.Commands.GroupInfo. Directory groups containing metadata.
    System.String. An HTML report when HtmlOutput is specified.

.EXAMPLE
    Convert-MediaInfoToHtml -Path 'D:\Music\Album' | Format-Table

    Displays the directory groups for the scanned audio files.

.EXAMPLE
    Convert-MediaInfoToHtml -Path 'D:\Music' -HtmlOutput | Set-Content report.html

    Saves the recursive music library report as HTML.

.NOTES
    Requires ffprobe.exe on PATH. Metadata values are inserted into HTML as-is,
    without escaping. Only MP3 and FLAC files are included; output is returned
    to the pipeline rather than saved to a report file.
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
        <#
        .SYNOPSIS
            Formats a byte count for the media report.

        .DESCRIPTION
            Selects GB, MB, KB, or B using PowerShell's binary size thresholds.
            Values in GB, MB, and KB use one decimal place and the current culture.

        .PARAMETER Bytes
            Number of bytes to format. Values below 1 KB, including negative
            values, are returned with a B suffix without scaling.

        .INPUTS
            None. This function does not accept pipeline input.

        .OUTPUTS
            System.String. The byte count with a size suffix.

        .EXAMPLE
            Format-Size -Bytes 1536

            Returns 1.5 KB when the current culture uses a decimal point.
        #>
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
.SYNOPSIS
    Converts media files to variable-bitrate MP3 audio.

.DESCRIPTION
    Uses ffmpeg's libmp3lame encoder with a quality level from 0 to 9.
    Video is excluded. By default, writes <name>.mp3 in the current directory.
    Supports -WhatIf and -Confirm.

.PARAMETER Quality
    Variable-bitrate quality level from 0 to 9. Lower values mean higher
    quality. Defaults to 2, approximately 190 kbit/s on average.

.PARAMETER InputFile
    Source media file path. Accepts pipeline objects with an InputFile or
    FullName property, such as FileInfo objects from Get-ChildItem. FullName
    is also a parameter alias; bare strings are not bound from the pipeline.

.PARAMETER OutputFile
    Destination path with a .mp3 extension. Defaults to the input base name
    with a .mp3 extension in the current directory.

.PARAMETER Force
    Overwrites existing output without an ffmpeg overwrite prompt.

.INPUTS
    System.IO.FileInfo, or objects with InputFile or FullName properties.

.OUTPUTS
    System.String. Conversion messages and a count of processed inputs,
    including inputs skipped by -WhatIf or -Confirm.

.EXAMPLE
    ConvertTo-Mp3 -InputFile '.\track.flac'

    Converts track.flac to track.mp3 using the default quality setting.
.EXAMPLE
    ConvertTo-Mp3 -InputFile '.\track.wav' -OutputFile '.\track-v0.mp3' -Quality 0 -Force

    Converts track.wav to track-v0.mp3 using higher-quality VBR settings and
    overwrites the destination if it already exists.
.EXAMPLE
    Get-ChildItem '.\*.wav' -File | ConvertTo-Mp3 -Quality 3

    Converts all WAV files in the current directory to MP3 using pipeline
    input and a lower bitrate setting.

.NOTES
    Requires ffmpeg.exe on PATH with the libmp3lame encoder, including during
    -WhatIf. An explicit OutputFile is reused for every pipeline input.
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

<#
.SYNOPSIS
    Combines audio files into a multi-track file with a .mogg extension.

.DESCRIPTION
    Accepts one or more audio files via the pipeline and encodes them as
    separate audio streams using ffmpeg and the libvorbis codec. Each stream
    is labeled with the source file's base name as its title metadata. The
    destination is named <OggFile>.mogg. Supports -WhatIf and -Confirm.

.PARAMETER File
    Path of one input audio file. Pipe multiple paths or objects with FullName
    or Path properties to collect several files. FullName and Path are aliases.

.PARAMETER OggFile
    Base name (without extension) of the output .mogg file. The .mogg extension
    is appended automatically.

.PARAMETER Force
    Overwrite the output file if it already exists. Without this switch,
    ffmpeg will fail if the destination file is present.

.INPUTS
    System.String. File paths, or objects with FullName or Path properties.

.OUTPUTS
    System.String. A creation summary when ffmpeg succeeds.

.EXAMPLE
    Get-ChildItem -File 'Bertha - *.mp3' | ConvertTo-MultitrackOgg -OggFile 'out'

    Combines all matching MP3 files into out.mogg as separate audio streams.

.EXAMPLE
    'left.flac', 'right.flac' | ConvertTo-MultitrackOgg -OggFile 'stereo-pair'

    Combines two FLAC files into stereo-pair.mogg with separate audio streams.

.NOTES
    Requires ffmpeg.exe on PATH with the libvorbis encoder and a build that
    recognizes the .mogg extension; the command does not specify an output format.
    Collects and resolves all inputs before checking ShouldProcess in end.
#>
function ConvertTo-MultitrackOgg {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,

        [Parameter(Mandatory)]
        [string]$OggFile,

        # Overwrite the output file if it already exists.
        [switch]$Force
    )

    begin {
        Get-Command -Name 'ffmpeg.exe' -CommandType Application -ErrorAction Stop | Out-Null

        Write-Verbose 'Begin'

        $files = [Collections.Generic.List[string]]::new()
    }

    process {
        $path = (Resolve-Path -LiteralPath $File -ErrorAction Stop).Path
        Write-Verbose "Adding '$path'"
        $files.Add($path)
    }

    end {
        if ($files.Count -eq 0) {
            Write-Warning 'No files added'
            return
        }

        $destination = "$OggFile.mogg"

        if (-not $PSCmdlet.ShouldProcess($destination, 'Create multi-track Ogg')) {
            return
        }

        $ffmpegArgs = [Collections.Generic.List[string]]::new()

        # Keep ffmpeg quiet and non-interactive
        $ffmpegArgs.AddRange([string[]]('-loglevel', 'warning', '-hide_banner', '-nostats', '-nostdin'))

        if ($Force) {
            $ffmpegArgs.Add('-y')
        }

        # Specify input files
        for ($track = 0; $track -lt $files.Count; $track++) {
            $ffmpegArgs.Add('-i')
            $ffmpegArgs.Add($files[$track])
        }

        # Map each input to an audio stream
        for ($track = 0; $track -lt $files.Count; $track++) {
            $ffmpegArgs.Add('-map')
            $ffmpegArgs.Add("$($track):a")
        }

        # Specify codec and track title metadata for each stream
        for ($track = 0; $track -lt $files.Count; $track++) {
            $ffmpegArgs.Add("-c:a:$($track)")
            $ffmpegArgs.Add('libvorbis')

            $ffmpegArgs.Add("-metadata:s:a:$($track)")
            $ffmpegArgs.Add('title={0}' -f [IO.Path]::GetFileNameWithoutExtension($files[$track]))
        }

        $ffmpegArgs.Add($destination)

        Write-Verbose ($ffmpegArgs -join ' ')

        & ffmpeg.exe @ffmpegArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Output "Created '$destination' with $($files.Count) audio track(s)."
        }
        else {
            Write-Warning "ffmpeg exited with code $LASTEXITCODE"
        }

        Write-Verbose 'End'
    }
}

<#
.SYNOPSIS
    Mixes vocal and instrumental stems with reduced vocal volume.

.DESCRIPTION
    Uses ffmpeg to reduce the vocal stem to 15 percent of its original
    amplitude and mix it with the instrumental stem. Mix normalization is
    disabled. Intended for stems produced by UVR5; defaults to MP3 output.

.PARAMETER VocalsFile
    Path of the vocal stem.

.PARAMETER InstrumentalFile
    Path of the instrumental stem.

.PARAMETER OutputFile
    Destination file path. Defaults to stems-merged.mp3 in the current
    directory. ffmpeg infers the output format from the extension.

.PARAMETER Force
    Overwrites an existing output file without prompting.

.INPUTS
    None. This function does not accept pipeline input.

.OUTPUTS
    System.String. A creation message when ffmpeg succeeds.

.EXAMPLE
    Convert-StemsToMp3 -VocalsFile 'vocals.wav' -InstrumentalFile 'instrumental.wav' -OutputFile 'merged.mp3'

    Creates merged.mp3 with reduced vocal volume and the instrumental stem.

.NOTES
    Requires ffmpeg.exe on PATH. Does not support -WhatIf or -Confirm.
    Input paths are passed directly to ffmpeg; the output extension selects
    the container, so OutputFile is not restricted to MP3.
#>
function Convert-StemsToMp3 {
    param(
        # Vocal file, split using UVR5
        [parameter(Mandatory)]
        [string]$VocalsFile,

        # Instrumental file, split using UVR5
        [parameter(Mandatory)]
        [string]$InstrumentalFile,

        # File to write to
        [string]$OutputFile = 'stems-merged.mp3',

        # Force overwrite of output file if it exists
        [switch]$Force
    )

    # Ensure ffmpeg is available before processing any files
    Get-Command -Name 'ffmpeg.exe' -CommandType Application -ErrorAction Stop | Out-Null

    $ffmpeg_args = @()
    if ($Force) {
        # overwrite output files
        $ffmpeg_args += '-y'
    }
    $ffmpeg_args += @(
        # Don't show banner
        '-hide_banner',
        # Show panic,fatal,error,warning only
        '-v', 'warning',
        # disable console itneraction
        '-nostdin',
        # Input files
        '-i', $VocalsFile,
        '-i', $InstrumentalFile,
        # apply specified filters
        '-filter_complex', '[0:a]volume=0.15[a1];[a1][1:a]amix=inputs=2:normalize=0[out]',
        # set mapping
        '-map', '[out]',
        # Output file
        $OutputFile
    )

    & ffmpeg.exe @ffmpeg_args
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Created '$OutputFile'."
    }
    else {
        Write-Host -ForegroundColor Red "ffmpeg exited with code $LASTEXITCODE"
    }
}

<#
.SYNOPSIS
    Converts video files to looping animated GIFs.

.DESCRIPTION
    Uses ffmpeg to generate a palette and convert video to a GIF at 10 frames
    per second and 240 pixels high, preserving the aspect ratio. The GIF
    loops indefinitely and is saved beside the source with .gif appended
    to its full name, such as clip.mp4.gif. Supports -WhatIf and -Confirm.

.PARAMETER File
    Source video path. Accepts pipeline strings or objects with FullName or
    Path properties. FullName and Path are parameter aliases.

.PARAMETER Force
    Overwrites an existing GIF without prompting. Without this switch,
    ffmpeg fails if the destination exists.

.INPUTS
    System.String. File paths, or objects with FullName or Path properties.

.OUTPUTS
    System.String. A creation message for each successful conversion.

.EXAMPLE
    ConvertTo-Gif -File '.\clip.mp4'

    Creates clip.mp4.gif beside the source video.

.EXAMPLE
    Get-ChildItem '.\*.mp4' -File | ConvertTo-Gif -Force

    Converts matching videos and overwrites their existing GIF outputs.

.NOTES
    Requires ffmpeg.exe on PATH, including during -WhatIf. Resolves literal
    source paths before checking ShouldProcess.
#>
function ConvertTo-Gif {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,

        [switch]$Force
    )

    begin {
        Get-Command -Name 'ffmpeg.exe' -CommandType Application -ErrorAction Stop | Out-Null

        Write-Verbose 'Begin'
    }

    process {
        $path = (Resolve-Path -LiteralPath $File -ErrorAction Stop).Path
        Write-Verbose "Adding '$path'"

        $destination = "$($path).gif"

        if (-not $PSCmdlet.ShouldProcess($destination, 'Convert to GIF')) {
            return
        }

        $ffmpegArgs = [Collections.Generic.List[string]]::new()

        # Keep ffmpeg quiet and non-interactive
        $ffmpegArgs.AddRange([string[]]('-loglevel', 'warning', '-hide_banner', '-nostats', '-nostdin'))

        if ($Force) {
            $ffmpegArgs.Add('-y')
        }

        $ffmpegArgs.Add('-i')
        $ffmpegArgs.Add($path)

        $ffmpegArgs.Add('-vf')
        $ffmpegArgs.Add('fps=10,scale=-1:240:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse')
        $ffmpegArgs.Add('-loop')
        $ffmpegArgs.Add('0')

        $ffmpegArgs.Add($destination)

        Write-Verbose ($ffmpegArgs -join ' ')

        & ffmpeg.exe @ffmpegArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Output "Created '$destination'."
        }
        else {
            Write-Warning "ffmpeg exited with code $LASTEXITCODE"
        }
    }

    end {
        Write-Verbose 'End'
    }
}

<#
.SYNOPSIS
    Shifts audio pitch by semitones or between musical keys.

.PARAMETER SourceFile
    Source media file path.

.PARAMETER TargetFile
    Destination file path. ffmpeg infers the output format from its extension.

.PARAMETER Force
    Overwrites an existing destination without prompting.

.PARAMETER Semitones
    Signed number of semitones to shift. Positive values raise the pitch;
    negative values lower it. Cannot be combined with SourceKey or TargetKey.

.PARAMETER SourceKey
    Original key as a natural note, sharp, or flat, such as C, F#, or Bb.
    Required with TargetKey instead of Semitones.

.PARAMETER TargetKey
    Desired key as a natural note, sharp, or flat. Required with SourceKey.
    Enharmonic equivalents, such as C# and Db, map to the same pitch.

.EXAMPLE
    Invoke-PitchShift -SourceFile '.\song.mp3' -TargetFile '.\song-lower.mp3' -Semitones -2

    Lowers the pitch by two semitones with tempo compensation.

.EXAMPLE
    Invoke-PitchShift -SourceFile '.\song.flac' -TargetFile '.\song-in-d.flac' -SourceKey C -TargetKey D -Force

    Raises the pitch from C to D and overwrites an existing destination.

.NOTES
    Requires ffprobe.exe and ffmpeg.exe on PATH. Does not support -WhatIf
    or -Confirm. Large shifts are subject to ffmpeg's audio filter limits.
#>
function Invoke-PitchShift {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$TargetFile,

        [switch]$Force,

        [Parameter(Mandatory, ParameterSetName = 'Semitones')]
        [int]$Semitones,

        [Parameter(Mandatory, ParameterSetName = 'Keys')]
        [ValidateSet('A', 'B', 'C', 'D', 'E', 'F', 'G', 'Ab', 'Bb', 'Db', 'Eb', 'Gb', 'A#', 'C#', 'D#', 'F#', 'G#')]
        [string]$SourceKey,
        [ValidateSet('A', 'B', 'C', 'D', 'E', 'F', 'G', 'Ab', 'Bb', 'Db', 'Eb', 'Gb', 'A#', 'C#', 'D#', 'F#', 'G#')]
        [Parameter(Mandatory, ParameterSetName = 'Keys')]
        [string]$TargetKey
    )

    function Get-Semitones {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory)]
            [ValidateSet('A', 'B', 'C', 'D', 'E', 'F', 'G', 'Ab', 'Bb', 'Db', 'Eb', 'Gb', 'A#', 'C#', 'D#', 'F#', 'G#')]
            [string]$SourceKey,

            [Parameter(Mandatory)]
            [ValidateSet('A', 'B', 'C', 'D', 'E', 'F', 'G', 'Ab', 'Bb', 'Db', 'Eb', 'Gb', 'A#', 'C#', 'D#', 'F#', 'G#')]
            [string]$TargetKey
        )

        # Distance in semitones from "C".
        $notePositions = @{
            'C' = 0
            'C#' = 1; 'Db' = 1
            'D' = 2
            'D#' = 3; 'Eb' = 3
            'E' = 4
            'F' = 5
            'F#' = 6; 'Gb' = 6
            'G' = 7
            'G#' = 8; 'Ab' = 8
            'A' = 9
            'A#' = 10; 'Bb' = 10
            'B' = 11
        }

        # Returns difference within -6 to 6 semitones.
        #                 / semitones + 12, semitones < -6,
        # f(semitones) = |  semitones,      -6 <= semitones <= 6
        #                 \ semitones - 12, semitones > 6,
        $semitones = $notePositions[$TargetKey] - $notePositions[$SourceKey]
        if ($semitones -lt -6) {
            $semitones += 12
        }
        elseif ($semitones -gt 6) {
            $semitones -= 12
        }
        return $semitones
    }

    if ($PSCmdlet.ParameterSetName -eq 'Keys') {
        $Semitones = Get-Semitones -SourceKey $SourceKey -TargetKey $TargetKey
        Write-Verbose "$SourceKey -> $TargetKey; Calculated semitones: $Semitones"
    }

    if ($Semitones -eq 0) {
        Write-Host "No pitch shift needed."
        return
    }

    # Ensure tools are available before processing any files
    'ffprobe.exe', 'ffmpeg.exe' | ForEach-Object {
        Get-Command -Name $_ -CommandType Application -ErrorAction Stop | Out-Null
    }

    $ffprobe_args = @(
        '-hide_banner',
        '-v', 'error',
        '-show_entries', 'stream=index,sample_rate',
        '-of', 'json',
        $SourceFile
    )
    $ffprobeOutput = ffprobe.exe @ffprobe_args | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "ffprobe exited with code $LASTEXITCODE"
        return
    }

    $sample_rate = $ffprobeOutput.streams | Where-Object { $_.sample_rate }
    if ($sample_rate.Count -gt 1) {
        Write-Host "Multiple sample rates found. Cannot continue."
        return
    }
    $sample_rate = $sample_rate[0].sample_rate

    [float]$PITCH_RATIO = [math]::Pow(2, $Semitones / 12)
    [float]$TEMPO_CORRECTION = 1 / $PITCH_RATIO

    $af = 'asetrate={0}*{1},atempo={2}' -f $sample_rate, $PITCH_RATIO, $TEMPO_CORRECTION
    Write-Host "Sample rate: $sample_rate; Applying audio filter: $af"

    $ffmpeg_args = @(
        '-hide_banner',
        '-i', $SourceFile,
        '-stats',
        '-loglevel', 'warning',
        '-nostdin',
        '-af', $af
    )
    if ($Force) {
        $ffmpeg_args += '-y'
    }
    $ffmpeg_args += $TargetFile

    Write-Verbose ("Starting ffmpeg with arguments: $($ffmpeg_args -join ' ')")

    ffmpeg.exe @ffmpeg_args
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "ffmpeg exited with code $LASTEXITCODE"
        return
    }
}

Export-ModuleMember -Function `
    Convert-MediaInfoToHtml, `
    Convert-StemsToMp3, `
    ConvertTo-Gif, `
    ConvertTo-Mp3, `
    ConvertTo-MultitrackOgg, `
    Invoke-Normalize, `
    Invoke-PitchShift, `
    Get-Semitones
