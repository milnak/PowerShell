
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
# Convert output to CSV
#
# Invoke-ScoopListInfo `
# | Select-Object @{Name='App'; Expression={"$($_.Source)/$($_.Name)"}},Version,Description,Website,@{Name='Updated'; Expression={[DateTime]$_.'Updated at'}} `
# | ConvertTo-Csv `
# | Out-File -FilePath ./scoop-listinfo.csv -Encoding UTF8
#
# .SEE ALSO
# Invoke-ScoopListInfoMarkdown
#
# .NOTES
# This function is designed to be used with PowerShell 7 or later.
function Invoke-ScoopListInfo {
    # Suppress "scoop list" Write-Host output by overriding Write-Host
    function global:Write-Host { }
    try {
        $list = scoop.ps1 list
    }
    finally {
        Remove-Item function:Write-Host
    }

    # "scoop info" is slow, so do it in parallel.
    $list | ForEach-Object -Parallel {
        scoop.ps1 info "$($_.Source)/$($_.Name)"
    }
}

# .DESCRIPTION
# Outputs Scoop package information as Markdown grouped by bucket.
#
# .EXAMPLE
# Invoke-ScoopListInfoMarkdown | Out-File ./scoop-listinfo.md
function Invoke-ScoopListInfoMarkdown {
    '# Scoop List'
    ''
    "*Created on $(Get-Date -Format 'yyyy-MM-dd') using Invoke-ScoopListInfoMarkdown*"
    ''
    Invoke-ScoopListInfo `
    | Select-Object Source, Name, Version, Description, Website, @{Name = 'Updated'; Expression = { [DateTime]$_.'Updated at' } }
    | Sort-Object Source, Name
    | Group-Object Source
    | ForEach-Object {
        "## Bucket: $($_.Name)"
        ''
        $_.Group
        | ForEach-Object {
            "* [$($_.Name)]($($_.Website)) ($($_.Version), $($_.Updated.ToString('yyyy-MM-dd'))) - $($_.Description.Trim())"
        }
        ''
    }
}

Export-ModuleMember -Function `
    Invoke-ScoopListInfo, `
    Invoke-ScoopListInfoMarkdown, `
    Invoke-ScoopUpdate
