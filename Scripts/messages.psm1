<#
.SYNOPSIS
    Display a message inside a colorized box.
.DESCRIPTION
    Prints the provided string(s) surrounded by a Unicode box drawing
    border. Supports optional ANSI color codes for the entire box.
.PARAMETER Message
    The text to show in the box; line breaks are supported.
.PARAMETER ColorCode
    ANSI color code (30–37) used for the box border.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None. Writes the colored box to the host.
.EXAMPLE
    Write-BoxedMessage -Message "First line`nSecond line" -ColorCode 36
#>
function Write-BoxedMessage {
    Param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateRange(30, 37)][int]$ColorCode = 34
    )

    $Color = "`e[0;${ColorCode}m"
    $lines = $Message -split "`n"
    $maxLength = ($lines | Measure-Object -Maximum -Property Length).Maximum
    $separator = '─' * ($maxLength + 2)

    Write-Host "$Color┌$separator┐`e[0m"
    foreach ($line in $lines) {
        $paddedLine = $line.PadRight($maxLength)
        Write-Host "$Color│`e[0m $paddedLine $Color│`e[0m"
    }
    Write-Host "$Color└$separator┘`e[0m`n"
}

<#
.SYNOPSIS
    Generate ASCII art text with figlet and prefix lines with comments.
.DESCRIPTION
    Uses the external figlet program to render input strings as ASCII art
    and prepends each output line with a specified comment character. Useful
    for embedding decorative banners in scripts or documentation.
.PARAMETER Message
    One or more input strings; supports pipeline input.
.PARAMETER CommentIndicator
    Text prefixed to each generated line (e.g. '# ').
.PARAMETER OutputWidth
    Maximum width passed to figlet.
.PARAMETER FontName
    Figlet font name to use.
.INPUTS
    System.String. One or more text lines.
.OUTPUTS
    System.String. Prefixed figlet output and a trailing comment-only line
    for each input string.
.EXAMPLE
    'Utilities' | Write-Figlet -FontName small -CommentIndicator '# '
.NOTES
    Requires figlet.exe on PATH and the selected figlet font.
#>
function Write-Figlet {
    [CmdletBinding()]
    Param(
        # Message(s) to print, can be from pipeline.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)][ValidateNotNullOrEmpty()]
        [string[]]$Message,
        # Language comment indicator, '' for none.
        [string]$CommentIndicator = '# ',
        # Maximum width of message
        [uint]$OutputWidth = 80,
        # Font to use, see "figlet.exe -list", e.g. 'slant'
        [string]$FontName = 'small'
    )

    begin {
        Get-Command -Name 'figlet.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }
    process {
        foreach ($line in $Message) {
            figlet.exe -w $OutputWidth -f $FontName $line | ForEach-Object {
                "$CommentIndicator $_"
            }
            $CommentIndicator
        }
    }
}


<#
.SYNOPSIS
    Render text using bold-looking Unicode characters.
.DESCRIPTION
    Converts ordinary alphanumeric characters into equivalent symbols from
    various Unicode blocks to give the appearance of bold or mathematical
    formatting. Non-alphanumeric characters are preserved when possible.
.PARAMETER Message
    Strings to convert; supports pipeline input.
.INPUTS
    System.String. Text to transform.
.OUTPUTS
    System.String. Text with mapped letters, digits, and selected punctuation.
.EXAMPLE
    'Example 123' | Write-Bold
.NOTES
    Produces Unicode characters, not ANSI bold styling. Unmapped characters
    are unchanged, and display depends on the terminal font.
#>
function Write-Bold {
    [CmdletBinding()]
    Param(
        # Message(s) to print, can be from pipeline.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)][ValidateNotNullOrEmpty()]
        [string[]]$Message
    )

    begin {
        # Mathematical Alphanumeric Symbols Block https://unicodeplus.com/block/1D400
        # Mathematical Operators Block https://unicodeplus.com/block/2200
        # Miscellaneous Mathematical Symbols-A Block https://unicodeplus.com/block/27C0
        # Miscellaneous Mathematical Symbols-B Block https://unicodeplus.com/block/2980
        # Supplemental Mathematical Operators Block https://unicodeplus.com/block/2A00

        # Can't use dictionary, as it is case insensitive by default
        $hash = New-Object  System.Collections.Hashtable ([StringComparer]::Ordinal)
        $hash[[char]'-'] = "`u{22EF}"
        $hash[[char]'('] = "`u{27EE}"
        $hash[[char]')'] = "`u{27EF}"
        $hash[[char]'['] = "`u{27E6}"
        $hash[[char]']'] = "`u{27E7}"
        $hash[[char]'|'] = "`u{2999}"
        $hash[[char]'0'] = "`u{1D7EC}"
        $hash[[char]'1'] = "`u{1D7ED}"
        $hash[[char]'2'] = "`u{1D7EE}"
        $hash[[char]'3'] = "`u{1D7EF}"
        $hash[[char]'4'] = "`u{1D7F0}"
        $hash[[char]'5'] = "`u{1D7F1}"
        $hash[[char]'6'] = "`u{1D7F2}"
        $hash[[char]'7'] = "`u{1D7F3}"
        $hash[[char]'8'] = "`u{1D7F4}"
        $hash[[char]'9'] = "`u{1D7F5}"
        $hash[[char]'A'] = "`u{1D400}"
        $hash[[char]'a'] = "`u{1D41A}"
        $hash[[char]'B'] = "`u{1D401}"
        $hash[[char]'b'] = "`u{1D41B}"
        $hash[[char]'C'] = "`u{1D402}"
        $hash[[char]'c'] = "`u{1D41C}"
        $hash[[char]'D'] = "`u{1D403}"
        $hash[[char]'d'] = "`u{1D41D}"
        $hash[[char]'E'] = "`u{1D404}"
        $hash[[char]'e'] = "`u{1D41E}"
        $hash[[char]'F'] = "`u{1D405}"
        $hash[[char]'f'] = "`u{1D41F}"
        $hash[[char]'G'] = "`u{1D406}"
        $hash[[char]'g'] = "`u{1D420}"
        $hash[[char]'H'] = "`u{1D407}"
        $hash[[char]'h'] = "`u{1D421}"
        $hash[[char]'I'] = "`u{1D408}"
        $hash[[char]'i'] = "`u{1D422}"
        $hash[[char]'J'] = "`u{1D409}"
        $hash[[char]'j'] = "`u{1D423}"
        $hash[[char]'K'] = "`u{1D40A}"
        $hash[[char]'k'] = "`u{1D424}"
        $hash[[char]'L'] = "`u{1D40B}"
        $hash[[char]'l'] = "`u{1D425}"
        $hash[[char]'M'] = "`u{1D40C}"
        $hash[[char]'m'] = "`u{1D426}"
        $hash[[char]'N'] = "`u{1D40D}"
        $hash[[char]'n'] = "`u{1D427}"
        $hash[[char]'O'] = "`u{1D40E}"
        $hash[[char]'o'] = "`u{1D428}"
        $hash[[char]'P'] = "`u{1D40F}"
        $hash[[char]'p'] = "`u{1D429}"
        $hash[[char]'Q'] = "`u{1D410}"
        $hash[[char]'q'] = "`u{1D42A}"
        $hash[[char]'R'] = "`u{1D411}"
        $hash[[char]'r'] = "`u{1D42B}"
        $hash[[char]'S'] = "`u{1D412}"
        $hash[[char]'s'] = "`u{1D42C}"
        $hash[[char]'T'] = "`u{1D413}"
        $hash[[char]'t'] = "`u{1D42D}"
        $hash[[char]'U'] = "`u{1D414}"
        $hash[[char]'u'] = "`u{1D42E}"
        $hash[[char]'V'] = "`u{1D415}"
        $hash[[char]'v'] = "`u{1D42F}"
        $hash[[char]'W'] = "`u{1D416}"
        $hash[[char]'w'] = "`u{1D430}"
        $hash[[char]'X'] = "`u{1D417}"
        $hash[[char]'x'] = "`u{1D431}"
        $hash[[char]'Y'] = "`u{1D418}"
        $hash[[char]'y'] = "`u{1D432}"
        $hash[[char]'Z'] = "`u{1D419}"
        $hash[[char]'z'] = "`u{1D433}"
    }
    process {
        foreach ($line in $Message) {
            # StringBuilder is much faster than string concatenation
            $sb = [Text.StringBuilder]::new()
            foreach ($char in $line.ToCharArray()) {
                $u = $hash[$char]
                $sb.Append(@($char, $u)[$null -ne $u ]) | Out-Null
            }
            $sb.ToString()
        }
    }

}

<#
.SYNOPSIS
    Writes text using a cycling RGB foreground color.
.DESCRIPTION
    Reads existing file paths or text from the pipeline and writes each line
    to the host with an ANSI true-color sequence. A shared counter keeps
    colors and optional line numbers continuous across pipeline items.
.PARAMETER InputObject
    Text, a literal existing file path, or another object convertible to text.
    Null and empty strings are allowed. Accepts values or InputObject properties.
.PARAMETER Frequency
    Sine-wave frequency controlling how quickly colors cycle. Defaults to 0.3.
.PARAMETER NumberLines
    Prefix each displayed line with a right-aligned, one-based line number.
.INPUTS
    System.Object. File paths or values to render as text.
.OUTPUTS
    None. Writes colored text to the host.
.EXAMPLE
Get-Content '.\vcpkg.json','.\Directory.Build.props' | Get-ContentWithRainbow

.EXAMPLE
Get-Content '.\vcpkg.json' | Get-ContentWithRainbow -NumberLines

.EXAMPLE
Get-ChildItem | Get-ContentWithRainbow -Frequency 0.5

.EXAMPLE
"1`n2`n3`n4`n5`n6`n7`n8`n9" | Get-ContentWithRainbow -NumberLines

.EXAMPLE
1..20 | Get-ContentWithRainbow -NumberLines
.NOTES
    Requires an ANSI true-color terminal for the intended display.
#>
function Get-ContentWithRainbow {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [object] $InputObject,
        [double] $Frequency = 0.3,
        [switch] $NumberLines
    )
    begin {
        $lineCounter = 1
    }
    process {
        <#
        .SYNOPSIS
        Calculates RGB components for a position in the rainbow cycle.
        .DESCRIPTION
        Uses three phase-shifted sine waves to produce integer color components.
        .PARAMETER Freq
        Frequency multiplier controlling the color-cycle speed.
        .PARAMETER I
        Position in the sequence, normally the current line number.
        .INPUTS
        None. This function does not accept pipeline input.
        .OUTPUTS
        System.Collections.Hashtable. Red, Green, and Blue components.
        .EXAMPLE
        Get-RainbowColor -Freq 0.3 -I 1
        .NOTES
        Local helper for Get-ContentWithRainbow.
        #>
        function Get-RainbowColor {
            param(
                [double]$Freq,
                [double]$I
            )
            @{
                Red   = [int]([Math]::Sin($Freq * $I + 0) * 127 + 128)
                Green = [int]([Math]::Sin($Freq * $I + (2 * [Math]::PI / 3)) * 127 + 128)
                Blue  = [int]([Math]::Sin($Freq * $I + (4 * [Math]::PI / 3)) * 127 + 128)
            }
        }
        if ($InputObject -is [string] -and (Test-Path -LiteralPath $InputObject)) {
            # If the input is a file path and exists, read it
            $lines = Get-Content -LiteralPath $InputObject
        }
        else {
            $lines = $InputObject -split "`n`r?"
        }
        foreach ($line in $lines) {
            $color = Get-RainbowColor -Freq $Frequency -I $lineCounter
            Write-Verbose "`R=$($color.Red); G=$($color.Green); B=$($color.Blue)"
            if ($NumberLines) {
                Write-Host ("{0,4}: `e[38;2;$($color.Red);$($color.Green);$($color.Blue)m{1}`e[0m" -f $lineCounter, $line)
            }
            else {
                Write-Host "`e[38;2;$($color.Red);$($color.Green);$($color.Blue)m$($line)`e[0m"
            }
            $lineCounter++
        }
    }
}

Export-ModuleMember -Function `
    Get-ContentWithRainbow, `
    Write-Bold, `
    Write-BoxedMessage, `
    Write-Figlet
