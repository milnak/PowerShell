<#
.SYNOPSIS
Launch vscode
.DESCRIPTION
Unlike code.cmd, this supports wildcards.
.EXAMPLE
 Get-ChildItem *.txt | Invoke-Code -Confirm
 #>
function Invoke-Code {
    # Support -Confirm, -WhatIf
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Files to edit. Wildcards supported.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path,
        # Whether to create a new VSCode instance.
        [switch]$NewWindow,
        # Command to launch code. Typically 'code.cmd'
        [string]$CodeCommand = 'code.cmd'
    )

    begin {
        Write-Verbose '[Invoke-Code] begin'

        # Fail fast if $CodeCommand can't be located.
        Get-Command -Name $CodeCommand -CommandType Application -ErrorAction Stop | Out-Null

        $codeArgs = @()
    }

    process {
        Write-Verbose '[Invoke-Code] process'

        foreach ($item in $Path) {
            # if ($item -notmatch '[\*\?]' -and -not (Test-Path $item -PathType Leaf)) {
            $resolvedPath = Resolve-Path -Path $item -ErrorAction SilentlyContinue
            if (-not $resolvedPath -or (Test-Path -LiteralPath $resolvedPath -PathType Container -ErrorAction SilentlyContinue)) {
                # Add directory names or files that don't exist as-is
                if ($PSCmdlet.ShouldProcess($item, 'Edit with code')) {
                    Write-Verbose "Adding non-existent file: $item"
                    $codeArgs += $item
                }
            }
            else {
                # Support wildcards
                Get-ChildItem -Path $item | Select-Object -ExpandProperty FullName | ForEach-Object {
                    if ($PSCmdlet.ShouldProcess($_, 'Edit with code')) {
                        Write-Verbose "Adding file: $_"
                        $codeArgs += $_
                    }
                }
            }
        }
    }

    end {
        Write-Verbose '[Invoke-Code] end'

        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('WhatIf')) {
            # -WhatIf requires no additional processing.
            return
        }

        if ($codeArgs.Count -eq 0) {
            Write-Warning 'No matching files found.'
            return
        }

        if ($NewWindow) {
            $codeArgs += '--new-window'
        }
        Write-Verbose "Launching $CodeCommand $codeArgs"
        & $CodeCommand @codeArgs
    }
}
