<#
.SYNOPSIS
Open git repo homepage.
.DESCRIPTION
Run from anywhere inside of a local git project.
#>
function Invoke-GitRepo {
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
Backup modified git files
#>
function gitbackup {
    Param([Parameter(mandatory = $true, position = 0)][string]$Destination)

    $backupDir = (Join-Path $Destination (Get-Date -Format FileDateTime))
    git.exe status --porcelain=v1 | Where-Object { $_ -notlike 'D *' } | ForEach-Object {
        $item = $_.SubString(3)
        Copy-Item -LiteralPath $item -Destination (New-Item -Type Directory -Force (Join-Path $backupDir (Split-Path -Parent $item))) -Verbose
        git.exe status | Out-File -Encoding UTF8 (Join-Path $backupDir 'gitstatus.txt')
    }
}


<#
.SYNOPSIS
Combination of "git grep" and "git blame".
#>
function Get-GitGrepBlame {
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
.DESCRIPTION
    Formats and outputs the Git configuration in a structured manner.
.EXAMPLE
    .\Format-GitConfig.ps1
    Outputs the Git configuration grouped by sections and sorted.
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


function Invoke-GitDownHelper {
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
        $response = Invoke-WebRequest -Uri $apiUri
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
#>
function Invoke-GitDown {
    param ([Parameter(Mandatory)][Uri]$RepoPath)

    # e.g. 'https://github.com/microsoft/CsWinRT/tree/master/src/Samples/NetProjectionSample'
    $Author = $RepoPath.Segments[1] -replace '/', ''  # microsoft
    $Repository = $RepoPath.Segments[2] -replace '/', '' # CsWinRT
    $Branch = $RepoPath.Segments[4] -replace '/', '' # master
    $ResourcePath = $RepoPath.Segments[5..($RepoPath.Segments.Count)] -join '' # src/Samples/NetProjectionSample

    Invoke-GitDownHelper -Author $Author -Repository $Repository -Branch $Branch -ResourcePath $ResourcePath
}
