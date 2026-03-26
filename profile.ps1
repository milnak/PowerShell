# Profile for Windows PowerShell (PowerShell 5)
Write-Host ("Profile loaded from {0}" -f $PSCommandPath)

if ($env:VSCODE_INJECTION) {
    Write-Host -ForegroundColor Yellow 'Running inside VSCode Terminal'
}
