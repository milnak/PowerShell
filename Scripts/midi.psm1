<#
.SYNOPSIS
SysEx File Verification Utility

.EXAMPLE
Get-ChildItem -File '*.syx' | Test-SysExFile | Select-Object FileName,Company,Device,Function | ConvertTo-Csv
#>
function Test-SysExFile {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )

    begin {
        Write-Verbose "SysEx file verification for $Path"
    }

    process {
        # Validate file exists
        if (-not (Test-Path $Path)) {
            throw "File not found: $Path"
        }

        # Validate extension
        if ([IO.Path]::GetExtension($Path).ToLower() -ne ".syx") {
            throw "Invalid file type. Expected a .SYX file."
        }

        # Read raw binary - requires full path to file
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))

        if ($bytes.Length -lt 8) {
            throw "SYX file is too small to contain a valid SysEx header."
        }

        # Status byte - start sysex (0XF0)
        $StatusByte = $bytes[0]

        # ID # (i=67; Yamaha)
        $ManufacturerIdByte = $bytes[1]

        # Model Number ID byte ?
        # Sub-status (s=0) & channel number (n=0; ch 1)
        $SubStatusByte = $bytes[2]

        # Format number (f=0; 1 voice)
        $FormatNumberByte = $bytes[3]

        # Byte count MS byte
        $ByteCountMSByte = $bytes[4]
        # $ByteSix   = $bytes[5]

        # Byte count LS byte (b=155; 1 voice)
        $ByteCountLSByte = $bytes[6]

        # ExtraByte
        $ExtraByte = $bytes[7]

        $Company = $null
        $SetMidi = $null
        $Device = $null
        $Function = $null
        $ModelId = $null
        $Operation = $null

        # Build output object
        switch ($ManufacturerIdByte) {
            # ============================
            # SEQUENTIAL CIRCUITS
            # ============================
            0x01 {
                $Company = "Sequential Circuits"
            }

            # ============================
            # BIG BRIAR
            # ============================
            0x02 {
                $Company = "Big Briar"
            }

            # ============================
            # OCTAVE / PLATEAU
            # ============================
            0x03 {
                $Company = "Octave / Plateau"
            }

            # ============================
            # MOOG
            # ============================
            0x04 {
                $Company = "Moog"
            }

            # ============================
            # PASSPORT DESIGNS
            # ============================
            0x05 {
                $Company = "Passport Designs"
            }

            # ============================
            # LEXICON
            # ============================
            0x06 {
                $Company = "Lexicon"
            }

            # ============================
            # KURZWEIL
            # ============================
            0x07 {
                $Company = "Kurzweil"
            }

            # ============================
            # FENDER
            # ============================
            0x08 {
                $Company = "Fender"
            }

            # ============================
            # GULBRANSEN
            # ============================
            0x09 {
                $Company = "Gulbransen"
            }

            # ============================
            # DELTA LABS (AKG ACOUSTICS)
            # ============================
            0x0A {
                $Company = "Delta Labs"
            }

            # ============================
            # SOUND COMP.
            # ============================
            0x0B {
                $Company = "Sound Comp."
            }

            # ============================
            # GENERAL ELECTRO
            # ============================
            0x0C {
                $Company = "General Electro"
            }

            # ============================
            # TECHMAR
            # ============================
            0x0D {
                $Company = "Techmar"
            }

            # ============================
            # MATTHEWS RESEARCH
            # ============================
            0x0E {
                $Company = "Matthews Research"
            }

            # ============================
            # ENSONIQ
            # ============================
            0x0F {
                $Company = "Ensoniq"
            }

            # ============================
            # OBERHEIM
            # ============================
            0x10 {
                $Company = "Oberheim"
                $SetMidi = 0

                switch ($SubStatusByte) {
                    0x02 { $Device = "Matrix-12 / Xpander"; $Function = "Synthesizer"; $ModelID = 0x02 }
                    0x06 { $Device = "Matrix-6 / Matrix-6R / Matrix-1000"; $Function = "Synthesizer"; $ModelID = 0x06 }
                }
            }

            # ============================
            # PAIA (APPLE)
            # ============================
            0x11 {
                $Company = "PAIA"
            }

            # ============================
            # SIMMONS
            # ============================
            0x12 {
                $Company = "Simmons"
            }

            # ============================
            # DIGIDESIGN (Gentle Electric)
            # ============================
            0x13 {
                $Company = "DigiDesign"
            }

            # ============================
            # FAIRLIGHT
            # ============================
            0x14 {
                $Company = "Fairlight"
            }

            # ============================
            # JL COOPER
            # ============================
            0x15 {
                $Company = "JL Cooper"
            }

            # ============================
            # LOWERY
            # ============================
            0x16 {
                $Company = "Lowery"
            }

            # ============================
            # LIN
            # ============================
            0x17 {
                $Company = "Lin"
            }

            # ============================
            # EMU
            # ============================
            0x18 {
                $Company = "Emu"
                $SetMidi = 4

                switch ($SubStatusByte) {
                    0x04 { $Device = "Proteus/1 / Proteus/2 / Proteus/3 / Proteus/FX"; $Function = "Synthesizer"; $ModelID = 0x04 }
                }

                switch ($ByteCountMSByte) {
                    "01" { $Operation = "Preset Data" }
                    "03" { $Operation = "Parameter Value" }
                    "05" { $Operation = "Tuning Table" }
                    "07" { $Operation = "Program Map Data" }
                }

                if ($FormatNumberByte -eq 0x08 -and $ByteCountMSByte -eq 0x01) {
                    $Operation = "MMA Tuning Dump"
                }
            }

            # ============================
            # ART
            # ============================
            0x1A {
                $Company = "ART"
            }

            # ============================
            # PEAVEY
            # ============================
            0x1B {
                $Company = "Peavey"
            }

            # ============================
            # EVENTIDE
            # ============================
            0x1C {
                $Company = "Eventide"
            }

            # ============================
            # SYNTHAXE
            # ============================
            0x1D {
                $Company = "Synthaxe"
            }

            # ============================
            # BON TEMPI
            # ============================
            0x20 {
                $Company = "Bon Tempi"
            }

            # ============================
            # S.I.E.L.
            # ============================
            0x21 {
                $Company = "S.I.E.L."
            }

            # ============================
            # SYNTHEAXE
            # ============================
            0x23 {
                $Company = "Syntheaxe"
            }

            # ============================
            # HOHNER
            # ============================
            0x24 {
                $Company = "Hohner"
            }

            # ============================
            # CRUMAR
            # ============================
            0x25 {
                $Company = "Crumar"
            }

            # ============================
            # SOLTON
            # ============================
            0x26 {
                $Company = "Solton"
            }

            # ============================
            # JELLINGHOUSE MS
            # ============================
            0x27 {
                $Company = "Jellinghouse Ms"
            }

            # ============================
            # CTS
            # ============================
            0x28 {
                $Company = "CTS"
            }

            # ============================
            # PPG
            # ============================
            0x29 {
                $Company = "PPG"
            }

            # ============================
            # SSL
            # ============================
            0x2B {
                $Company = "SSL"
            }

            # ============================
            # HINTON INSTRUMENTS
            # ============================
            0x2D {
                $Company = "Hinton Instruments"
            }

            # ============================
            # ELKA (GENERAL MUSIC)
            # ============================
            0x2F {
                $Company = "Elka"
            }

            # ============================
            # DYNACORD
            # ============================
            0x30 {
                $Company = "Dynacord"
            }

            # ============================
            # CLAVIA (NORD)
            # ============================
            0x33 {
                $Company = "Clavia (Nord)"
            }

            # ============================
            # CHEETAH
            # ============================
            0x36 {
                $Company = "Cheetah"
            }

            # ============================
            # WALDORF (WALDORF ELECTRONICS GMBH)
            # ============================
            0x3E {
                $Company = "Waldorf"
            }

            # ============================
            # KAWAI
            # ============================
            0x40 {
                $Company = "Kawai"
                $SetMidi = 33

                switch ($WordSix) {
                    0x01 { $Device = "K3"; $Function = "Synthesizer"; $ModelID = 0x01 }
                    0x02 { $Device = "K5 / K5m"; $Function = "Synthesizer"; $ModelID = 0x02 }
                    0x03 { $Device = "K1 / K1m / K1r"; $Function = "Synthesizer"; $ModelID = 0x03 }
                    0x04 { $Device = "K4 / K4r"; $Function = "Synthesizer"; $ModelID = 0x04 }
                }

                switch ($FormatNumberByte) {
                    0x21 { $Operation = "All Patch Data Dump" }
                    0x22 { $Operation = "All Patch Data Dump" }
                    0x20 { $Operation = "All Patch Data Dump" }
                }
            }

            # ============================
            # ROLAND
            # ============================
            0x41 {
                $Company = "Roland"
                $SetMidi = 4

                # --- Opcode (ByteFive / ByteThree / wordSix) ---
                switch ($ByteCountMSByte) {
                    0x11 { $Operation = "Request Data (RQ1)" }
                    0x12 { $Operation = "Data Set #1 (DT1) / Bulk Dump" }
                    0x06 { $Device = "JP-8000"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 0x06 }
                    0x20 { $Device = "MKS-80"; $Function = "Synthesizer"; $SetMidi = 4; $ModelID = 20 }
                    0x21 { $Device = "JX-8P"; $Function = "Synthesizer"; $SetMidi = 4; $ModelID = 21 }
                    0x23 { $ModelID = 23 } # Alpha Juno / MKS-50 group
                    0x24 { $Device = "Super JX-10 / MKS-70"; $Function = "Synthesizer"; $SetMidi = 4; $ModelID = 24 }
                }

                switch ($SubStatusByte) {
                    0x34 { $Operation = "All Tone Parameters / Program Number (APR/PGR)" }
                    0x35 { $Operation = "All Patch Parameters (APR)" }
                    0x36 { $Operation = "Individual Parameters (IPR)" }
                    0x37 { $Operation = "Bulk Dump (BLD)" }
                    0x3A { $Operation = "Vecoven v4.xx Bulk Patch Dump" }
                    0x3E { $Operation = "Vecoven v3.xx/4.xx Bootloader/Firmware Upgrade" }
                    0x40 { $Operation = "Want To Send File (WSF)" }
                    0x41 { $Operation = "Request File (RQF)" }
                    0x42 { $Operation = "Data File (DAT)" }
                    0x43 { $Operation = "Acknowledge (ACK)" }
                    0x45 { $Operation = "End Of File (EOF)" }
                    0x4E { $Operation = "Error (ERR)" }
                    0x4F { $Operation = "Rejection (RJC)" }
                }

                # --- Model ID via ByteFour ---
                switch ($FormatNumberByte) {
                    0x00 { if ($ByteCountMSByte -eq 0x07) { $Device = "GR-30"; $Function = "Guitar Synthesizer"; $SetMidi = 17; $ModelID = 0x07 } }
                    0x10 { $Device = "S-10 / MKS-100 / S-220"; $Function = "Sampler"; $SetMidi = 3; $ModelID = 10 }
                    0x14 { $Device = "D-50 / D-550"; $Function = "Synthesizer"; $SetMidi = 3; $ModelID = 14 }
                    0x16 { $Device = "D-5 / D-10 / D-110 / D-20 / MT-32 / GR-50"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 16 }
                    0x18 { $Device = "S-50"; $Function = "Sampler"; $SetMidi = 3; $ModelID = 18 }
                    0x1E { $Device = "S-330 / S-550"; $Function = "Sampler"; $SetMidi = 3; $ModelID = 0x1E }
                    0x23 { $Device = "U-110"; $Function = "Synthesizer"; $SetMidi = 3; $ModelID = 23 }
                    0x2B { $Device = "U-20 / U-220"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 0x2B }
                    0x34 { $Device = "S-700 / S-750 / S-760 / S-770"; $Function = "Sampler"; $SetMidi = 17; $ModelID = 34 }
                    0x35 { $Device = "Rhodes 660 / 760"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 35 }
                    0x39 { $Device = "D-70"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 39 }
                    0x3D { $Device = "JD-800"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 0x3D }
                    0x3E { $Device = "JX-1"; $Function = "Synthesizer"; $SetMidi = 3; $ModelID = 0x3E }
                    0x42 { $Device = "JV-30 / JV-35 / JV-50"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 42 }
                    0x46 { $Device = "JV-80 / JV-90 / JV-880 / JV-1000"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 46 }
                    0x48 { $Device = "Rhodes VK-1000"; $Function = "Synthesizer"; $SetMidi = 3; $ModelID = 48 }
                    0x4D { $Device = "JV-30"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 0x4D }
                    0x54 { $Device = "GR-1"; $Function = "Guitar Synthesizer"; $SetMidi = 17; $ModelID = 54 }
                    0x57 { $Device = "JD-990"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 57 }
                    0x6A { $Device = "JV-1010 / JV-1080 / JV-2080 / XP-30 / XP-50 / XP-60 / XP-80"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 0x6A }
                    0x7B { $Device = "XP-10"; $Function = "Synthesizer"; $SetMidi = 17; $ModelID = 0x7B }
                }

                # --- Alpha Juno / MKS-50 special cases ---
                if ($ByteCountMSByte -eq 0x23) {
                    $Device = "Alpha Juno-1/2, HS-10/80, or MKS-50"
                    $Function = "Synthesizer"
                    $ModelID = 23

                    # TODO: FIX
                    switch ("$SubStatusByte-$WordSix") {
                        "35-20" { $Operation = "All Tone Parameters (APR) - Individual Tone File" }
                        "35-30" { $Operation = "All Patch Parameters (APR)"; $Device = "MKS-50" }
                        "35-40" { $Operation = "All Chord Memory Parameters (APR)"; $Device = "MKS-50" }
                        "36-20" { $Operation = "Individual Tone Parameters (IPR)" }
                        "36-30" { $Operation = "Individual Patch Parameters (IPR)"; $Device = "MKS-50" }
                        "37-20" { $Operation = "All Tone Parameters Bulk Dump (BLD)" }
                        "37-30" { $Operation = "All Patch Parameters Bulk Dump (BLD)"; $Device = "MKS-50" }
                        "37-40" { $Operation = "All Tone Parameters Bulk Dump (BLD)"; $Device = "MKS-50" }
                    }
                }
            }

            # ============================
            # KORG
            # ============================
            0x42 {
                $Company = "Korg"
                $SetMidi = 4

                switch ($FormatNumberByte) {
                    0x19 {
                        $Device = "M1 / M1R"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x19
                        switch ($ByteCountMSByte) {
                            0x1C { $Operation = "Data Dump Request" }
                            0x4C { $Operation = "All Program Dump" }
                            0x50 { $Operation = "All Data Dump" }
                        }
                    }

                    0x2C {
                        $Device = "A1"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x2C
                        switch ($ByteCountMSByte) {
                            0x0F { $Operation = "All Data Dump Request" }
                            0x40 { $Operation = "Program Parameter Dump" }
                            0x50 { $Operation = "All Data Dump" }
                        }
                    }

                    0x2D {
                        $Device = "A2"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x2D
                        switch ($ByteCountMSByte) {
                            0x1C { $Operation = "All Program Parameter Dump Request" }
                            0x40 { $Operation = "Program Parameter Dump" }
                            0x4C { $Operation = "All Program Parameter Dump" }
                        }
                    }

                    0x24 {
                        $Device = "M3 / M3R"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x24
                        switch ($ByteCountMSByte) {
                            0x1C { $Operation = "Data Dump Request" }
                            0x4C { $Operation = "All Program Dump" }
                            0x50 { $Operation = "All Data Dump" }
                        }
                    }

                    0x26 {
                        $Device = "T1 / T2 / T3"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x26
                        switch ($ByteCountMSByte) {
                            0x1C { $Operation = "Data Dump Request" }
                            0x4C { $Operation = "All Program Dump" }
                            0x50 { $Operation = "All Data Dump" }
                        }
                    }

                    0x28 { $Device = "Wavestation"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x28 }
                    0x2B { $Device = "01/W"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x2B }
                    0x30 { $Device = "03R/W"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x30 }
                    0x36 { $Device = "05R/W"; $Function = "Synthesizer"; $SetMidi = 6; $ModelID = 0x36 }
                }

                if ($SubStatusByte -eq 0x21) {
                    $Device = "Poly800 / EX800"
                    $Function = "Synthesizer"
                    $ModelID = 0x21
                }
            }

            # ============================
            # YAMAHA
            # ============================
            0x43 {
                $Company = "Yamaha"

                if ($SubStatusByte -eq 0x75) {
                    $Device = "FB-01"
                    $Function = "Synthesizer"
                    $SetMidi = 4
                    $ModelID = 0x75

                    switch ($ByteCountLSByte) {
                        0x00 { $Operation = "Voice Bank 1" }
                        0x01 { $Operation = "Voice Bank 2" }
                    }
                }

                if ($FormatNumberByte -eq 0x09 -and $ByteCountMSByte -eq 0x20) {
                    $Device = "DX7"
                    $Function = "Synthesizer"
                    $Operation = "Bulk Data Of 32 Voices"
                    $SetMidi = 3
                    $ModelID = 0x00
                }

                if ($FormatNumberByte -eq 0x00 -and $ByteCountMSByte -eq 0x20) {
                    $Device = "DX7"
                    $Function = "Synthesizer"
                    $Operation = "Bulk Data Of 1 Voice"
                    $SetMidi = 3
                    $ModelID = 0x00
                }

                # CP: 0xF0 0x43 0x00 0x7F 0x1C 0x04 0x04
                # DX: 0xF0 0x43 0x00 0x7F 0x1C 0x04 0x05
                if ($SubStatusByte -eq 0x00 -and $ByteCountLSByte -eq 0x04) {
                    switch ($ExtraByte) {
                        0x04 { $Device = "Reface CP" }
                        0x05 { $Device = "Reface DX" }
                        0x09 { $Device = "YC61" }
                    }
                    $Function = "Synthesizer"
                    $ModelID = $ExtraByte
                }
            }

            # ============================
            # CASIO
            # ============================
            0x44 {
                $Company = "Casio"
                $Device = "CZ-1 / CZ-101 / CZ-1000 / CZ-3000 / CZ-5000"
                $Function = "Synthesizer"
                $SetMidi = 5
                $ModelID = 0x44
            }


            # ============================
            # KAMIYA STUDIO
            # ============================
            0x46 {
                $Company = "Kamiya Studio"

            }

            # ============================
            # AKAI
            # ============================
            0x47 {
                $Company = "Akai"
            }

            # ============================
            # VICTOR (JVC)
            # ============================
            0x48 {
                $Company = "Victor"
            }

            # ============================
            # SONY
            # ============================
            0x4C {
                $Company = "Sony"
            }

            # ============================
            # TEAC
            # ============================
            0x4E {
                $Company = "Teac"
            }

            # ============================
            # MATSUSHITA
            # ============================
            0x50 {

            }

            # ============================
            # FOSTEX
            # ============================
            0x51 {
                $Company = "Fostex"
            }

            # ============================
            # ZOOM
            # ============================
            0x52 {
                $Company = "Zoom"
            }

            # ============================
            # SUZUKI
            # ============================
            0x55 {
                $Company = "Suzuki"
            }

            # ============================
            # FUJI SOUND
            # ============================
            0x56 {
                $Company = "Fuji Sound"
            }


            # ============================
            # ACOUSTIC TECHNICAL LABORATORY
            # ============================
            0x57 {
                $Company = "Acoustic Technical Laboratory"
            }

            # ============================
            # BEHRINGER (special SysEx)
            # ============================
            0x00 {
                if ($SubStatusByte -eq 0x20 -and $FormatNumberByte -eq 0x32) {
                    $Company = "Behringer"
                }
            }
        }

        [PSCustomObject]@{
            FileName           = [IO.Path]::GetFileName($Path)
            Company            = $Company
            SetMidi            = $SetMidi
            Device             = $Device
            Function           = $Function
            ModelID            = $ModelID
            Operation          = $Operation

            StatusByte         = '0x{0:X2}' -f $StatusByte
            ManufacturerIdByte = '0x{0:X2}' -f $ManufacturerIdByte
            SubStatusByte      = '0x{0:X2}' -f $SubStatusByte
            FormatNumberByte   = '0x{0:X2}' -f $FormatNumberByte
            ByteCountMSByte    = '0x{0:X2}' -f $ByteCountMSByte
            ByteCountLSByte    = '0x{0:X2}' -f $ByteCountLSByte
            ExtraByte          = '0x{0:X2}' -f $ExtraByte
        }
    }

    end {

    }
}

Export-ModuleMember -Function `
    Test-SysExFile
