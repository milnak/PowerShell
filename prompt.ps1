<#
.SYNOPSIS
Builds the interactive Windows PowerShell prompt.
.DESCRIPTION
Returns an ANSI-colored prompt showing administrator status, an abbreviated
working directory, Git branch and dirty state when available, and a failure
indicator based on the status captured within the prompt.
.INPUTS
None. Called by the PowerShell host.
.OUTPUTS
System.String. Colored prompt text ending with a new input marker.
.EXAMPLE
. .\prompt.ps1
.NOTES
Defines global:Prompt. Requires Windows identity APIs and an ANSI terminal;
Git information is omitted when Git lookup fails.
#>
function global:Prompt {
    <#
    .SYNOPSIS
    Shortens a path to fit a prompt character budget.
    .DESCRIPTION
    Keeps short paths unchanged. For absolute paths, retains the drive
    qualifier and as many trailing components as fit after an ellipsis.
    Relative paths retain a trailing substring after an ellipsis.
    .PARAMETER Path
    Path text to shorten.
    .PARAMETER MaxChars
    Desired character limit. Defaults to 80; the prompt passes 60.
    .INPUTS
    None. This function does not accept pipeline input.
    .OUTPUTS
    System.String. Original or abbreviated path text.
    .EXAMPLE
    TruncatePath -Path 'C:\Projects\Example\Source' -MaxChars 20
    .NOTES
    Local display helper; does not resolve or modify filesystem paths.
    #>
    function TruncatePath {
        Param([string]$Path, [int]$MaxChars = 80)
        # truncated is the minimal string that will be shown, e.g. 'C:...'
        $truncated = $Path
        if ($Path.Length -gt $MaxChars) {
            if (Split-Path $Path -IsAbsolute) {
                $minPath = (Split-Path $Path -Qualifier) + '...'
                # Fit as many subpaths as possible
                $fit = $null
                while ($true) {
                    $leaf = Split-Path $Path -Leaf
                    if ($minPath.Length + 1 + $fit.Length + $leaf.Length -gt $MaxChars) {
                        break
                    }
                    $fit = '' + $leaf + $fit
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
    Wraps text in ANSI color and style sequences.
    .DESCRIPTION
    Adds requested styles and standard or bright foreground/background colors.
    Appends a reset sequence unless NoReset is specified.
    .PARAMETER Text
    Text to decorate.
    .PARAMETER ForegroundColor
    Standard color name, optionally prefixed with Bright, such as BrightWhite.
    .PARAMETER BackgroundColor
    Standard or Bright-prefixed background color name.
    .PARAMETER Bold
    Enable bold intensity.
    .PARAMETER Italic
    Enable italic styling.
    .PARAMETER Underline
    Enable underline styling.
    .PARAMETER Blink
    Enable blinking where supported.
    .PARAMETER Inverse
    Enable inverse foreground/background rendering.
    .PARAMETER Strikethrough
    Enable strikethrough styling.
    .PARAMETER NoReset
    Leave the selected styles active after the returned text.
    .INPUTS
    None. This function does not accept pipeline input.
    .OUTPUTS
    System.String. Text with ANSI escape sequences.
    .EXAMPLE
    Get-AnsiColorString -Text ' ADMIN ' -ForegroundColor BrightWhite -BackgroundColor Red
    .NOTES
    Local prompt helper. Unknown color names throw; visual support depends
    on the terminal.
    #>
    function Get-AnsiColorString {
        Param(
            # The text to colorize.
            [Parameter(Mandatory = $true)][string]$Text,
            # Foreground color and Background color to apply. (optional)
            [string]$ForegroundColor,
            [string]$BackgroundColor,
            # "`e[4m`e[3m`e[1munderline bold italic`e[0m"
            [switch]$Bold,
            [switch]$Italic,
            [switch]$Underline,
            [switch]$Blink,
            [switch]$Inverse,
            [switch]$Strikethrough,
            # Whether to add a reset sequence at the end.
            [switch]$NoReset
        )
        $colorMap = @{
            'Black'         = 30
            'Red'           = 31
            'Green'         = 32
            'Yellow'        = 33
            'Blue'          = 34
            'Magenta'       = 35
            'Cyan'          = 36
            'White'         = 37
            'BrightBlack'   = 90
            'BrightRed'     = 91
            'BrightGreen'   = 92
            'BrightYellow'  = 93
            'BrightBlue'    = 94
            'BrightMagenta' = 95
            'BrightCyan'    = 96
            'BrightWhite'   = 97
        }
        $result = ""
        if ($Bold) { $result += "`e[1m" }
        if ($Italic) { $result += "`e[3m" }
        if ($Underline) { $result += "`e[4m" }
        if ($Blink) { $result += "`e[5m" }
        if ($Inverse) { $result += "`e[7m" }
        if ($Strikethrough) { $result += "`e[9m" }
        if ($ForegroundColor) {
            $colorCode = $colorMap[$ForegroundColor]
            if (-not $colorCode) {
                throw "Invalid foreground color: $ForegroundColor"
            }
            else {
                $result += "`e[$($colorCode)m"
            }
        }
        if ($BackgroundColor) {
            $colorCode = $colorMap[$BackgroundColor]
            if (-not $colorCode) {
                throw "Invalid background color: $BackgroundColor"
            }
            $result += "`e[$($colorCode + 10)m"
        }
        $result += $Text
        if (-not $NoReset) {
            $result += "`e[0m"
        }
        return $result
    }

    # -------------------

    $lec = $?
    $cwd = (Get-Location).Path
    if ($cwd.StartsWith($HOME)) { $cwd = $cwd.Replace($HOME, '~') }
    $cwd = TruncatePath -Path $cwd -MaxChars 60
    $promptString = $null
    $isAdmin = [bool](([Security.Principal.WindowsIdentity]::GetCurrent()).groups -match 'S-1-5-32-544')
    if ($isAdmin) {
        $promptString += Get-AnsiColorString -Text ' ADMIN ' -ForegroundColor BrightWhite -BackgroundColor Red
    }
    else {
        $promptString += Get-AnsiColorString -Text ' PS ' -ForegroundColor BrightWhite -BackgroundColor Magenta
    }
    $promptString += Get-AnsiColorString -Text " $cwd " -ForegroundColor BrightBlack -BackgroundColor Yellow
    try {
        $gitBranch = (git.exe symbolic-ref HEAD 2>&1)
        if ($gitBranch.ToString() -notmatch 'fatal:') {
            $gitBranch = Split-Path -leaf $gitBranch
            $uncommitedChanges = [bool]((git.exe status --porcelain).Length -ne 0)
            $promptString += Get-AnsiColorString -Text " $gitBranch " -ForegroundColor BrightBlack -BackgroundColor @('Green', 'Red')[$uncommitedChanges]
        }
    }
    catch {}
    if (-not [bool]$lec) {
        $promptString += Get-AnsiColorString -Text ' FAIL ' -ForegroundColor Red -Blink
    }
    return "$promptString`n`e[0m> "
}
