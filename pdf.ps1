<#
.SYNOPSIS
    Split a PDF into individual page files.
.DESCRIPTION
    Uses qpdf to split a PDF file into separate per-page PDF files named
    with a numeric suffix (e.g. document-1.pdf, document-2.pdf, ...).
.PARAMETER File
    Path to the PDF file to split.
.EXAMPLE
    Invoke-PdfSplitPages -File 'document.pdf'
.EXAMPLE
    Get-ChildItem *.pdf | Invoke-PdfSplitPages
#>
function Invoke-PdfSplitPages {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$File
    )

    begin {
        Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null
    }
    process {
        $outputFilename = [IO.Path]::GetFileNameWithoutExtension($File)
        $outputFilename += '-%d.pdf'

        Write-Host ''
        Write-Host "`"$File`" --> `"$outputFilename`""
        Write-Host ''

        if ($PSCmdlet.ShouldProcess($File, 'Split PDF pages')) {
            & qpdf.exe --split-pages "1-z" $File $outputFilename
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "qpdf failed with exit code $LASTEXITCODE"
            }
        }
    }
}

<#
.SYNOPSIS
    Remove encryption from a PDF file.
.DESCRIPTION
    Uses qpdf to decrypt a PDF, writing the result with a -decrypted suffix.
.PARAMETER File
    Path to the encrypted PDF file.
.EXAMPLE
    Invoke-PdfDecrypt -File 'secure.pdf'
.EXAMPLE
    Get-ChildItem *.pdf | Invoke-PdfDecrypt
#>
function Invoke-PdfDecrypt {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$File
    )

    begin {
        Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null
    }
    process {
        $outputFilename = [IO.Path]::GetFileNameWithoutExtension($File)
        $outputFilename += '-decrypted.pdf'

        Write-Host ''
        Write-Host "`"$File`" --> `"$outputFilename`""
        Write-Host ''

        if ($PSCmdlet.ShouldProcess($File, 'Decrypt PDF')) {
            & qpdf.exe --decrypt "$File" "$outputFilename"
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "qpdf failed with exit code $LASTEXITCODE"
            }
        }
    }
}

<#
.SYNOPSIS
    Merge multiple PDF files into a single PDF.
.DESCRIPTION
    Finds all PDF files matching a given filename prefix, sorts them by name,
    and uses qpdf to merge them into one output file with a -merged suffix.
.PARAMETER File
    Filename prefix used to match PDFs (e.g. 'chapter' matches 'chapter*.pdf').
.EXAMPLE
    Invoke-PdfMerge -File 'chapter'
#>
function Invoke-PdfMerge {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$File
    )

    begin {
        Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null
    }
    process {
        $pdfList = Get-ChildItem -Filter "${File}*.pdf" | Sort-Object Name | Select-Object -ExpandProperty Name
        if ($pdfList.Count -eq 0) {
            Write-Warning "No files matching ${File}*.pdf found."
            return
        }

        $outputFilename = $File
        $outputFilename += '-merged.pdf'

        Write-Host ''
        Write-Host "`"$File*.pdf`" --> `"$outputFilename`""
        Write-Host ''

        if ($PSCmdlet.ShouldProcess($outputFilename, 'Merge PDFs')) {
            $qpdfArgs = @('--empty', '--pages') + ($pdfList | ForEach-Object { $_, '1-z' }) + @('--', $outputFilename)
            & qpdf.exe @qpdfArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "qpdf failed with exit code $LASTEXITCODE"
            }
        }
    }
}


<#
.SYNOPSIS
    List bookmarks (outlines) from a PDF file.
.DESCRIPTION
    Uses qpdf's JSON output to extract the page numbers and titles of all
    bookmark entries (document outlines) in a PDF.
.PARAMETER File
    Path to the PDF file to inspect.
.EXAMPLE
    Get-PdfBookmarks -File 'document.pdf'
.EXAMPLE
    Get-ChildItem *.pdf | Get-PdfBookmarks
#>
function Get-PdfBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$File
    )

    begin {
        Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null
    }
    process {
        $json = qpdf.exe --json $File | ConvertFrom-Json
        $json.pages | Where-Object { $_.outlines.title } `
        | Select-Object -Property @{Name = 'Page'; Expression = { $_.pageposfrom1 } }, @{Name = 'Title'; Expression = { $_.outlines.title } }
    }
}
