<#
.SYNOPSIS
Launch vscode
.DESCRIPTION
Unlike code.cmd, this supports wildcards.
.EXAMPLE
 Get-ChildItem *.txt | Invoke-Code -Confirm
 #>
function Invoke-Code {
    # TODO: Support multiple files on commandline, e.g. "Invoke-Code file1.txt file2.txt"

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


        # Cases:
        # 1. Wildcard provided: resolve and add all matches.
        # 2. No wildcard, but file doesn't exist: add as-is (let code handle the error).
        # 3. No wildcard, file exists: resolve and add. This allows for relative paths, e.g. "subdir\file.txt", to be added correctly.

        if ($File -match '[\*\?]')
        {
            Write-Verbose "Resolving wildcard: $File"
            Get-ChildItem -Path $File | Select-Object -ExpandProperty FullName | ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_, 'Edit with code')) {
                    Write-Verbose "Adding file: $_"
                    $codeArgs += $_
                }
            }
        }
        else {
            $resolvedPath = Resolve-Path -LiteralPath $File -ErrorAction SilentlyContinue
            if (-not $resolvedPath) {
                Write-Warning "Adding non-existent file: $File"
                $codeArgs += $File
            }
            else {
                $codeArgs += $resolvedPath
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
