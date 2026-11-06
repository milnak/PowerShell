<#
.SYNOPSIS
Open git repo homepage.
.DESCRIPTION
Opens the remote origin URL of the current git repository in the default browser.
Run from anywhere inside of a local git project. Use -Root to open the repository
root rather than the current subdirectory path.
.PARAMETER Root
Open the origin URL without appending the current repository-relative path.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
None. Launches the default URL handler.
.EXAMPLE
Invoke-GitRepo -Root
.NOTES
Requires git.exe, an origin remote expressible as a URI, and a browser.
#>
function Invoke-GitRepo {
    [CmdletBinding()]
    Param(
        # Launch browser to root of repo?
        [switch]$Root
    )

    if ($origin = [Uri](git.exe config --get remote.origin.url)) {
        if ($Root) {
            $uri = $origin.AbsoluteUri
        }
        else {
            $uri = [uri]($origin.AbsoluteUri + '?path=/' + (git.exe rev-parse --show-prefix))
        }
        Start-Process -FilePath $uri
    }
}


<#
.SYNOPSIS
Copies existing changed Git files into a timestamped backup directory.
.DESCRIPTION
Reads git status --porcelain=v1, skips deleted entries, and copies listed
paths while retaining their relative directories. Saves gitstatus.txt with
the backup. Supports -WhatIf and -Confirm.
.PARAMETER Destination
Parent directory for the FileDateTime-named backup folder.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
None. Copy progress is written to the verbose stream.
.EXAMPLE
Invoke-GitBackup -Destination 'D:\Backups' -WhatIf
.NOTES
Requires git.exe. Run at the repository root so status paths resolve
correctly. This is a working-file copy, not a Git history backup.
#>
function Invoke-GitBackup {
    [CmdletBinding(SupportsShouldProcess)]
    Param([Parameter(mandatory = $true, position = 0)][string]$Destination)

    $backupDir = (Join-Path $Destination (Get-Date -Format FileDateTime))
    if ($PSCmdlet.ShouldProcess($backupDir, 'Create backup')) {
        git.exe status --porcelain=v1 | Where-Object { $_ -notlike 'D *' } | ForEach-Object {
            $item = $_.SubString(3)
            Copy-Item -LiteralPath $item -Destination (New-Item -Type Directory -Force (Join-Path $backupDir (Split-Path -Parent $item))) -Verbose
            git.exe status | Out-File -Encoding UTF8 (Join-Path $backupDir 'gitstatus.txt')
        }
    }
}


<#
.SYNOPSIS
Combination of "git grep" and "git blame".
.DESCRIPTION
Searches tracked file contents and runs git blame for each matching line,
returning the commit and author information alongside the blamed text.
.PARAMETER Query
Pattern passed to git grep.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.Management.Automation.PSCustomObject. Hash, Author, Date, Path,
Line, and Text properties.
.EXAMPLE
Get-GitGrepBlame -Query 'Export-ModuleMember'
.NOTES
Requires git.exe. Run inside a Git working tree.
#>
function Get-GitGrepBlame {
    [CmdletBinding()]
    Param([Parameter(Mandatory)][string]$Query)

    # grep "--null" uses null separators, blame "-c" uses tab separators.
    git.exe --no-pager grep --null --line-number $Query `
    | Select-String -Pattern '(?<Filename>[^\0]+)\0(?<Line>[1-9][0-9]*)\0\s*(?<Text>.+)' `
    | Select-Object -ExpandProperty Matches `
    | ForEach-Object {
        $filename = $_.Groups['Filename'].Value
        $lineno = [int]$_.Groups['Line'].Value
        # We'll grab line text from blame instead ("$line = $_.Groups['Text'].Value")
        git.exe --no-pager blame -c --show-name --show-number -L "$lineno,$lineno" -- $filename `
        | Select-String -Pattern '(?<Hash>[0-9a-fA-F]+)\t\((?<Author>.+)\t(?<Date>.+)\t\s*(?<Line>[1-9][0-9]*)\)\s*(?<Text>.+)' `
        | Select-Object -ExpandProperty Matches `
        | ForEach-Object {
            [PSCustomObject]@{
                Hash   = $_.Groups['Hash'].Value
                Author = $_.Groups['Author'].Value
                # DateTime cast will convert to local time.
                Date   = [DateTime]$_.Groups['Date'].Value
                Path   = $filename
                Line   = [int]$_.Groups['Line'].Value
                Text   = $_.Groups['Text'].Value
            }
        }
    }
}


<#
.SYNOPSIS
"Pretty prints" and displays .gitconfig file.
.DESCRIPTION
Parses effective Git configuration into section and subsection groups and
returns INI-style text. With -Local, reads repository-local settings only.
.PARAMETER Local
Use git config --local instead of the effective combined configuration.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Configuration section headings and assignment lines.
.EXAMPLE
Get-GitConfig -Local
.NOTES
Requires git.exe. Output can include sensitive configuration values.
#>
function Get-GitConfig {
    param([switch]$Local)
    $params = @('--no-pager', 'config', '--list')
    if ($Local) {
        $params += '--local'
    }
    $config = foreach ($line in git.exe @params) {
        if ($line -match '(?<section>.+?)(\.(?<subsection>.+))?\.(?<variable>.+?)=(?<value>.+)') {
            [PSCustomObject]@{
                Section    = $matches['section']
                SubSection = $matches['subsection']
                Variable   = $matches['variable']
                Value      = $matches['value']
            }
        }
        else {
            Write-Warning "Invalid line? $line"
        }
    }

    foreach ($item in $config | Group-Object -Property Section, SubSection) {
        #  read section, subsection from first item in group
        $Section, $SubSection = $item.Group[0].Section, $item.Group[0].SubSection
        if ($SubSection) {
            '[{0} "{1}"]' -f $Section, $SubSection
        }
        else {
            '[{0}]' -f $Section
        }
        foreach ($entry in $item.Group) {
            "{0}{1} = {2}" -f "`t", $entry.Variable, $entry.Value
        }
    }
}


function Format-GitConfig {
    <#
.SYNOPSIS
    Returns sorted, grouped global Git configuration text.
.DESCRIPTION
    Reads git config --global --list, sorts and deduplicates entries, and
    renders section and subsection headings with indented assignments.
.INPUTS
    None. This function does not accept pipeline input.
.OUTPUTS
    System.String. Formatted global Git configuration lines.
.EXAMPLE
    Format-GitConfig
.NOTES
    Requires git.exe. Does not rewrite .gitconfig.
#>
    $config = foreach ($line in git.exe --no-pager config --global --list | Sort-Object -Unique) {
        if ($line -match '^\s*(?<section>\w*)\.(?<subsection>\w*)\.(?<key>\w*)\s*=\s*(?<value>.+)') {
            # e.g. difftool.winmerge.name=WinMerge
            [PSCustomObject]@{
                Section    = $matches['section']
                Subsection = $matches['subsection']
                Key        = $matches['key']
                Value      = $matches['value']
            }
        }
        elseif ($line -match '^\s*(?<section>\w*)\.(?<key>\w*)\s*=\s*(?<value>.+)') {
            # e.g. color.ui=auto
            [PSCustomObject]@{
                Section    = $matches['section']
                Subsection = $null
                Key        = $matches['key']
                Value      = $matches['value']
            }
        }
        else {
            Write-Warning "Invalid line? $line"
        }

    }

    # $config | Sort-Object Section, Variable | Format-List; return

    foreach ($line in $config | Group-Object -Property Section, SubSection | Sort-Object Name) {
        $section, $subsection = $line.Group[0].Section, $line.Group[0].Subsection
        if ($subsection) {
            "[$section ""$subsection""]"
        }
        else {
            "[$section]"
        }
        foreach ($item in $line.Group) {
            "`t{0} = {1}" -f $item.Key, $item.Value
        }
    }
}


<#
.SYNOPSIS
Downloads files and directories through the GitHub contents API.
.DESCRIPTION
Recursively queries a repository path at a branch, creates missing
subdirectories, and writes files using their repository-relative paths.
.PARAMETER Author
GitHub repository owner or organization.
.PARAMETER Repository
Repository name.
.PARAMETER Branch
Branch or ref passed to the contents API.
.PARAMETER ResourcePath
Repository-relative directory path to enumerate.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. FILE and DIR progress lines.
.EXAMPLE
Invoke-GitDownHelper -Author microsoft -Repository CsWinRT -Branch master -ResourcePath 'src/Samples'
.NOTES
Requires GitHub API access. Writes beneath the current directory and can
overwrite existing files. The top-level destination path must already exist.
#>
function Invoke-GitDownHelper {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Author,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$ResourcePath
    )

    # e.g. https://api.github.com/repos/microsoft/CsWinRT/contents/src/Samples/NetProjectionSample?ref=master
    $apiUri = 'https://api.github.com/repos/{0}/{1}/contents/{2}?ref={3}' -f $Author, $Repository, $ResourcePath, $Branch

    # Save current progress preference and hide the progress
    $prevProgressPreference = $global:ProgressPreference
    $global:ProgressPreference = 'SilentlyContinue'
    try {
        $response = Invoke-WebRequest -Uri $apiUri -ErrorAction Stop
    }
    catch {
        throw "Failed to retrieve GitHub API response for '$apiUri': $_"
    }
    finally {
        $global:ProgressPreference = $prevProgressPreference
    }

    $content = $response.Content | ConvertFrom-Json
    foreach ($obj in $content) {
        if ($obj.type -eq 'file') {
            'FILE {0}' -f $obj.path
            # Save current progress preference and hide the progress
            $prevProgressPreference = $global:ProgressPreference
            $global:ProgressPreference = 'SilentlyContinue'
            try {
                # FUTURE: check $obj.size, $obj.sha
                Invoke-WebRequest -Uri $obj.download_url -OutFile $obj.path -ErrorAction Stop
            }
            catch {
                throw "Failed to download '$($obj.path)' from '$($obj.download_url)': $_"
            }
            finally {
                $global:ProgressPreference = $prevProgressPreference
            }
        }
        elseif ($obj.type -eq 'dir') {
            # TODO: Need to recursively call the API for subdirectories,
            # e.g. https://api.github.com/repos/microsoft/CsWinRT/contents/src/Samples/NetProjectionSample/SimpleMathProjection?ref=master
            'DIR  {0}' -f $obj.path
            if (-not (Test-Path -Path $obj.path -PathType Container)) {
                mkdir $obj.path -ErrorAction Stop | Out-Null
            }

            Invoke-GitDownHelper -Author $Author -Repository $Repository -Branch $Branch -ResourcePath $obj.path
        }
        else {
            Write-Warning "Unknown type $($obj.type)"
        }
    }
}


<#
.SYNOPSIS
Download contents from a GitHub repository path.

.DESCRIPTION
Given a GitHub repository URL containing a tree/branch and resource path,
recursively retrieves files and directories via the GitHub API and
saves them into the current filesystem.

.PARAMETER RepoPath
A URI pointing to a GitHub repository tree location, e.g.
'https://github.com/owner/repo/tree/branch/path'.

.EXAMPLE
Invoke-GitDown -RepoPath 'https://github.com/microsoft/CsWinRT/tree/master/src/Samples/NetProjectionSample'
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. FILE and DIR progress lines from Invoke-GitDownHelper.
.NOTES
Uses an unauthenticated GitHub contents API request. Branch names containing
slashes are not supported by the URL parser. Existing files can be overwritten;
the destination's repository-relative parent directories must already exist.
#>
function Invoke-GitDown {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][Uri]$RepoPath)

    if ($RepoPath.Segments.Count -lt 5) {
        throw "Not a valid GitHub tree URL. Expected format: 'https://github.com/owner/repo/tree/branch/path'. Got: '$RepoPath'"
    }

    # e.g. 'https://github.com/microsoft/CsWinRT/tree/master/src/Samples/NetProjectionSample'
    $Author = $RepoPath.Segments[1] -replace '/', ''  # microsoft
    $Repository = $RepoPath.Segments[2] -replace '/', '' # CsWinRT
    $Branch = $RepoPath.Segments[4] -replace '/', '' # master
    $ResourcePath = $RepoPath.Segments[5..($RepoPath.Segments.Count)] -join '' # src/Samples/NetProjectionSample

    Invoke-GitDownHelper -Author $Author -Repository $Repository -Branch $Branch -ResourcePath $ResourcePath
}


<#
.SYNOPSIS
Opens a directory diff against the oldest current-branch reflog entry.
.DESCRIPTION
Finds the oldest available reflog entry for the current branch and passes
its commit to git difftool --dir-diff. This is not a merge-base calculation.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Any standard output produced by Git or the configured diff tool.
.EXAMPLE
Invoke-GitBranchDiff
.NOTES
Requires git.exe, branch reflog history, and a configured directory diff tool.
#>
function Invoke-GitBranchDiff {
    git.exe difftool --dir-diff ((git reflog (git branch --show-current) | Select-Object -Last 1) -split ' ')[0]
}

<#
.SYNOPSIS
Use AI to create a descriptive git commit message and commit the changes.
.DESCRIPTION
Checks that the current directory is in a repository with staged changes,
invokes Copilot CLI to create a commit, then displays the latest commit.
.INPUTS
None. This function does not accept pipeline input.
.OUTPUTS
System.String. Copilot and Git output, including the latest commit.
.EXAMPLE
Invoke-GitCommitAI
.NOTES
Requires git.exe and copilot.exe with authentication configured. Invokes
Copilot with --allow-all and asks it to commit without a co-author. This
can create a commit; it does not stage files or push.
#>
function Invoke-GitCommitAI {
    git.exe branch --show-current 2> $null | Out-Null
    IF ($LASTEXITCODE -ne 0) {
        Write-Host -ForegroundColor Red 'Not in a git repository.'
        return
    }

    git.exe diff --staged --quiet 2> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host -ForegroundColor Yellow 'No staged changes to commit.'
        git.exe status --short
        return
    }

    copilot.exe --allow-all --prompt 'Create a descriptive git commit message and call git commit. Do not add a co-author to the commit.'

    git.exe log -1
}

Export-ModuleMember -Function `
    Format-GitConfig, `
    Get-GitConfig, `
    Get-GitGrepBlame, `
    Invoke-GitBackup, `
    Invoke-GitBranchDiff, `
    Invoke-GitCommitAI, `
    Invoke-GitDown, `
    Invoke-GitDownHelper, `
    Invoke-GitRepo
