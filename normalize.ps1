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

        $tempfile = Join-Path -Path (Get-Location) -ChildPath "$itemname-normalized$($itemextension)"
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
            Rename-Item -LiteralPath $tempfile -NewName $resolveditem -ErrorAction Stop
            Remove-Item -LiteralPath $backupItem -ErrorAction SilentlyContinue
        }
    }

    end {}
}

