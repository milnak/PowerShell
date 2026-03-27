# Copilot Instructions

## Repository Purpose

Personal PowerShell environment for Windows. Root-level `.ps1` files are domain-specific utility modules dot-sourced by the profile at startup. The repo is not a module — it's a collection of scripts and functions loaded into the interactive session.

## Profile Architecture

Three profile files with distinct roles:

- **`Microsoft.PowerShell_profile.ps1`** — Primary profile (ConsoleHost only; exits early in VSCode). Dot-sources all root-level modules, initializes PSReadline/PSFzf/zoxide, runs throttled package updates.
- **`prompt.ps1`** — Custom prompt: admin detection, truncated path (≤60 chars), git branch + dirty indicator.
- **`profile.ps1`** — Legacy Windows PowerShell 5 placeholder; prints a message, nothing else.

Module loading in `Microsoft.PowerShell_profile.ps1`:
```powershell
@('audio', 'download', 'filesystem', 'git', 'messages', ...) | ForEach-Object {
    . "$PSScriptRoot\$_.ps1"
}
```

## Root Module Files

| File | Domain |
|------|--------|
| `audio.ps1` | Audio normalization, MP3 conversion — wraps `ffmpeg`/`ffprobe` |
| `download.ps1` | Downloads via `yt-dlp`, `aria2c`, `wget`; PowerShell auto-updater |
| `filesystem.ps1` | File hashing, recycle bin delete, disk usage, ownership |
| `git.ps1` | Git repo browser, grep+blame, GitHub API downloader |
| `mame.ps1` | MAME ROM parsing, MAME auto-updater |
| `messages.ps1` | Unicode box drawing, figlet ASCII art, bold Unicode text |
| `musescore.ps1` | Export PDFs/audio from `.mscz` files via MuseScore 4 |
| `pdf.ps1` | Split, decrypt, merge PDFs — wraps `qpdf` |
| `prompt.ps1` | Custom prompt function |
| `sibelius.ps1` | Detect Sibelius file version from binary header |
| `transcribe.ps1` | Parse/write `.xsc` files (Transcribe app format) |
| `update.ps1` | WinGet and Scoop updates with 7-day throttle |
| `vscode.ps1` | `code` wrapper with wildcard and pipeline support |

## Coding Conventions

### Advanced Functions
All functions use `[CmdletBinding()]`. Support `-Confirm`/`-WhatIf` via `ShouldProcess` wherever the function modifies or deletes anything.

```powershell
function Verb-Noun {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'Path')]
        [string]$File
    )
    process {
        if ($PSCmdlet.ShouldProcess($File, 'action description')) { ... }
    }
}
```

### Pipeline Support
Functions that operate on files always accept pipeline input via `ValueFromPipeline`/`ValueFromPipelineByPropertyName` with an `[Alias('FullName')]` so they compose with `Get-ChildItem`.

### External Tool Invocation
- Use `System.Diagnostics.Process` directly when stderr capture is needed (e.g., ffmpeg output parsing).
- Use argument arrays, not string concatenation, to handle paths with spaces.
- Always check `$LASTEXITCODE` or `$proc.ExitCode` after external tool calls.
- Validate tool availability with `Get-Command -Name $tool -ErrorAction Stop` before use.

### Error Handling
- `Write-Warning` for non-fatal issues; `throw` for fatal ones.
- `Write-Verbose` for diagnostic output users can opt into.
- `Test-Path -LiteralPath $path -PathType Leaf` before file operations.

### Parsing Patterns
- Named capture groups in regex: `(?<name>pattern)` with `-match` or `Select-String`.
- Ordered hashtables (`[ordered]@{}`) for config-like structured data.
- Return `[PSCustomObject]` for structured output that works with `Format-Table`/`Where-Object`.

### Throttling Pattern
Time-gated operations store a timestamp file in `~/.toolname-lastcheck`. Check age with `(Get-Date) - (Get-Item $stampFile).LastWriteTime` before running.

### ANSI Colors
Use escape sequences directly: `` "`e[0;35m" `` (magenta), `` "`e[0m" `` (reset). Do not use `[System.Console]::ForegroundColor` in these scripts.

## Linting and Formatting

PSScriptAnalyzer and PowerShell-Beautifier are installed in `Modules/`:

```powershell
# Lint a file
Invoke-ScriptAnalyzer -Path .\audio.ps1

# Format a file
Edit-DTWBeautifyScript -Source .\audio.ps1
```

Pester tests can be run with:
```powershell
Invoke-Pester
```
No test files currently exist in this repo.

## External Dependencies

These tools must be in `PATH` for the relevant functions to work:

| Tool | Used by |
|------|---------|
| `ffmpeg`, `ffprobe` | `audio.ps1` |
| `qpdf` | `pdf.ps1` |
| `yt-dlp` | `download.ps1` |
| `aria2c` | `download.ps1` |
| `wget` | `download.ps1` |
| `7z` | `mame.ps1` |
| `du` (Sysinternals) | `filesystem.ps1` |
| `figlet` | `messages.ps1` |
| `fzf` | PSFzf integration in profile |
| `zoxide` | Directory navigation in profile |
| MuseScore 4 | `musescore.ps1` |
