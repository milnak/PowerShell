if ($env:VSCODE_INJECTION) {
    Write-Host -ForegroundColor Yellow 'Running inside VSCode Terminal.'
    return
}

if ($host.Name -ne 'ConsoleHost') {
    Write-Host -ForegroundColor Yellow 'Not running in consolehost.'
    return
}

# Load external functions

Get-ChildItem "$PSScriptRoot\Scripts\*.psm1" | ForEach-Object {
    Write-Host "Loading functions from $($_.Name)"
    Import-Module -Name $_.FullName
}

Write-BoxedMessage -Message "Profile loaded from $PSScriptRoot`nPowerShell $((Get-Host).Version)"

Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# Add Winget package paths to PATH

$wingetPackagesPath = "$env:LocalAppData\Microsoft\Winget\Packages"
"Adding Winget paths from $wingetPackagesPath"
Get-ChildItem -LiteralPath $wingetPackagesPath -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue `
| Group-Object DirectoryName `
| ForEach-Object {
    $fullPath = $_.Name
    # e.g. "zyedidia.micro_Microsoft.Winget.Source_8wekyb3d8bbwe" -> "zyedidia.micro"
    $relativePath = [IO.Path]::GetRelativePath("$env:LocalAppData\Microsoft\Winget\Packages", $fullPath).Replace('_Microsoft.Winget.Source_8wekyb3d8bbwe', '')
    Write-Host ("• `e[4m{0}`e[24m" -f $relativePath)
    $exes = $_.Group | ForEach-Object { "`e[1m{0}`e[0m" -f (Split-Path -Leaf $_) }
    Write-Host "  $($exes -join ', ')"
    $env:Path += ";$fullPath"
}

# Set the prompt
. "$PSScriptRoot\prompt.ps1"

# zoxide, needs to come AFTER setting prompt!
if ((Get-Command -Name 'zoxide.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
    'Adding zoxide completion'
    Invoke-Expression -Command $(zoxide.exe init powershell | Out-String)
}

$env:RIPGREP_CONFIG_PATH = (Resolve-Path "~\.ripgreprc" -ErrorAction SilentlyContinue).Path

# Terminal-Icons
# Set Terminal font to "MesloLGM Nerd Font".
$moduleName = 'Terminal-Icons'
if (-not (Get-Module -ListAvailable  -Name $moduleName)) {
    Write-Host -ForegroundColor Green "Installing $moduleName module..."
    Install-Module -Name $moduleName -Repository PSGallery -Force
}
Import-Module $moduleName

if ((Get-Command -Name 'oh-my-posh.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
	'Adding oh-my-posh'

    oh-my-posh init pwsh --config 'takuya' | Invoke-Expression
}

# FD doesn't support configuration files, so create a wrapper.
function fd { fd.exe --no-ignore $args }

# topgrade doesn't support setting run-type in config.
function topgrade { topgrade.exe --run-type damp }
