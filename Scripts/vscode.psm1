<#
.SYNOPSIS
Start editor.

.EXAMPLE
Invoke-Editor -Verbose $PROFILE -EditorCommand micro.exe
Edit PowerShell $PROFILE file using micro.exe.

.EXAMPLE
Invoke-Editor -Path m* -EditorArgs '--new-window'
Editor with wildcard path using the default editor in a new window.
#>
function Invoke-Editor {
    [CmdletBinding(SupportsShouldProcess)] # Support -Confirm, -WhatIf
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        # Editor command to use, e.g. 'code.cmd' or 'micro.exe'.
        [string]$EditorCommand = 'code.cmd',

        # Arguments to pass to the editor command, e.g. '--new-window'.
        [string[]]$EditorArgs
    )

    begin {
        # Fail fast if editor command doesn't exist.
        Get-Command -Name $EditorCommand -CommandType Application -ErrorAction Stop | Out-Null

        $files = [Collections.Generic.List[string]]::new()
    }

    process {
        function Add-SurroundingQuotes {
            param ([Parameter(Mandatory = $true)][string]$InputString)

            if (($InputString.StartsWith('"') -and $InputString.EndsWith('"'))) {
                return $InputString
            }
            else {
                return '"' + $InputString + '"'
            }
        }

        foreach ($item in $Path) {
            if ([Management.Automation.WildcardPattern]::ContainsWildcardCharacters($item)) {
                # Wildcard detected. Add resolved wildcard matches.
                Write-Verbose "Wildcard detected: $item"
                $resolvedPaths = Resolve-Path -Path $item -ErrorAction Stop
                foreach ($resolvedPath in $resolvedPaths) {
                    if ($PSCmdlet.ShouldProcess("$resolvedPath", "Edit with $EditorCommand")) {
                        $files.Add((Add-SurroundingQuotes $resolvedPath))
                    }
                }
            }
            else {
                # No wildcard detected. Resolve literal path if file found, otherwise pass path as-is.
                $resolvedPath = Resolve-Path -LiteralPath $item -ErrorAction SilentlyContinue
                if ($resolvedPath) {
                    if ($PSCmdlet.ShouldProcess("$resolvedPath", "Edit with $EditorCommand")) {
                        $files.Add((Add-SurroundingQuotes $resolvedPath))
                    }

                }
                else {
                    if ($PSCmdlet.ShouldProcess("$item", "Edit with $EditorCommand")) {
                        $files.Add((Add-SurroundingQuotes $item))
                    }
                }
            }
        }
    }

    end {
        if ($files.Count -eq 0) {
            Write-Warning "No files to edit."
            return
        }
        if ($files.Count -ne 0 -and -not $WhatIfPreference) {
            Write-Host "`nLaunching " -NoNewline -ForegroundColor DarkGray
            Write-Host $EditorCommand -ForegroundColor Cyan
            $files | ForEach-Object {
                Write-Host ' > ' -NoNewline -ForegroundColor DarkCyan
                Write-Host $_
            }
            Write-Host ''
            $parameters = @{
                FilePath     = $EditorCommand
                ArgumentList = ($EditorArgs + $files)
            }

            # Launch the editor with the specified arguments and files.
            # Not using "&" as that sometimes ends up causing Terminal not to close.
            if ($EditorCommand -like '*.cmd') {
                # For .cmd (e.g. code.cmd) don't show the command window.
                Start-Process -NoNewWindow @parameters
            }
            else {
                Start-Process @parameters
            }
        }
    }
}

function code {
    Invoke-Editor -EditorCommand 'code.cmd' -EditorArgs @() -Path $args
}

function micro {
    Invoke-Editor -EditorCommand 'micro.exe' -EditorArgs @() -Path $args
}

Export-ModuleMember -Function `
    code, `
    micro, `
    Invoke-Editor
