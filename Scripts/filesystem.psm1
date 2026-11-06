<#
.SYNOPSIS
    Create a directory and change into it.
.DESCRIPTION
    Ensures the specified directory exists (creating it if necessary) and
    then pushes the location stack to that path.
.PARAMETER Path
    Directory path to create and enter.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None. Changes the current location and location stack.
.EXAMPLE
    New-FolderAndSetLocation -Path '.\work'
#>
function New-FolderAndSetLocation {
    [CmdletBinding()]
    Param([Parameter(Mandatory)][string]$Path)

    if (New-Item -Path $Path -ItemType Directory -Force) {
        Push-Location -LiteralPath $Path
    }
}


<#
.SYNOPSIS
Creates a randomly named temporary directory and enters it.
.DESCRIPTION
Creates a directory under the system temporary path, pushes it onto the
location stack, and returns its path for later use.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. The full path of the new directory.
.EXAMPLE
$work = New-TempFolderAndSetLocation
.NOTES
The directory is not automatically removed. Use Pop-Location to return.
#>
function New-TempFolderAndSetLocation {
    [CmdletBinding()]
    $tempPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    Push-Location -LiteralPath $tempPath
    $tempPath
}


<#
.SYNOPSIS
Moves existing items to the Windows Recycle Bin.
.DESCRIPTION
Uses the Shell.Application COM delete verb for each literal path, warning
for missing items. Supports -WhatIf and -Confirm.
.PARAMETER Paths
One or more paths to recycle. Accepts strings from the pipeline.
.INPUTS
System.String. One or more item paths.
.OUTPUTS
None.
.EXAMPLE
Get-ChildItem -File '*.tmp' | Select-Object -ExpandProperty FullName | Remove-ItemToRecycleBin -WhatIf
.NOTES
Requires Windows Shell COM support. The Shell object is created even with
-WhatIf; actual recycling depends on the shell and target volume.
#>
function Remove-ItemToRecycleBin {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)][ValidateNotNullOrEmpty()]
        [string[]]$Paths
    )

    begin {
        $shell = New-Object -ComObject 'Shell.Application'
    }

    process {
        foreach ($path in $Paths) {
            if (Test-Path -LiteralPath $path) {
                if ($PSCmdlet.ShouldProcess($path, 'Move to Recycle Bin')) {
                    Write-Verbose "Removing to Recycle Bin: $path"
                    $item = Get-Item -LiteralPath $path
                    $directoryPath = Split-Path -Path $item -Parent
                    $shell.Namespace($directoryPath).ParseName($item.Name).InvokeVerb('delete')
                }
            }
            else {
                Write-Warning "Path not found: $path"
            }
        }
    }

    end {}
}


<#
.SYNOPSIS
Removes a folder recursively.

.DESCRIPTION
Validates that the target is a directory and not a filesystem root, then
requires the literal response yes before recursively removing it.

.PARAMETER Path
    Directory path to remove.
.PARAMETER Recycle
    Recycle enumerated files using Windows Shell COM before permanently
    removing the directory tree. The directory itself is not recycled.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    None.
.EXAMPLE
    Remove-FolderRecursive -Path '.\obsolete-output' -Recycle
.NOTES
    Permanently removes remaining contents with -Recurse -Force after
    confirmation. Does not support -WhatIf or -Confirm.
#>
function Remove-FolderRecursive {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Recycle
    )

    begin {
        Write-Verbose '[begin] Remove-FolderRecursive'

        if ($Recycle) {
            $shell = New-Object -ComObject 'Shell.Application'
        }

        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

        if (-not $directory.PSIsContainer) {
            throw "'$Path' is not a directory."
        }

        $root = [IO.Path]::GetPathRoot($directory.FullName)
        if ($directory.FullName.TrimEnd('\') -eq $root.TrimEnd('\')) {
            throw "Refusing to remove filesystem root '$($directory.FullName)'."
        }
    }

    process {
        Write-Verbose '[process] Remove-FolderRecursive: $Path'
        Write-Host -NoNewline "Really remove '`e[37;1;3m$Path`e[0m'? ('yes' to confirm): "
        if ((Read-Host) -eq 'yes') {
            if ($Recycle) {
                Write-Verbose "Recycling files in: $($directory.FullName)"
                foreach ($file in (Get-ChildItem -LiteralPath $directory.FullName -Recurse -File)) {
                    Write-Verbose "Recycling: $file"
                    $directoryPath = Split-Path -Path $file -Parent
                    $shell.Namespace($directoryPath).ParseName($file.Name).InvokeVerb('delete')
                }
            }

            Write-Verbose "Removing: $($directory.FullName)"
            Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction Stop
        }
    }

    end {
        Write-Verbose '[end] Remove-FolderRecursive'
    }
}


<#
.SYNOPSIS
Returns full paths of files matching a recursive search.
.DESCRIPTION
Searches files below a literal starting directory using the filesystem
provider's filename filter. Defaults to all files below the current directory.
.PARAMETER Filter
Filename filter such as *.ps1. Defaults to *.
.PARAMETER Path
Starting directory. Defaults to the current directory.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Full file paths.
.EXAMPLE
Invoke-RecursiveFileFind -Filter '*.ps1' -Path '.\Scripts'
#>
function Invoke-RecursiveFileFind {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [ValidateNotNullOrEmpty()] [string]$Filter = '*',
        [Parameter(Position = 1)] [ValidateNotNullOrEmpty()] [string]$Path = '.'
    )

    Get-ChildItem -Recurse -File -Filter $Filter -LiteralPath $Path | Select-Object -ExpandProperty FullName
}


<#
.SYNOPSIS
Searches recursively for lines matching a regular expression.
.DESCRIPTION
Enumerates files under the current directory with the specified filename
filter and passes them to Select-String.
.PARAMETER Pattern
Regular expression to search for in file contents.
.PARAMETER Files
Filename filter, not a starting path. The default is the literal filter .
so supply a filter such as * or *.psm1 to select ordinary files.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
Microsoft.PowerShell.Commands.MatchInfo. Matching lines and their locations.
.EXAMPLE
Invoke-RecursiveGrep -Pattern 'Export-ModuleMember' -Files '*.psm1'
#>
function Invoke-RecursiveGrep {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$Pattern,
        [Parameter(Position = 1)] [string]$Files = '.'
    )
    Get-ChildItem -Recurse -File -Filter $Files | Select-String -Pattern $Pattern
}

<#
.SYNOPSIS
    Compute SHA256 hashes similar to UNIX sha256sum.
.DESCRIPTION
    Takes file paths from pipeline or arguments, outputs lowercase hash and
    relative path, separated by ' *' like the UNIX tool.
.PARAMETER File
    File path to hash. Accepts pipeline strings or objects with FullName
    or Path properties; those names are also parameter aliases.
.INPUTS
    System.String, or objects with FullName or Path properties.
.OUTPUTS
    System.String. Lowercase SHA256 hash and relative filename in sha256sum
    binary-mode format, with forward slashes as path separators.
.EXAMPLE
    Get-ChildItem -File '*.zip' | Get-FileSha256Hash
#>
function Get-FileSha256Hash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File
    )

    begin {}
    process {
        $target = (Resolve-Path $File).Path
        Write-Verbose "Hashing $File"
        # Get-ChildItem -Recurse -File | ForEach-Object {
        '{0} *{1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLower(), (Resolve-Path -Relative $target).Substring(2) -replace '\\', '/'
    }
    end {}
    clean {}

}


<#
.SYNOPSIS
Returns hexadecimal and Base64 file hashes.
.DESCRIPTION
Reads each file using the selected hash algorithm and returns both encodings
alongside the algorithm and resolved path.
.PARAMETER Path
One or more literal file paths. Accepts pipeline strings or Path properties.
.PARAMETER Algorithm
SHA1, SHA256, SHA384, SHA512, or MD5. Defaults to SHA256.
.INPUTS
System.String, or objects with a Path property.
.OUTPUTS
System.Management.Automation.PSCustomObject. Algorithm, Hash, HashBase64,
and Path properties.
.EXAMPLE
Get-FileHashBase64 -Path '.\archive.zip' -Algorithm SHA256
#>
function Get-FileHashBase64 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path,
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5', IgnoreCase)]
        [string]$Algorithm = 'SHA256'
    )

    begin {
        $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        Write-Verbose "Get-FileHashBase64 begin : $Algorithm"
    }

    process {
        foreach ($file in $Path) {
            $resolvedFile = Resolve-Path -LiteralPath $file
            Write-Verbose "Get-FileHashBase64 process $resolvedFile"
            $hash = $hashAlgorithm.ComputeHash([IO.File]::OpenRead($resolvedFile))
            [PSCustomObject]@{
                'Algorithm'  = $Algorithm
                'Hash'       = [BitConverter]::ToString($hash) -replace '-', ''
                'HashBase64' = [Convert]::ToBase64String($hash)
                'Path'       = $resolvedFile
            }
        }
    }

    end {
        $hashAlgorithm.Dispose()
        Write-Verbose 'Get-FileHashBase64 end'
    }
}


<#
.SYNOPSIS
Shows the 15 largest directory entries reported by Sysinternals DU.
.DESCRIPTION
Reads DU's depth-one CSV report, sorts by on-disk size, and returns the first
15 entries with formatted size and path properties.
.PARAMETER Path
Directory to measure. Defaults to the current directory.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.Management.Automation.PSCustomObject. Size and Path properties.
.EXAMPLE
Invoke-DU -Path 'C:\Tools'
.NOTES
Requires Sysinternals du.exe on PATH.
#>
function Invoke-DU {
    [CmdletBinding()]
    param ([ValidateNotNullOrEmpty()] [string]$Path = '.')

    begin {
        Get-Command -Name 'du.exe' -CommandType Application -ErrorAction Stop | Out-Null
    }

    process {
        du.exe -nobanner -c -l 1 $Path
        | ConvertFrom-Csv
        | Sort-Object -Descending { [uint64]$_.DirectorySizeOnDisk }
        | Select-Object -First 15 @{ Name = 'Size'; Expression = { '{0,15:N0}' -f [uint64]$_.DirectorySizeOnDisk } }, Path
    }
}


<#
.SYNOPSIS
    Take ownership of a file or folder.
.DESCRIPTION
    Runs takeown and grants the current user's SID full control using icacls.
    Directories are processed recursively. Supports -WhatIf and -Confirm.
.PARAMETER File
    File or directory path. Accepts pipeline strings or objects with FullName
    or Path properties; those names are also parameter aliases.
.INPUTS
    System.String, or objects with FullName or Path properties.
.OUTPUTS
    System.String. Native takeown and icacls output.
.NOTES
    takeown.exe and icacls.exe (both included in Windows) need to be in $env:PATH
    An elevated PowerShell session is required, including when using -WhatIf.

    If a folder is specified, all files and subfolders of that folder will change ownership.
.EXAMPLE
    Set-SelfOwnership 'd:\temp\v.ps1'

    Set-SelfOwnership -Confirm 'd:\temp\v.ps1'

    Get-ChildItem  'd:\temp\g*' | Set-SelfOwnership -WhatIf  -Verbose
#>
function Set-SelfOwnership {
    # Support -Confirm, -WhatIf
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File
    )

    begin {
        Write-Verbose 'Set-SelfOwnership begin'

        # Ensure admin
        If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Admin privileges required'
        }

        # Check for required apps.
        'takeown', 'icacls' | ForEach-Object {
            Get-Command -Name "$_.exe" -CommandType Application -ErrorAction Stop | Out-Null
        }

        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }

    process {
        Write-Verbose "Taking ownership of $File"
        $ResolvedPath = Resolve-Path -LiteralPath $File -ErrorAction Stop
        if ($PSCmdlet.ShouldProcess($ResolvedPath, 'Take Ownership')) {
            if (Test-Path -LiteralPath $ResolvedPath -PathType Container) {
                takeown.exe /f $ResolvedPath /r /d y
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed: $LASTEXITCODE"
                }
            }
            else {
                takeown.exe /f $ResolvedPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed: $LASTEXITCODE"
                }
            }

            Write-Verbose "Granting full control to current user SID $currentUserSid"
            icacls.exe $ResolvedPath /grant "*${currentUserSid}:(F)" /t
            if ($LASTEXITCODE -ne 0) {
                throw "Failed: $LASTEXITCODE"
            }
        }
    }

    end {
        Write-Verbose 'Set-SelfOwnership end'
    }
}


<#
.SYNOPSIS
Displays drive capacity, free space, and usage in a table.
.DESCRIPTION
Queries volumes with drive letters and formats free/total GiB and a ten-block
usage indicator, sorted by drive letter.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
Microsoft.PowerShell.Commands.Internal.Format.FormatStartData and related
formatting records, not reusable volume objects.
.EXAMPLE
Get-DiskUsage
.NOTES
Requires the Windows Get-Volume command.
#>
function Get-DiskUsage {
    [CmdletBinding()]
    param()
    Get-Volume `
    | Where-Object DriveLetter -ne $null `
    | Sort-Object DriveLetter `
    | Select-Object -Property DriveLetter, FileSystemLabel, `
    @{Label = 'FreeGb'; Expression = { ($_.SizeRemaining / 1GB).ToString('F2') } }, `
    @{Label = 'TotalGb'; Expression = { ($_.Size / 1GB).ToString('F2') } }, `
    @{Label = 'Used %'; Expression = {
            $pct = 100 - ($_.SizeRemaining / $_.Size) * 100
            $blocks = [Math]::Floor($pct / 10)
            '{0,6:F2}% {1}{2}' -f $pct, ('■' * $blocks), ('□' * (10 - $blocks))
        }
    } `
    | Format-Table
}


<#
.SYNOPSIS
Returns a recursive directory tree as text.
.DESCRIPTION
Lists directories alphabetically, including hidden entries. Optionally
includes files before subdirectories and uses ASCII branch characters.
.PARAMETER Path
Root directory to display. Defaults to the current location.
.PARAMETER ShowFiles
Include files, including hidden files, in each directory.
.PARAMETER UseAscii
Use ASCII connectors instead of Unicode box-drawing characters.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Root label and tree lines.
.EXAMPLE
Get-ChildItemTree -Path '.\Scripts' -ShowFiles -UseAscii
#>
function Get-ChildItemTree {
    param(
        [string]$Path = (Get-Location).Path,
        # Display the names of the files in each folder.
        [switch]$ShowFiles,
        # Use ASCII instead of extended characters.
        [switch]$UseAscii
    )

    if ($UseAscii) {
        $pipe = '|'
        $tee = '+'
        $elbow = '\'
        $dash = '-'
    }
    else {
        $pipe = [char]0x2502    # │
        $tee = [char]0x251C     # ├
        $elbow = [char]0x2514   # └
        $dash = [char]0x2500    # ─
    }

    <#
    .SYNOPSIS
    Emits the entries beneath one directory in a text tree.
    .DESCRIPTION
    Recursively renders sorted directories and optional files using connector
    characters and ShowFiles from the enclosing Get-ChildItemTree invocation.
    .PARAMETER Dir
    Directory whose children should be rendered.
    .PARAMETER Prefix
    Indentation and continuation connectors preceding each rendered line.
    .INPUTS
    None. This function does not accept pipeline input.
    .OUTPUTS
    System.String. Tree lines below Dir.
    .EXAMPLE
    Show-TreeDir -Dir $root -Prefix ''
    .NOTES
    Local helper; requires the enclosing function's rendering variables.
    #>
    function Show-TreeDir {
        param(
            [string]$Dir,
            [string]$Prefix = ""
        )

        $subdirs = @(Get-ChildItem -Path $Dir -Directory  -Force | Sort-Object Name)
        $hasDirs = $subdirs.Count -gt 0

        if ($ShowFiles) {
            $files = @(Get-ChildItem -Path $Dir -File -Force | Sort-Object Name)

            # Files listed first; use │ continuation when subdirs follow
            $fileIndent = if ($hasDirs) { "$pipe   " } else { "    " }
            foreach ($f in $files) {
                Write-Output "$Prefix$fileIndent$($f.Name)"
            }

            # Blank separator between files and directories
            if ($files.Count -gt 0 -and $hasDirs) {
                Write-Output "$Prefix$pipe"
            }
        }

        # Subdirectories
        for ($i = 0; $i -lt $subdirs.Count; $i++) {
            $isLast = ($i -eq $subdirs.Count - 1)
            $connector = if ($isLast) { "$elbow$([string]$dash * 3)" } else { "$tee$([string]$dash * 3)" }
            $childPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix$pipe   " }

            Write-Output "$Prefix$connector$($subdirs[$i].Name)"
            Show-TreeDir -Dir $subdirs[$i].FullName -Prefix $childPrefix
        }
    }

    # Print root label (drive + relative path like Windows tree)
    $root = (Resolve-Path $Path -ErrorAction Stop).Path
    $cwd = (Get-Location -ErrorAction Stop).Path
    $drive = Split-Path $cwd -Qualifier
    if ($root -eq $cwd) {
        Write-Output "${drive}."
    }
    else {
        Write-Output "$drive$((Split-Path $root -NoQualifier).TrimStart('\'))"
    }

    Show-TreeDir -Dir $root
}

<#
.SYNOPSIS
    Synchronizes selected backup contents to a destination on drive F:.
.DESCRIPTION
    Runs Robocopy recursively with /PURGE, /XO, no retries, and exclusions
    for system folders, temporary data, executables, and disk-image formats.
    Creates the destination and reports Robocopy's bitmask exit status.
.PARAMETER Source
    Existing source directory.
.PARAMETER Destination
    Destination directory whose drive qualifier must be F:.
.PARAMETER WhatIf
    Pass /L to Robocopy to list operations instead of copying or deleting.
    The destination directory is still created before Robocopy runs.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Robocopy console output.
.NOTES
    Requires robocopy.exe and attrib.exe. /PURGE deletes destination entries
    absent from the source; /XO skips older source files. Normal runs write
    a timestamped log under $env:TEMP, not the destination directory.

.EXAMPLE
    Invoke-RobocopyBackup -Source $env:USERPROFILE -Destination 'f:\PCBackup\UserProfile'

#>
function Invoke-RobocopyBackup {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [switch]$WhatIf
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Cannot find source `"$Source`""
    }

    if ((Split-Path -Path $Destination -Qualifier) -ne 'F:') {
        throw "Destination drive must be F:."
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    # $logFile = Join-Path -Path $Destination -ChildPath ('Backup-{0:yyyy-MM-dd_HH-mm-ss}.log' -f (Get-Date))
    $logFile = Join-Path -Path $env:TEMP -ChildPath ('Backup-{0:yyyy-MM-dd_HH-mm-ss}.log' -f (Get-Date))

    $copyOptions = @(
        # copy subdirectories, including Empty ones.
        '/E'
        # what to COPY for files (default is /COPY:DAT)
        # '/COPY:DT'
        # delete dest files/dirs that no longer exist in source.
        '/PURGE'
        # Do multi-threaded copies with n threads (default 8).
        '/MT:2'
    )

    $excludeFiles = @(
        '*.APPICON'
        '*.APPINFO'
        '*.CAB'
        '*.DL_'
        '*.DLL'
        '*.DMG'
        '*.DRK'
        '*.EXE'
        '*.FDD'
        '*.HDD'
        '*.HDS'
        '*.ISO'
        '*.ITHMB'
        '*.LOG'
        '*.MEM'
        '*.MENUDATA'
        '*.MSI'
        '*.NVRAM'
        '*.O'
        '*.OST'
        '*.PVA'
        '*.PVI'
        '*.PVM'
        '*.PVS'
        '*.QTCH'
        '*.SPARSEIMAGE'
        '*.SYS'
        '*.VDI'
        '*.VHD'
        '*.VHDX'
        '*.VMC'
        '*.VMDK'
        '*.VMEM'
        '*.VMSD'
        '*.VMSN'
        '*.VMSS'
        '*.VMX'
        '*.VMXF'
        '*.VO1'
        '*.VO2'
        '*.VSV'
        '*.VUD'
        '*.WAB~'
        '*.WIM'
        '.DS_Store'
        'DumpStack.log.tmp'
        'DESKTOP.INI'
        'hiberfil.sys'
        'NTUSER.DAT'
        'pagefile.sys'
    )

    # Excluded directories do not exclude subfolders when full path is specified !!!

    $excludeDirectories = @(
        '.bzvol'
        '$RECYCLE.BIN'
        '$WINDOWS.~BT'
        'Windows.~WS'
        'I386'
        'MSOCACHE'
        'OneDriveTemp'
        'System Volume Information'
        # "${env:ProgramFiles(x86)}"
        'Program Files (x86)'
        # "$env:AppData"
        'Roaming'
        # "$env:LocalAppData"
        # 'Local'
        # ???
        'LocalLow'
        # "$env:ProgramData"
        'ProgramData'
        # "$env:ProgramFiles"
        'Program Files'
        # "$env:SYSTEMROOT"
        # "$env:ProgramData\MICROSOFT\WINDOWS\APPREPOSITORY"
        'Windows'
        # "$env:USERPROFILE\.copilot"
        '.copilot'
        # "$env:USERPROFILE\.vscode"
        '.vscode'
        # "$env:USERPROFILE\.vscode-shared"
        '.vscode-shared'
        # "$env:USERPROFILE\scoop"
        'scoop'
        # '"$env:LocalAppData\PACKAGES"'
        'Packages'
        'RECYCLER'
        'Temp'
    )

    $fileSelectionOptions = @(
        # eXclude Older files.
        '/XO'
        # eXclude symbolic links (for both files and directories) and Junction points.
        '/XJ'
        # assume FAT File Times (2-second granularity).
        # '/FFT'
        # eXclude Files matching given names/paths/wildcards.
        '/XF'
        $excludeFiles
        # eXclude Directories matching given names/paths.
        '/XD'
        $excludeDirectories
    )

    $retryOptions = @(
        # number of Retries on failed copies: default 1 million.
        '/R:0'
        # Wait time between retries: default is 30 seconds.
        '/W:0'
    )

    if ($WhatIf) {
        # List only - don't copy, timestamp or delete any files.
        $loggingOptions += '/L'
    }
    else {
        $loggingOptions = @(
            # No Size - don't log file sizes.
            '/NS'
            # No Progress - don't display percentage copied.
            # '/NP'
            # show Estimated Time of Arrival of copied files.
            '/ETA'
            # output status to LOG file.
            "/LOG:$logFile"
            # output to console window, as well as the log file.
            '/TEE'
        )
    }

    $robocopyArgs = $copyOptions + $fileSelectionOptions + $retryOptions + $loggingOptions

    & robocopy.exe $source $destination @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
    # https://ss64.com/nt/robocopy-exit.html
    if ($robocopyExitCode -eq 0) {
        Write-Host -ForegroundColor Yellow 'No errors occurred, and no copying was done.'
        Write-Host 'The source and destination directory trees are completely synchronized.'
    }
    else {
        if ($robocopyExitCode -band 1) {
            Write-Host -ForegroundColor Green 'One or more files were copied successfully (that is, new files have arrived).'
        }

        if ($robocopyExitCode -band 2) {
            Write-Host -ForegroundColor Yellow 'Some Extra files or directories were detected. No files were copied.'
            Write-Host 'Examine the output log for details.'
        }

        if ($robocopyExitCode -band 4) {
            Write-Host -ForegroundColor Yellow 'Some Mismatched files or directories were detected.'
            Write-Host 'Examine the output log. Housekeeping might be required.'
        }

        if ($robocopyExitCode -band 8) {
            Write-Host -ForegroundColor Red 'Some files or directories could not be copied (copy errors occurred and the retry limit was exceeded).'
            Write-Host 'Check these errors further.'
        }

        if ($robocopyExitCode -band 16) {
            Write-Host -ForegroundColor Red 'Serious error. Robocopy did not copy any files.'
            Write-Host 'Either a usage error or an error due to insufficient access privileges on the source or destination directories.'
        }

        Write-Host "Log file: $logFile"

        & attrib.exe -h -s $destination
    }

}

Set-Alias -Name mdcd -Value New-FolderAndSetLocation
Set-Alias -Name mdcdtemp -Value New-TempFolderAndSetLocation
Set-Alias -Name rff -Value Invoke-RecursiveFileFind
Set-Alias -Name rgrep -Value Invoke-RecursiveGrep
Set-Alias -Name rmr -Value Remove-ItemToRecycleBin
Set-Alias -Name rmrf -Value Remove-FolderRecursive
Set-Alias -Name tree -Value Get-ChildItemTree

Export-ModuleMember -Function `
    Get-ChildItemTree, `
    Get-DiskUsage, `
    Get-FileHashBase64, `
    Get-FileSha256Hash, `
    Invoke-DU, `
    Invoke-RecursiveFileFind, `
    Invoke-RecursiveGrep, `
    Invoke-RobocopyBackup, `
    New-FolderAndSetLocation, `
    New-TempFolderAndSetLocation, `
    Remove-FolderRecursive, `
    Remove-ItemToRecycleBin, `
    Set-SelfOwnership, `
    Show-TreeDir

Export-ModuleMember -Alias `
    mdcd, `
    mdcdtemp, `
    rff, `
    rgrep, `
    rmrf, `
    tree

