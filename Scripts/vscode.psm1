<#
.SYNOPSIS
Starts an editor for literal paths or wildcard matches.
.DESCRIPTION
Collects paths across the pipeline, expands wildcard matches, and launches
the editor once. Existing literal paths are resolved; nonexistent literal
paths are passed through so the editor can create files.
.PARAMETER Path
One or more paths or wildcard patterns. Accepts pipeline strings or objects
with Path or FullName properties.
.PARAMETER EditorCommand
Application to launch. Defaults to code.cmd.
.PARAMETER EditorArgs
Arguments placed before the collected file paths.
.INPUTS
System.String, or objects with Path or FullName properties.
.OUTPUTS
None. Launches the editor without waiting for it to exit.

.EXAMPLE
Invoke-Editor -Verbose $PROFILE -EditorCommand micro.exe
Edit PowerShell $PROFILE file using micro.exe.

.EXAMPLE
Invoke-Editor -Path m* -EditorArgs '--new-window'
Editor with wildcard path using the default editor in a new window.
.NOTES
Requires the chosen editor application. Supports -WhatIf/-Confirm for each
resolved path. No files are opened when all paths are skipped or absent.
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
        <#
        .SYNOPSIS
        Adds surrounding double quotes to an editor path when needed.
        .DESCRIPTION
        Leaves text already enclosed in double quotes unchanged; otherwise
        wraps it for use in Start-Process's command-line argument string.
        .PARAMETER InputString
        Path or argument text to quote.
        .INPUTS
        None. This function does not accept pipeline input.
        .OUTPUTS
        System.String. The surrounded argument.
        .EXAMPLE
        Add-SurroundingQuotes -InputString 'C:\My Files\song.txt'
        .NOTES
        Local helper for Invoke-Editor. Does not escape embedded double quotes.
        #>
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

<#
.SYNOPSIS
Opens paths in Visual Studio Code through Invoke-Editor.
.DESCRIPTION
Forwards all positional arguments as Path values to Invoke-Editor, using
code.cmd without additional editor arguments.
.INPUTS
None. Supply paths as arguments, not pipeline input.
.OUTPUTS
None. Launches the editor.
.EXAMPLE
code '.\song.txt'
.NOTES
Requires code.cmd on PATH. This shadows the code launcher and treats all
arguments as paths, not as arbitrary VS Code command-line options.
#>
function code {
    Invoke-Editor -EditorCommand 'code.cmd' -EditorArgs @() -Path $args
}

<#
.SYNOPSIS
Opens paths in Micro through Invoke-Editor.
.DESCRIPTION
Forwards all positional arguments as Path values to Invoke-Editor, using
micro.exe without additional editor arguments.
.INPUTS
None. Supply paths as arguments, not pipeline input.
.OUTPUTS
None. Launches the editor.
.EXAMPLE
micro '.\song.txt'
.NOTES
Requires micro.exe on PATH. All arguments are treated as paths rather than
Micro command-line options.
#>
function micro {
    Invoke-Editor -EditorCommand 'micro.exe' -EditorArgs @() -Path $args
}

Export-ModuleMember -Function `
    code, `
    micro, `
    Invoke-Editor
