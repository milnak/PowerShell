<#
.SYNOPSIS
Check for and install winget package updates.
#>
function Invoke-WingetUpgrade {
    Get-Command -Name 'sudo.exe' -CommandType Application -ErrorAction Stop | Out-Null
    Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction Stop | Out-Null

    $params = `
        '--all', `
        '--accept-package-agreements', `
        '--accept-source-agreements', `
        '--include-unknown', `
        '--interactive'

    sudo.exe --inline winget.exe upgrade @params
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


# .DESCRIPTION
# Similar to "scoop list", except that it also includes Description and Website.
#
# .EXAMPLE
# .\scoop-listinfo.ps1 | ConvertTo-Csv | Out-File -FilePath ./scoop-listinfo.csv -Encoding UTF8
# .NOTES
# This function is designed to be used with PowerShell 7 or later.
function Invoke-ScoopListInfo {
    # "scoop info" is slow, so do it in parallel.
    scoop.ps1 list | ForEach-Object -Parallel {
        $app = '{0}/{1}' -f $_.Source, $_.Name
        $updated = $_.Updated

        $info = scoop.ps1 info $app
        [PSCustomObject]@{
            'App'         = $app
            'Version'     = $info.Version
            'Description' = $info.Description
            'Website'     = $info.Website
            'Updated'     = $updated
        }
    }
}
