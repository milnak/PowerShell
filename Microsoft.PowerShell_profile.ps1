if ($env:VSCODE_INJECTION) {
    Write-Host -ForegroundColor Yellow 'Running inside VSCode Terminal.'
    return
}

if ($host.Name -ne 'ConsoleHost') {
    Write-Host -ForegroundColor Yellow 'Not running in consolehost.'
    return
}


# Load external functions

'_unsorted', `
    'audio', `
    'download', `
    'filesystem', `
    'git', `
    'mame', `
    'messages', `
    'musescore', `
    'pdf', `
    'process', `
    'prompt', `
    'sibelius', `
    'transcribe', `
    'update', `
    'vscode', `
    'windows' `
| ForEach-Object {
    Write-Host "Loading functions from `e[1m$($_).ps1`e[22m"
    . "$PSScriptRoot\$_.ps1"
}

# See also $env:USERPROFILE\OneDrive\Documents\PowerShell\profile.ps1
Write-BoxedMessage -Message "Profile loaded from $PSScriptRoot`nPowerShell $((Get-Host).Version)"

Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# Add Winget package paths to PATH
$wingetPackagesPath = "$env:LocalAppData\Microsoft\Winget\Packages"
"Adding Winget paths from $wingetPackagesPath"
Get-ChildItem -LiteralPath $wingetPackagesPath -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue `
| Group-Object DirectoryName `
| ForEach-Object {
    $exes = $_.Group | ForEach-Object { "`e[1m{0}`e[22m" -f (Split-Path -Leaf $_) }
    '  {0}: {1}' -f [IO.Path]::GetRelativePath("$env:LocalAppData\Microsoft\Winget\Packages", $_.Name), ($exes -join ', ')
    $env:Path += ";$($_.Name)"
}

# zoxide, needs to come AFTER setting prompt!
if ((Get-Command -Name 'zoxide.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
    'Adding zoxide completion'
    Invoke-Expression -Command $(zoxide.exe init powershell | Out-String)
}
