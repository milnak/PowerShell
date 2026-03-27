<#
.SYNOPSIS
Reads a Sibelius score file and determines its internal version code.

.DESCRIPTION
Validates the Sibelius file header and extracts the 32‑bit version
identifier, returning both the raw version code and the corresponding
Sibelius release (when known).

.EXAMPLE
Get-SibeliusFileVersion -Path "score.sib"

.EXAMPLE
Get-ChildItem *.sib | Get-SibeliusFileVersion
#>
function Get-SibeliusFileVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Error "File not found: $Path"
            return
        }

        # Read first 16 bytes
        $fileStream = [IO.File]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] 16
            $bytesRead = $fileStream.Read($buffer, 0, $buffer.Count)
        }
        finally {
            $fileStream.Close()
        }

        if ($bytesRead -lt 16) {
            Write-Error "File is too small to be a valid Sibelius file: $Path"
            return
        }

        # Validate header
        if ($buffer[0] -ne 0x0F `
                -or [Text.Encoding]::UTF8.GetString($buffer[1..0x8]) -ne 'SIBELIUS' `
                -or $buffer[0x09] -ne 0x00) {

            Write-Error "Not a valid Sibelius file: $Path"
            return
        }

        # Extract version (bytes reversed)
        $ver = [BitConverter]::ToUint32(@(
                $buffer[0x0D], $buffer[0x0C], $buffer[0x0B], $buffer[0x0A]
            ), 0)

        # Map version to known releases
        $versionName = switch ($ver) {
            0x002D0003 { 'Sibelius 5.0' }
            0x002D000D { 'Sibelius 5.1' }
            0x002D0010 { 'Sibelius 5.2.x' }
            0x00360001 { 'Sibelius 6.0.x' }
            0x00360017 { 'Sibelius 6.1' }
            0x0036001E { 'Sibelius 6.2' }
            0x0039000C { 'Sibelius 7.0' }
            0x0039000E { 'Sibelius 7.0.1 - 7.0.2' }
            0x00390013 { 'Sibelius 7.0.3' }
            0x00390015 { 'Sibelius 7.1' }
            0x00390016 { 'Sibelius 7.1.2 - 7.1.3' }
            0x003D000E { 'Sibelius 7.5.x' }
            0x003D0010 { 'Sibelius 8.0.0 - 8.0.1' }
            0x003E0000 { 'Sibelius 8.1.x' }
            0x003E0001 { 'Sibelius 8.2' }
            0x003E0002 { 'Sibelius 8.3' }
            0x003E0006 { 'Sibelius 8.4.x' }
            0x003E0007 { 'Sibelius 8.5.x' }
            0x003F0000 { 'Sibelius 8.6.x - 8.7.1' }
            0x003F0001 { 'Sibelius 8.7.2 - 2018.7' }
            0x003F0002 { 'Sibelius 2018.11 - 2018.12' }
            0x003F0004 { 'Sibelius 2019.1 - 2019.3' }
            0x003F0005 { 'Sibelius 2019.4' }
            0x003F0006 { 'Sibelius 2019.4 - 2019.12' }
            0x003F0007 { 'Sibelius 2019.4 - 2019.12' }
            0x003F0009 { 'Sibelius 2019.4 - 2019.12' }
            0x003F000A { 'Sibelius 2019.4 - 2019.12' }
            0x003F000B { 'Sibelius 2020.1' }
            0x00400001 { 'Sibelius 2020.3' }
            0x00400003 { 'Sibelius 2020.3 - 2022.5' }
            0x00410001 { 'Sibelius 2022.9' }
            0x00420001 { 'Sibelius 2023.2 - 2023.3.1' }
            0x00430006 { 'Sibelius 2023.4 ?' }
            0x00430007 { 'Sibelius 2023.5 - 2023.8' }
            0x00440003 { 'Sibelius 2023.11 - 2024.10' }
            0x00450003 { 'Sibelius 2025.4' }
            default {
                # Try 16‑bit fallback
                $ver16 = [BitConverter]::ToUint16(@(
                        $buffer[0x0B], $buffer[0x0A]
                    ), 0)

                switch ($ver16) {
                    0x0008 { 'Sibelius 2.x' }
                    0x000A { 'Sibelius 3.x' }
                    0x001B { 'Sibelius 4.x' }
                    0x001C { 'Sibelius 4.x' }
                    default { "Unknown Sibelius version (code: {0:x8})" -f $ver }
                }
            }
        }

        # Output object
        [PSCustomObject]@{
            Path        = $Path
            VersionCode = ('0x{0:x8}' -f $ver)
            Version     = $versionName
        }
    }
}
