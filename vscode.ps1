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
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File,
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

        $resolvedPath = Resolve-Path -Path $File -ErrorAction SilentlyContinue
        if (-not $resolvedPath -and $File -notmatch '[\*\?]' -and -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            # Add directory names or files that don't exist as-is
            if ($PSCmdlet.ShouldProcess($File, 'Edit with code')) {
                Write-Verbose "Adding non-existent file: $File"
                $codeArgs += $File
            }
        }
        else {
            # Support wildcards
            Write-Verbose "Resolving path: $File"
            Get-ChildItem -Path $File | Select-Object -ExpandProperty FullName | ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_, 'Edit with code')) {
                    Write-Verbose "Adding file: $_"
                    $codeArgs += $_
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
