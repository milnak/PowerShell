<#
.SYNOPSIS
    Extract PDFs and audio from a MuseScore (.mscz) project file.

.DESCRIPTION
    Uses MuseScore's command‑line interface to export score PDFs, part PDFs,
    and optionally audio, from a .mscz archive. Handles MuseScore's JSON output,
    decodes embedded base64 data, and writes the resulting files to disk.
    Includes workarounds for known MuseScore 4.x CLI issues.

.PARAMETER File
    Path to a .mscz file.
    Accepts input from the pipeline (strings or objects with a Path/FullName property).

.PARAMETER Extract
    Specifies which resources to extract.
    Valid options: Score, ScoreAndParts, ScoreAudio, Parts.
    Defaults to: Score, Parts.

.PARAMETER MuseScorePath
    Path to the MuseScore executable.
    Defaults to the standard MuseScore 4 installation directory.

.EXAMPLE
    ConvertFrom-MuseScore -File "myscore.mscz"

.EXAMPLE
    Get-ChildItem *.mscz | ConvertFrom-MuseScore

.EXAMPLE
    'a.mscz','b.mscz' | ConvertFrom-MuseScore -Extract ScoreAndParts

.NOTES
    Requires MuseScore 4.x or later.
#>
function ConvertFrom-MuseScore {
    [CmdletBinding()]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,

        [ValidateSet('Score', 'ScoreAndParts', 'ScoreAudio', 'Parts', IgnoreCase)]
        [string[]]$Extract = @('Score', 'Parts'),

        [string]$MuseScorePath = (Join-Path "$env:ProgramFiles" 'MuseScore 4\bin\MuseScore4.exe')
    )

    process {
        $path = Resolve-Path -LiteralPath $File -ErrorAction Stop

        Write-Host ('Processing "{0}"...' -f $path)

        Write-Host '* Extracting JSON'
        $musescoreJsonFile = 'musescore-score-parts.json'
        $process = Start-Process -Wait -NoNewWindow -PassThru `
            -WorkingDirectory (Get-Location).Path `
            -FilePath """$MuseScorePath""" `
            -ArgumentList '--score-parts-pdf', """$path""", '--export-to', """$musescoreJsonFile"""
        if ($process.ExitCode -ne 0) {
            Write-Warning "ExitCode=$($process.ExitCode)"
        }

        $musescoreJson = Get-Content $musescoreJsonFile | ConvertFrom-Json
        $name = Split-Path -LeafBase $musescoreJson.score

        if ('Score' -in $Extract) {
            $filename = $name + ' [Score].pdf'
            Write-Host "* Extracting score ""$filename"""
            Set-Content -LiteralPath $filename -AsByteStream -Value ([Convert]::FromBase64String($musescoreJson.scoreBin))
        }

        if ('Parts' -in $Extract) {
            for ($i = 0; $i -lt $musescoreJson.parts.Count; $i++) {
                $partname = $musescoreJson.parts[$i]
                # Create filename using "score_name [part].pdf", ensuring valid filename.
                $filename = ('{0} [{1}].pdf' -f (Split-Path -LeafBase $name), $partname) -replace '[<>:"/\\|?*]', '_'
                Write-Host "* Extracting part ""$filename"""
                Set-Content -LiteralPath $filename -AsByteStream -Value ([Convert]::FromBase64String($musescoreJson.partsBin[$i]))
            }
        }

        Remove-Item -LiteralPath $musescoreJsonFile

        if ('ScoreAudio' -in $Extract) {
            $filename = $name + '.mp3'
            Write-Host "* Extracting audio ""$filename""..."
            $process = Start-Process -Wait -NoNewWindow -PassThru `
                -WorkingDirectory (Get-Location).Path `
                -FilePath """$MuseScorePath""" `
                -ArgumentList """$path""", '--export-to', """$filename"""
            if ($process.ExitCode -ne 0) {
                Write-Warning "ExitCode=$($process.ExitCode)"
            }
        }
    }
}
