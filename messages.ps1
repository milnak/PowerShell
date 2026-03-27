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
    Create a directory and change into it.
.DESCRIPTION
    Ensures the specified directory exists (creating it if necessary) and
    then pushes the location stack to that path.
.PARAMETER Path
    Directory path to create and enter.
#>
function mdcd {
    [CmdletBinding()]
    Param([Parameter(Mandatory)][string]$Path)

    if (New-Item -Path $Path -ItemType Directory -Force) {
        Push-Location -LiteralPath $Path
    }
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

