
<#
.SYNOPSIS
Check for and install Scoop package updates.

.DESCRIPTION
If Scoop is installed, this function updates all packages and performs a
cleanup. It keeps a timestamp file to avoid running more than once every
7 days unless -Force is specified.

.PARAMETER Force
Skips the 7‑day frequency check and runs immediately.

.EXAMPLE
Invoke-ScoopUpdate

.EXAMPLE
Invoke-ScoopUpdate -Force
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Status and any output from Scoop.
.NOTES
Requires scoop.ps1. Normal runs write ~/.scoop-lastcheck before updating;
-Force bypasses both the frequency check and timestamp write. Cleanup
removes old package versions. Does not support -WhatIf.
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


<#
.SYNOPSIS
Returns detailed information about installed Scoop packages.
.DESCRIPTION
Lists installed packages while suppressing host output, then runs scoop info
for each bucket/package in parallel to include descriptions and websites.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.Object. Scoop info records for installed packages.
.EXAMPLE
Invoke-ScoopListInfo | Select-Object Name,Version,Description,Website | Export-Csv '.\scoop-listinfo.csv'
.LINK
Invoke-ScoopListInfoMarkdown
.NOTES
Requires scoop.ps1 and PowerShell 7 parallel pipelines. Temporarily installs
a global no-op Write-Host function, then removes it rather than restoring
any pre-existing function override.
#>
function Invoke-ScoopListInfo {
    # Suppress "scoop list" Write-Host output by overriding Write-Host

    <#
    .SYNOPSIS
    Suppresses host messages while Scoop lists installed packages.
    .DESCRIPTION
    Temporarily shadows Write-Host with a no-op function. All supplied
    arguments are ignored until Invoke-ScoopListInfo removes the override.
    .INPUTS
    None.
    .OUTPUTS
    None.
    .EXAMPLE
    Write-Host 'This message is suppressed.'
    .NOTES
    Global override used only during the enclosing Scoop list operation.
    #>
    function global:Write-Host {
    }
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

<#
.SYNOPSIS
Returns installed Scoop package information as a Markdown report.
.DESCRIPTION
Calls Invoke-ScoopListInfo, sorts packages by bucket and name, and emits
dated Markdown headings and linked entries with versions and descriptions.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Markdown report lines.
.EXAMPLE
Invoke-ScoopListInfoMarkdown | Out-File '.\scoop-listinfo.md'
.NOTES
Requires the Scoop dependencies of Invoke-ScoopListInfo.
#>
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
