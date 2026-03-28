<#
.SYNOPSIS
Check and apply WinGet package updates.

.DESCRIPTION
Queries WinGet for available package updates and installs them. A timestamp
file is used to avoid checking more than once every 7 days unless the
`-Force` switch is provided. The function requires the Microsoft.WinGet.Client
module and will warn if it's not installed.

.PARAMETER Force
If specified, bypasses the 7‑day throttle and skips the user prompt.

.EXAMPLE
Invoke-WingetUpdate

.EXAMPLE
Invoke-WingetUpdate -Force
#>
function Invoke-WingetUpdate {
    [CmdletBinding()]
    Param([switch]$Force)

    if (-not (Get-Command -Name 'Get-WinGetPackageUpdate' -ErrorAction SilentlyContinue)) {
        # Install-Module -Name Microsoft.WinGet.Client -RequiredVersion 0.2.1
        Write-Warning 'WinGet module not installed. Skipping.'
        return
    }

    if (-not $Force) {
        if (((Get-Date) - [DateTime](Get-Content "~/.winget-lastcheck" -ErrorAction SilentlyContinue)).TotalDays -lt 7) {
            'Winget update check was run recently. Skipping.'
            return
        }

        Set-Content "~/.winget-lastcheck" -ErrorAction SilentlyContinue (Get-Date -Format 'O')
    }

    'Checking for winget updates'
    ''

    $updates = Get-WinGetPackageUpdate | Where-Object { $_.Source -eq 'winget' }
    if ($updates.Count -eq 0) {
        return
    }

    'The following Winget packages have updates available:'
    $updates | ForEach-Object {
        "• {0} ({1} -> {2})" -f $_.ID, $_.Version, $_.Available
    }
    ''

    if (-not $Force) {
        for ($i = 0; $i -lt 3; $i++) {
            Write-Host -NoNewline "WinGet updates are available. Waiting for $(3-$i) second$(@('','s')[$i -le 1]), press a key to skip ...`r"
            if ($Host.UI.RawUI.KeyAvailable -and $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyUp,IncludeKeyDown').KeyDown) {
                Write-Warning 'Updating cancelled.'
                return
            }
            Start-Sleep -Seconds 1
        }
        ''
    }

    'Found updates. Updating now.'
    ''

    # $wingetArgs = 'update', '--all', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--include-unknown'
    # & sudo.exe winget.exe @wingetArgs
    $updates | ForEach-Object {
        "• Updating {0} ..." -f $_.ID
        Update-WinGetPackage -ID $_.ID -Exact
    }
}

<#
.SYNOPSIS
Check for and install Scoop package updates.

.DESCRIPTION
If Scoop is installed, this function updates all packages and performs a
cleanup. It keeps a timestamp file to avoid running more than once every
7 days unless `-Force` is specified. Completion support is optionally
loaded if available.

.PARAMETER Force
Skips the 7‑day frequency check and runs immediately.

.EXAMPLE
Invoke-ScoopUpdate

.EXAMPLE
Invoke-ScoopUpdate -Force
#>
function Invoke-ScoopUpdate {
    [CmdletBinding()]
    Param([switch]$Force)

    if (-not (Get-Command -Name 'scoop.ps1' -CommandType ExternalScript -ErrorAction SilentlyContinue)) {
        return
    }

    if (-not $Force) {
        if (((Get-Date) - [DateTime](Get-Content "~/.scoop-lastcheck" -ErrorAction SilentlyContinue)).TotalDays -lt 7) {
            'scoop update check was run recently. Skipping.'
            return
        }

        Set-Content "~/.scoop-lastcheck" -ErrorAction SilentlyContinue (Get-Date -Format 'O')
    }

    'Checking for scoop updates'

    scoop update *
    scoop cleanup *
}

