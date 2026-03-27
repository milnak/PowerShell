<#
.SYNOPSIS
    Truncate a filesystem path to fit within a maximum character length.
#>
function TruncatePath {
    [CmdletBinding()]
    param([string]$Path, [int]$MaxChars = 80)
    $truncated = $Path

    if ($Path.Length -gt $MaxChars) {
        if (Split-Path $Path -IsAbsolute) {
            # truncated is the minimal string that will be shown, e.g. 'C:\...'
            $minPath = (Split-Path $Path -Qualifier) + '\...'

            # Fit as many subpaths as possible
            $fit = $null

            while ($true) {
                $leaf = Split-Path $Path -Leaf
                if ($minPath.Length + 1 + $fit.Length + $leaf.Length -gt $MaxChars) {
                    break
                }

                $fit = '\' + $leaf + $fit
                $Path = Split-Path $Path -Parent
            }

            $truncated = $minPath + $fit
        }
        else {
            # Non-absolute path, just truncate as needed.
            $truncated = '...' + $Path.Substring(($Path.Length + 3) - $MaxChars)
        }
    }

    $truncated
}

<#
.SYNOPSIS
Prompt

.DESCRIPTION
Indicates if running as admin, and git branch.
#>
function global:Prompt {
    $cwd = (Get-Location).Path
    if ($cwd.StartsWith($HOME)) { $cwd = $cwd.Replace($HOME, '~') }
    $cwd = TruncatePath -Path $cwd -MaxChars 60

    $isAdmin = [bool](([Security.Principal.WindowsIdentity]::GetCurrent()).groups -match 'S-1-5-32-544')
    Write-Host @(' PS ', ' ADMIN ')[$isAdmin] -NoNewline -BackgroundColor @('DarkMagenta', 'DarkRed')[$isAdmin] -ForegroundColor White

    Write-Host " $cwd " -NoNewline -BackgroundColor DarkYellow -ForegroundColor Black

    try {
        $gitBranch = (git.exe symbolic-ref HEAD 2>&1)
        if ($gitBranch.ToString() -notmatch 'fatal:') {
            $gitBranch = Split-Path -Leaf $gitBranch
            $isDirty = (git.exe status --porcelain).Count -ne 0
            Write-Host " $gitBranch " -NoNewline -Background @('DarkBlue', 'DarkCyan')[$isDirty] -ForegroundColor White
        }
    }
    catch {}

    Write-Host ''

    '> '
}
