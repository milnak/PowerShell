<#
.SYNOPSIS
    Terminate a process gracefully or forcefully.
.DESCRIPTION
    When exactly one process matches, requests closure of its main window.
    With -Force, immediately calls Stop-Process if it has not exited.
    Multiple matches are reported without terminating them.
.PARAMETER Name
    Name of the process to terminate.
.PARAMETER Force
    Forcefully stop the process if it does not exit gracefully.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Status when no process, multiple processes, or an exited
    process is detected.
.EXAMPLE
    Invoke-Kill -Name notepad
.NOTES
    Does not wait for graceful shutdown or support -WhatIf. -Force can
    discard unsaved work and stops by name after the initial single-match check.
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
.DESCRIPTION
Sums WorkingSet across all matching instances of each name and returns one
human-readable line per name. Warns when no matching process is running.

.PARAMETER ProcessName
One or more process names without .exe. Accepts pipeline strings or objects
with ProcessName or Name properties.
.INPUTS
System.String, or objects with ProcessName or Name properties.
.OUTPUTS
System.String. Process name and total working set with a binary size suffix.

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
        <#
        .SYNOPSIS
        Formats a nonnegative byte count with a binary size suffix.
        .DESCRIPTION
        Selects TB, GB, MB, KB, or Bytes. Scaled values use two decimal places;
        byte values use no decimal places, following the current culture.
        .PARAMETER Bytes
        Nonnegative byte count to format.
        .INPUTS
        None. This function does not accept pipeline input.
        .OUTPUTS
        System.String. Formatted size.
        .EXAMPLE
        Convert-Bytes -Bytes 1536
        .NOTES
        Local helper for Get-ProcessWorkingSet.
        #>
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

Export-ModuleMember -Function `
    Get-ProcessWorkingSet, `
    Invoke-Kill
