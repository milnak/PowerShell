<#
.SYNOPSIS
    Rewrites a PDF through Ghostscript with transfer functions applied.
.DESCRIPTION
    Runs Ghostscript's pdfwrite device with TransferFunctionInfo=/Apply and
    writes <base-name>-inverted.pdf in the current directory.
.PARAMETER Path
    PDF path. Accepts pipeline strings or objects with a Path or FullName property.
.INPUTS
    System.String, or objects with Path or FullName properties.
.OUTPUTS
    System.String. Any standard output emitted by Ghostscript.
.EXAMPLE
    Invoke-InvertPdfColors -Path '.\document.pdf' -WhatIf
.NOTES
    Requires gs.exe on PATH. Supports -WhatIf/-Confirm. The command applies
    existing transfer functions; it does not define an inversion function.
#>
function Invoke-InvertPdfColors {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )

    begin {
        Write-Verbose "[Invoke-InvertPdfColors] BEGIN"

        Get-Command -Name 'gs.exe' -ErrorAction Stop | Out-Null
    }

    process {
        Write-Verbose "[Invoke-InvertPdfColors] PROCESS $Path"

        $outName = [IO.Path]::GetFileNameWithoutExtension($Path) + '-inverted.pdf'

        if ($PSCmdlet.ShouldProcess($Path, 'Invert PDF colors')) {
            $gsPath = Get-Command -Name 'gs.exe' -ErrorAction Stop | Select-Object -ExpandProperty Source
            & $gsPath -sDEVICE=pdfwrite -o $outName -dTransferFunctionInfo=/Apply -f $Path
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Ghostscript failed with exit code $LASTEXITCODE"
            }
        }
    }

    end {
        Write-Verbose "[Invoke-InvertPdfColors] END"
    }
}


<#
.SYNOPSIS
    Split a PDF into individual page files.
.DESCRIPTION
    Uses qpdf to split a PDF file into separate per-page PDF files named
    with a numeric suffix (e.g. document-1.pdf, document-2.pdf, ...).
.PARAMETER InFile
    PDF path. Accepts pipeline strings or objects with InFile or FullName properties.
.EXAMPLE
    Invoke-PdfSplitPages -InFile 'document.pdf'
.EXAMPLE
    Get-ChildItem *.pdf | Invoke-PdfSplitPages
.INPUTS
    System.String, or objects with InFile or FullName properties.
.OUTPUTS
    System.String. Any standard output emitted by qpdf.
.NOTES
    Requires qpdf.exe on PATH. Supports -WhatIf/-Confirm. Per-page output
    uses the input's leaf filename as a template in the current directory.
#>
function Invoke-PdfSplitPages {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$InFile
    )

    begin {
        Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null
    }

    process {
        $OutFile = Split-Path -Leaf -Path $InFile

        if ($PSCmdlet.ShouldProcess($InFile, 'Split PDF pages')) {
            & qpdf.exe $InFile --split-pages $OutFile
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
    PDF path. Accepts pipeline strings or objects with File or FullName properties.
.EXAMPLE
    Invoke-PdfDecrypt -File 'secure.pdf'
.EXAMPLE
    Get-ChildItem *.pdf | Invoke-PdfDecrypt
.INPUTS
    System.String, or objects with File or FullName properties.
.OUTPUTS
    System.String. Any standard output emitted by qpdf.
.NOTES
    Requires qpdf.exe on PATH. Supports -WhatIf/-Confirm. Writes
    <base-name>-decrypted.pdf in the current directory. No password parameter
    is supplied, so PDFs requiring a password may fail.
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
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Any standard output emitted by qpdf.
.NOTES
    Requires qpdf.exe on PATH. Supports -WhatIf/-Confirm. Searches the
    current directory and merges in filename sort order, not numeric order.
    A pre-existing <prefix>-merged.pdf also matches the input search.
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
    Reads qpdf's JSON page data and returns pages whose outline entries have
    titles. Multiple titles associated with a page remain grouped in Title.
.PARAMETER File
    PDF path. Accepts pipeline strings or objects with File or FullName properties.
.EXAMPLE
    Get-PdfBookmarks -File 'document.pdf'
.EXAMPLE
    Get-ChildItem *.pdf | Get-PdfBookmarks
.INPUTS
    System.String, or objects with File or FullName properties.
.OUTPUTS
    System.Management.Automation.PSCustomObject. One-based Page and Title properties.
.NOTES
    Requires qpdf.exe on PATH. Does not modify the PDF.
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

Export-ModuleMember -Function `
    Get-PdfBookmarks, `
    Invoke-InvertPdfColors, `
    Invoke-PdfDecrypt, `
    Invoke-PdfMerge, `
    Invoke-PdfSplitPages
