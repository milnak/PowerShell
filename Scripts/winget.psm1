function Invoke-Winget {
    # Missing functions:
    #   configure  Configures the system into a desired state
    #   dscv3      DSC v3 resource commands
    #   export     Exports a list of the installed packages
    #   features   Shows the status of experimental features
    #   hash       Helper to hash installer files
    #   import     Installs all the packages in a file
    #   mcp        MCP information
    #   pin        Manage package pins
    #   repair     Repairs the selected package
    #   settings   Open settings or set administrator settings
    #   validate   Validates a manifest file
    param(
        # Commands
        # --------

        # Downloads the installer from a given package
        [Parameter(Mandatory, ParameterSetName = 'download')]
        [switch]$Download,

        # Installs the given package
        [Parameter(Mandatory, ParameterSetName = 'install')]
        [switch]$Install,

        # Uninstalls the given package
        [Parameter(Mandatory, ParameterSetName = 'uninstall')]
        [switch]$Uninstall,

        # Find and show basic info of packages
        [Parameter(Mandatory, ParameterSetName = 'search')]
        [switch]$Search,

        # Display installed packages
        [Parameter(Mandatory, ParameterSetName = 'list')]
        [switch]$List,

        # Shows and performs available upgrades
        [Parameter(Mandatory, ParameterSetName = 'upgrade')]
        [switch]$Upgrade,

        # Parameters for commands
        # -----------------------

        [Parameter(Mandatory, ParameterSetName = 'download')]
        [Parameter(Mandatory, ParameterSetName = 'install')]
        [Parameter(Mandatory, ParameterSetName = 'uninstall')]
        [Parameter(Mandatory, ParameterSetName = 'search')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'download')]
        [string]$DestinationPath
    )

    # https://www.powershellgallery.com/packages/Microsoft.WinGet.Client
    # https://powershellisfun.com/2024/11/28/using-the-powershell-winget-module/
    # Get-Command -Module Microsoft.WinGet.Client
    $wingetModuleName = 'Microsoft.WinGet.Client'

    if (-not (Get-Module -ListAvailable -Name $wingetModuleName)) {
        Write-Host -ForegroundColor Yellow "$wingetModuleName module is not installed. Installing."
        Install-Module -Name 'Microsoft.WinGet.Client' -Force -Repository PSGallery
        Assert-WinGetPackageManager
        Write-Host "WinGet $(Get-WinGetVersion) is installed."
    }

    Import-Module -Name Microsoft.WinGet.Client

    if ($Install) {
        # e.g. Invoke-Winget -Install -id Microsoft.Edit
        Write-Host "Installing package '$Id'"
        $result = Install-WinGetPackage -Id $Id -Source 'winget'
        if ($result.Status -ne 'Ok') {
            Write-Host -ForegroundColor Red "Installation failed: $($result.Status)"
            Write-Host ("Failed: $($result.ExtendedErrorCode) (Code: {0:X})" -f $result.InstallerErrorCode)
        }
        else {
            Write-Host -ForegroundColor Green "Installation completed successfully."
            if ($result.RebootRequired) {
                Write-Host -ForegroundColor Yellow "A reboot is required to complete the installation."
            }
        }
    }

    #   show       Shows information about a package

    #   source     Manage sources of packages

    elseif ($Search) {
        # e.g. Invoke-Winget -Search -id Microsoft.Edit
        Write-Host "Searching for package '$Id'"
        $result = Find-WinGetPackage -Id $Id -Source 'winget'
        if ($result) {
            $result
        }
        else {
            Write-Host -ForegroundColor Red "No packages matched the given input criteria."
        }
    }

    elseif ($List) {
        # e.g. Invoke-Winget -List | Sort-Object Name | Format-Table -Property Name,Id,InstalledVersion -AutoSize
        $result = Get-WinGetPackage
        if ($result) {
            $result | Where-Object Source -eq 'winget'
        }
        else {
            Write-Host -ForegroundColor Yellow "No installed packages found."
        }
    }

    elseif ($Uninstall) {
        # e.g. Invoke-Winget -Uninstall -id Microsoft.Edit
        Write-Host "Uninstalling package '$Id'"
        $result = Uninstall-WinGetPackage -Id $Id
        # "No packages matched the given input criteria." doesn't return a result object, so we need to check for that
        if ($result) {
            if ($result.Status -eq 'InstallError') {
                Write-Host -ForegroundColor Red "Uninstallation failed: $($result.Status)"
                Write-Host ("Failed: $($result.ExtendedErrorCode) (Code: {0:X})" -f $result.InstallerErrorCode)
            }
            else {
                Write-Host -ForegroundColor Green "Uninstallation completed successfully."
                if ($result.RebootRequired) {
                    Write-Host -ForegroundColor Yellow "A reboot is required to complete the installation."
                }
            }
        }
    }

    elseif ($Download) {
        # e.g. Invoke-Winget -Download -id Microsoft.Edit -DestinationPath d:\temp\a
        Write-Host "Downloading package '$Id' to '$DestinationPath'"
        $result = Export-WinGetPackage -Id $Id -DownloadDirectory $DestinationPath
        if ($result) {
            if ($result.Status -ne 'Ok') {
                Write-Host -ForegroundColor Red "Export failed: $($result.Status)"
                Write-Host "Error: $($result.ExtendedErrorCode)"
            }
            else {
                Write-Host -ForegroundColor Green "Export completed successfully."
            }
        }
    }

    elseif ($Upgrade) {
        # e.g. Update-WinGetPackage
        $packages = Get-WinGetPackage | Where-Object Source -eq 'winget' | Sort-Object Name
        Write-Host "Checking $($packages.Count) packages for updates...`n"

        foreach ($package in $packages) {
            Write-Host -NoNewline "Package '$($package.Name)': "
            $result = Update-WinGetPackage -Id $package.Id -Source 'winget'
            if ($result.Status -eq 'Ok') {
                if ($result.RebootRequired) {
                    Write-Host -ForegroundColor Yellow 'Reboot required'
                }
                else {
                    Write-Host -ForegroundColor Green 'Update completed'
                }
            }
            elseif ($result.status -eq 'NoApplicableUpgrade') {
                Write-Host 'Up-to-date'
            }
            else {
                Write-Host -ForegroundColor Red ("Failed: $($result.Status) (Code: {0:X})" -f $result.InstallerErrorCode)
            }

        }
    }
}

Export-ModuleMember -Function Invoke-Winget
