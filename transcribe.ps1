<#
.SYNOPSIS
    Parse a Transcribe XSC file into a PowerShell object.

.DESCRIPTION
    Reads the custom XSC format used by the Transcribe application. Sections
    and key/value pairs are converted into nested ordered hashtables, and
    metadata such as version and platform info is captured.

.PARAMETER Path
    Path to the XSC file to read.

.RETURNS
    A PSCustomObject with properties Version, Transcribe, and Data.
#>
function Read-Xsc {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$Path)

    $data = [ordered]@{}

    $version = $null
    $transcribe = $null

    $section = $null

    Get-Content -LiteralPath $Path -ErrorAction Stop | ForEach-Object {
        switch -regex ($_) {
            # [Signature] Document Version
            '^XSC Transcribe.Document Version (\d+\.\d+)' {
                $version = $matches[1]
                Write-Host "XSC Version: $version"
                continue
            }

            # [Signature] System Info (transcribe platform,v_major,v_minor,?,?,?
            '^Transcribe!,(.+)$' {
                $transcribe = $matches[1]
                Write-Host "Transcribe Info: $transcribe"
                continue
            }

            # Each section is in format:
            # SectionStart,<section_name>
            # HowMany,<number_of_keys>
            # Key,Value
            # SectionEnd,<section_name>

            # [Header] SectionStart
            '^SectionStart,(.+)$' {
                if ($section) { throw "Unclosed section: $section" }
                $section = $matches[1]
                $data[$section] = [ordered]@{}
                continue
            }

            # [Header] SectionEnd
            '^SectionEnd,(.+)$' {
                if ($matches[1] -ne $section) { throw "Unmatched SectionEnd: $($matches[1])" }
                $section = $matches[1]
                $section = $null
                continue
            }

            # [Values] key,value
            '^(.+?),(.+)$' {
                $key, $value = $matches[1], $matches[2]
                if ($section -in 'Loops', 'Markers', 'TextBlocks') {
                    # These sections have a variable number of keys and values, so we store the entire line as value with a unique key
                    $key = '*' + (New-Guid).ToString()
                    $value = $_
                }

                $data[$section][$key] = $value
            }
        }
    }

    [PSCustomObject]@{
        Version    = $version
        Transcribe = $transcribe
        Data       = $data
    }
}

<#
.SYNOPSIS
    Serialize an XSC object back to the Transcribe format.

.DESCRIPTION
    Accepts the object produced by Read-Xsc (or modified manually) and emits
    lines suitable for writing to an XSC file. Sections are written with
    SectionStart/SectionEnd markers and key,value pairs.

.PARAMETER XSC
    The object representing the XSC data (from Read-Xsc).
#>
function Write-Xsc {
    [CmdletBinding()]
    param ([Parameter(Mandatory)]$XSC)

    # Write header
    "XSC Transcribe.Document Version $($XSC.Version)"
    "Transcribe!,$($XSC.Transcribe)"

    # Each section is in format:
    # SectionStart,<section_name>
    # HowMany,<number_of_keys>
    # Key,Value
    # SectionEnd,<section_name>
    $data = $XSC.Data
    Foreach ($section in $data.get_keys()) {
        ''
        "SectionStart,$section"
        foreach ($key in $data[$section].get_keys()) {
            if ($key.StartsWith('*')) {
                # Special case for Loops/Markers/TextBlocks where we stored the entire line as value
                $data[$section][$key]
            }
            else {
                '{0},{1}' -f $key, $data[$section][$key]
            }
        }
        "SectionEnd,$section"
    }
}

## Main

<#
.SYNOPSIS
    Fix a Transcribe XSC file to my desired default settings.
.DESCRIPTION
    This script reads a Transcribe XSC file, modifies some settings to my preferred defaults,
    and writes the changes back to the file.
.PARAMETER Path
    The path to the XSC file to fix.
.NOTES
    The XSC file format is meh, so Read-Xsc is a bit weird.
.EXAMPLE
    . c:\Users\jeffm\.local\bin\FixXsc.ps1
     Get-ChildItem -File '*.xsc' | Invoke-FixXsc
#>
function Invoke-FixXsc {
    [CmdletBinding()]
    param(
        # Accept filenames from the pipeline
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File
    )

    begin {
        Write-Host "Starting XSC processing..."
    }

    process {
        try {
            Write-Host "Processing file: $File"
            $xsc = Read-Xsc -Path $File
            if ($null -eq $xsc -or $null -eq $XSC.Version -or $null -eq $XSC.Transcribe) {
                Write-Warning "Failed to read XSC file at path '$File'. Skipping."
                return
            }

            # The values I prefer
            $xsc.Data['Main']['SaveDate'] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
            $xsc.Data['Main']['WindowSize'] = '1706|979|858|410,0'
            $xsc.Data['Main']['ViewList'] = '1,0,0'

            $xsc.Data['View0']['ShowSpectrum'] = '0'
            $xsc.Data['View0']['ShowGuessNotes'] = '0'
            $xsc.Data['View0']['ShowGuessChords'] = '0'
            $xsc.Data['View0']['ShowAsMono'] = '1'
            $xsc.Data['View0']['ShowDB'] = '0'

            $xsc.Data['View0']['ViewSplitterPos'] = '0.79'
            $xsc.Data['View0']['HorizProfileZoom'] = '0.01'

            Write-Host "Writing fixed XSC file to: $File"
            Write-Xsc -XSC $xsc | Out-File -LiteralPath $File
        }
        catch {
            Write-Warning "Failed to read XSC file at path '$File': $_"
        }
    }

    end {
        Write-Host "Finished XSC processing."
    }
}
