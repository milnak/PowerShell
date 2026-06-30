<#
.SYNOPSIS
Check for and install winget package updates.
#>
function Invoke-WingetUpgrade {
    Get-Command -Name 'sudo.exe' -CommandType Application -ErrorAction Stop | Out-Null
    Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction Stop | Out-Null

    $params = `
        '--all', `
        '--accept-package-agreements', `
        '--accept-source-agreements', `
        '--include-unknown', `
        '--interactive'

    sudo.exe --inline winget.exe upgrade @params
}

Export-ModuleMember -Function Invoke-WingetUpgrade

