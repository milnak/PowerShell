function Invoke-PdfSplitPages {
    param([Parameter(Mandatory)][string]$File)

    Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null

    $outputFilename = [IO.Path]::GetFileNameWithoutExtension($File)
    $outputFileName += '-%d.pdf'

    Write-Host ''
    Write-Host "`"$File`" --> `"$outputFilename`""
    Write-Host ''

    $qpdfCmd = "qpdf.exe --split-pages=1-z `"$File`" `"$outputFilename`""

    Invoke-Expression $qpdfCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "qpdf failed with exit code $LASTEXITCODE"
    }
}

function Invoke-PdfDecrypt {
    param([Parameter(Mandatory)][string]$File)

    Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null

    $outputFilename = [IO.Path]::GetFileNameWithoutExtension($File)
    $outputFilename += '-decrypted.pdf'

    Write-Host ''
    Write-Host "`"$PdfFile`" --> `"$outputFilename`""
    Write-Host ''

    & qpdf.exe --decrypt "$File" "$outputFilename"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "qpdf failed with exit code $LASTEXITCODE"
    }
}

function Invoke-PdfMerge {
    param([Parameter(Mandatory)][string]$File)

    Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null

    $pdfList = Get-ChildItem -Filter "${File}*.pdf" | Sort-Object Name | Select-Object -ExpandProperty Name
    if ($pdfList.Count -eq 0) {
        Write-Host "No files matching ${File}*.pdf found."
        exit
    }

    $pdfListString = $pdfList -join ' '

    $outputFilename = $File
    $outputFilename += '-merged.pdf'

    Write-Host ''
    Write-Host "`"$File*.pdf`" --> `"$outputFilename`""
    Write-Host ''

    $qpdfCmd = "qpdf.exe --empty --pages $pdfListString 1-z -- `"$outputFilename`""

    Invoke-Expression $qpdfCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "qpdf failed with exit code $LASTEXITCODE"
    }

}


function Get-PdfBookmarks {
    param([Parameter(Mandatory)][string]$File)

    Get-Command -Name 'qpdf.exe' -ErrorAction Stop | Out-Null

    $json = qpdf.exe --json $File | ConvertFrom-Json
    $json.pages | Where-Object { $_.outlines.title } `
    | Select-Object -Property @{Name = 'Page'; Expression = { $_.pageposfrom1 } }, @{Name = 'Title'; Expression = { $_.outlines.title } }
}
