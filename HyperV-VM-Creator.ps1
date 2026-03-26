<#
.SYNOPSIS
Create a Hyper-V VM from an ISO.

.DESCRIPTION
Create a Hyper-V VM from an ISO.

.PARAMETER VMName
VM Name

.PARAMETER Path
Where to create the new Disk Image?
Default: '\Hyper-V\Virtual Hard Disks'

.PARAMETER IsoPath
Path to ISO file

.PARAMETER DiskSize
Size of the new Disk in GB?
Default: 80

.PARAMETER StartMem
Memory Size in GB?
Default: 4

.PARAMETER ProcessorCount
Number of processors
Default: 6

.PARAMETER VSwitch
Hyper-V Switch to use?
Default: 'Default Switch'

.PARAMETER Generation
Hyper-V VM Generation?
Default: 2

.PARAMETER MaxMem
Max RAM Size in MegaByte?
Default: 12288

.PARAMETER VideoResolution
Video resolution in WxH format
Default: '1600x900'

.EXAMPLE
PS C:\> .\HyperV-VM-Creator.ps1 -VMName 'Windows 11' -IsoPath 'D:\Hyper-V\windows 11.iso'

.EXAMPLE
PS C:\> .\HyperV-VM-Creator.ps1 -VMName 'Ubuntu 22' -IsoPath .\ubuntu-22.04.5-desktop-amd64.iso -Generation 1 -DiskSize 32
#>
param
(
    [Parameter(Mandatory, Position = 1, HelpMessage = 'VM Name')]
    [ValidateNotNullOrEmpty()]
    [string]$VMName,
    [Parameter(Mandatory, Position = 2, HelpMessage = 'ISO Path')]
    [ValidateNotNullOrEmpty()]
    [string]$IsoPath,
    [ValidateNotNullOrEmpty()]
    [string]$Path = '\Hyper-V\Virtual Hard Disks',
    [int]$DiskSize = 80,
    [int]$StartMem = 4,
    [int]$ProcessorCount = 6,
    [String]$VSwitch = 'Default Switch',
    [int]$Generation = 2,
    [int]$MaxMem = 12288,
    [string]$VideoResolution = '1600x900'

)

if ((Get-VM -VMName $VMName -ErrorAction SilentlyContinue).Count -ne 0) {
    Write-Warning "VM '$VMName' already exists."
    return
}

# Where to create the Disk
$Target = Join-Path $Path ($VMName + '.vhdx')

if ((Test-Path -LiteralPath $Target -PathType Leaf)) {
    Write-Warning "Target '$Target' already exists."
    return
}

if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
    Write-Warning "ISoPath '$IsoPath' not found."
    return
}

if ($IsoPath -like '*ubuntu*' -and $Generation -ne 1) {
    Write-Warning 'Ubuntu ISO should use Generation 1 VM'
    Read-Host 'Press any key to continue, or Ctrl-C to stop'
}

# Create the Disk
$DiskImageSize = ($DiskSize * 1GB)
New-VHD -Path $Target -Fixed -SizeBytes $DiskImageSize -ErrorAction Stop | Out-Null

# Create the VM, without a Disk. We attach the new disk later
$VMStartupMemeory = ($StartMem * 1GB)
New-VM -Name $VMName `
    -MemoryStartupBytes $VMStartupMemeory `
    -NoVHD `
    -SwitchName $VSwitch `
    -Generation $Generation | Out-Null

# Set the Memory settings
$VMMaximumBytes = ($MaxMem * 1MB)
Set-VMMemory -VMName $VMName `
    -DynamicMemoryEnabled $true `
    -MaximumBytes $VMMaximumBytes

# Set number of processors; disable automatic checkpoints
Set-VM -Name $VMName `
    -ProcessorCount $ProcessorCount `
    -AutomaticCheckpointsEnabled $False

# Attach the new Disk
Add-VMHardDiskDrive -VMName $VMName `
    -Path $Target
Add-VMDvdDrive -VMName $VMName `
    -Path $IsoPath

# Remove PXE boot
if ($Generation -eq 2) {
    $oldBootOrder = Get-VMFirmware -VMName $VMName `
    | Select-Object -ExpandProperty BootOrder
    Set-VMFirmware -VMName $VMName `
        -BootOrder ($oldBootOrder | Where-Object { $_.BootType -ne 'Network' })
}

# Set video resolution
Set-VMVideo -VMName $VMName `
    -ResolutionType Single `
    -HorizontalResolution ([int](($VideoResolution -split 'x')[0])) `
    -VerticalResolution ([int](($VideoResolution -split 'x')[1]))

# Set TPM (required to boot Windows 11)
if ($Generation -eq 2) {
    Set-VMKeyProtector -VMName $VMName `
        -NewLocalKeyProtector
    Enable-VMTPM -VMName $VMName
}

# Start the VM
if ($IsoPath -like '*Windows*11*') {
    'Note:  Guest OS should be of at least the Pro edition since Home editions of Windows'
    'do not support Enhanced Session Mode.'
    'Choose "Windows 11 Pro" or higher at "Select Image" page.'
}

Checkpoint-VM -VMName $VMName `
    -SnapshotName 'Clean'
vmconnect.exe localhost $VMName
Start-VM -VMName $VMName
