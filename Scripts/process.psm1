<#
.SYNOPSIS
    Terminate a process gracefully or forcefully.
.DESCRIPTION
    Attempts to close the main window of the named process. If -Force is
    specified and the process remains, Stop-Process is invoked to kill it.
.PARAMETER Name
    Name of the process to terminate.
.PARAMETER Force
    Forcefully stop the process if it does not exit gracefully.
#>
function Invoke-Kill {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [switch]$Force
    )

    $process = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if ($process.Count -eq 0) {
        'Process not found'
    }
    elseif ($process.Count -eq 1) {
        $description = $process.Description
        $processId = $process.Id
        $mainWindowTitle = $process.MainWindowTitle
        # try gracefully first
        $process.CloseMainWindow() | Out-Null
        if ($Force -and -not $process.HasExited) {
            Stop-Process -Force -Name $Name
        }
        if ($process.HasExited) {
            'process {0} ({1}) - ''{2}'' killed' -f $description, $processId, $mainWindowTitle
        }
    }
    else {
        'Multiple instances running: {0}' -f ($process.Id -join ' ')
    }
}


<#
.SYNOPSIS
Gets the total working set size for one or more running processes.

.PARAMETER ProcessName
One or more process names (without .exe). This parameter is required.

.EXAMPLE
Get-ProcessWorkingSet msedgewebview2

.EXAMPLE
Get-ProcessWorkingSet pwsh, code
#>
function Get-ProcessWorkingSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$ProcessName
    )

    process {
        function Convert-Bytes {
            param (
                [Parameter(Mandatory = $true)]
                [ValidateRange(0, [double]::MaxValue)]
                [double]$Bytes
            )

            if ($Bytes -ge 1TB) {
                "{0:N2} TB" -f ($Bytes / 1TB)
            }
            elseif ($Bytes -ge 1GB) {
                "{0:N2} GB" -f ($Bytes / 1GB)
            }
            elseif ($Bytes -ge 1MB) {
                "{0:N2} MB" -f ($Bytes / 1MB)
            }
            elseif ($Bytes -ge 1KB) {
                "{0:N2} KB" -f ($Bytes / 1KB)
            }
            else {
                "{0:N0} Bytes" -f $Bytes
            }
        }

        foreach ($name in $ProcessName) {
            $sum = (Get-Process -Name $name -ErrorAction SilentlyContinue | Measure-Object -Sum -Property WorkingSet).Sum
            if ($null -eq $sum) {
                Write-Warning "No running process found with name '$name'."
                continue
            }

            # $mb = $sum / 1MB
            # $formattedSize = '{0:N0} bytes ({1:N2} MB)' -f $sum, $mb
            '{0}: {1}' -f $name, (Convert-Bytes -Bytes $sum)
        }
    }
}

Export-ModuleMember -Function Invoke-Kill, Get-ProcessWorkingSet
