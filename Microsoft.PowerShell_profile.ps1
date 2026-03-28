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
    'prompt', `
    'sibelius', `
    'transcribe', `
    'update', `
    'vscode' `
| ForEach-Object {
    Write-Host "Loading functions from `e[1m$($_).ps1`e[22m"
    . "$PSScriptRoot\$_.ps1"
}

# See also $env:USERPROFILE\OneDrive\Documents\PowerShell\profile.ps1
Write-BoxedMessage -Message "Profile loaded from $PSScriptRoot`nPowerShell $((Get-Host).Version)"

Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

if ((Get-Command -Name 'fzf.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
    # PSFzf: https://github.com/kelleyma49/PSFzf
    'PSFzf' | ForEach-Object {
        if (-not (Get-Module -Name $_ -ListAvailable -ErrorAction SilentlyContinue)) {
            "Installing $_"
            Install-Module -Name $_ -Force
        }
    }

    'Enabling Ctrl+T, Ctrl+R completion'
    # Reverse Search Through PSReadline History (default chord: Ctrl+r)
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    # Set-Location Based on Selected Directory (default chord: Alt+c)
    $commandOverride = [ScriptBlock] { param($Location) Write-Host $Location }
    Set-PsFzfOption -AltCCommand $commandOverride
    # Tab Expansion
    # Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
}

Invoke-WingetUpdate

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

# Invoke-ScoopUpdate

# Enable completion in current shell.
# scoop install extras/scoop-completion
$modulePath = "$env:USERPROFILE\scoop\modules\scoop-completion"
if (Test-Path -LiteralPath $modulePath -PathType Container) {
    'Installing scoop-completion'
    Import-Module $modulePath
}

# zoxide, needs to come AFTER setting prompt!
if ((Get-Command -Name 'zoxide.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
    'Adding zoxide completion'
    Invoke-Expression -Command $(zoxide.exe init powershell | Out-String)
}


