
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
# Invoke-ScoopListInfo
# | Select-Object @{Name='App'; Expression={"$($_.Source)/$($_.Name)"}},Version,Description,Website,@{Name='Updated'; Expression={[DateTime]$_.'Updated at'}}
# | ConvertTo-Csv
# | Out-File -FilePath ./scoop-listinfo.csv -Encoding UTF8
#
# .NOTES
# This function is designed to be used with PowerShell 7 or later.
function Invoke-ScoopListInfo {
    # "scoop info" is slow, so do it in parallel.
    scoop.ps1 list | ForEach-Object -Parallel {
        scoop.ps1 info "$($_.Source)/$($_.Name)"
    }
}

function Invoke-ScoopListInfoMarkdown {
    "# Scoop List`n"
    Invoke-ScoopListInfo
    | Select-Object Source, Name, Version, Description, Website, @{Name = 'Updated'; Expression = { [DateTime]$_.'Updated at' } }
    | Sort-Object Source, Name
    | Group-Object Source
    | ForEach-Object {
        "## Bucket: $($_.Name)`n"
        $_.Group
        | ForEach-Object {
            "* [$($_.Name)]($($_.Website)) ($($_.Version), $($_.Updated)) - $($_.Description.Trim())"
        }
        ''
    }

}
