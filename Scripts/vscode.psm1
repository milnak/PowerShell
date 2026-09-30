<#
.SYNOPSIS
Start editor.
#>
function Invoke-Editor {
    [CmdletBinding(SupportsShouldProcess)] # Support -Confirm, -WhatIf
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        # Editor command to use, e.g. 'code' or 'micro'.
        [string]$EditorCommand = 'code.cmd'
    )

    begin {
        # Fail fast if editor command doesn't exist.
        Get-Command -Name $EditorCommand -CommandType Application -ErrorAction Stop | Out-Null

        $files = [Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Path) {
            if ([Management.Automation.WildcardPattern]::ContainsWildcardCharacters($item)) {
                Write-Verbose "Wildcard detected: $item"
                # Wildcard detected. Add resolved wildcard matches.
                $resolvedPaths = Resolve-Path -Path $item -ErrorAction Stop
                if ($resolvedPaths.Count -eq 0) {
                    Write-Warning "No matches found for wildcard: $item"
                }
                else {
                    foreach ($resolvedPath in $resolvedPaths) {
                        Write-Verbose "Resolved wildcard match: $resolvedPath"
                        if ($PSCmdlet.ShouldProcess($File, "Edit with $EditorCommand")) {
                            $files.Add($resolvedPath)
                        }
                    }
                }
            }
            else {
                # No wildcard detected. Resolve literal path if file found, otherwise pass path as-is.
                $resolvedPath = Resolve-Path -LiteralPath $item -ErrorAction SilentlyContinue
                if ($resolvedPath) {
                    Write-Verbose "Resolved literal path: $($resolvedPath)"
                    if ($PSCmdlet.ShouldProcess($File, "Edit with $EditorCommand")) {
                        $files.Add($resolvedPath)
                    }

                }
                else {
                    # $file = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
                    Write-Verbose "Using unresolved path: $item"
                    if ($PSCmdlet.ShouldProcess($File, "Edit with $EditorCommand")) {
                        $files.Add($item)
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
            & $EditorCommand @files
        }
    }
}


Export-ModuleMember -Function `
    Invoke-Editor
