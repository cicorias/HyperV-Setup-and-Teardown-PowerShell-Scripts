<#
 Script: 01-setup-vm.ps1
 Purpose: Unified Hyper-V PXE VM setup script supporting Gen1 (legacy BIOS) and Gen2 (UEFI) with dynamic naming and optional auto-start.
 Naming: PXE-CLIENT[-UEFI]-<RND3> (disk name matches VM name: <VMName>.vhdx)
 Default: UEFI (Generation 2) with Secure Boot Off and NIC-first boot order.
 Run elevated (Administrator) with Hyper-V PowerShell module.
 Examples:
	 .\01-setup-vm.ps1                       # Creates UEFI PXE client (default)
	 .\01-setup-vm.ps1 -UEFI:$false           # Creates Gen1 (legacy) PXE client
	 .\01-setup-vm.ps1 -MemoryGB 4 -VhdSizeGB 40 -Start
	 .\01-setup-vm.ps1 -SecureBoot On -Start  # Start with Secure Boot enabled (UEFI only)
#>

[CmdletBinding()]param(
		[switch]$UEFI = $true,
		[int]$CPUCount = 2,
		[int]$MemoryGB = 2,
		[int]$VhdSizeGB = 200,
		[string]$SwitchName = 'PXENetwork',
		[ValidateSet('On','Off')][string]$SecureBoot = 'Off',
		[switch]$Start,
		[switch]$NestedVirtualization = $true
)

$ErrorActionPreference = 'Stop'
try { Import-Module Hyper-V -ErrorAction SilentlyContinue } catch {}
$ErrorActionPreference = 'Continue'

# Compute generation & secure boot state
$generation = if ($UEFI) { 2 } else { 1 }
$secureBootState = if ($UEFI) { $SecureBoot } else { 'Off' }

function New-RandomSuffix {
	param([int]$Length = 3)
	$chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
	-join (1..$Length | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })
}

$baseName = if ($UEFI) { 'PXE-CLIENT-UEFI' } else { 'PXE-CLIENT' }
for ($i=0; $i -lt 10; $i++) {
	$suffix = New-RandomSuffix
	$vmName = "$baseName-$suffix"
	if (-not (Get-VM -Name $vmName -ErrorAction SilentlyContinue)) { break }
	if ($i -eq 9) { throw "Could not generate unique VM name with suffix after 10 attempts." }
}

# Disk name matches VM name
$vhdFileName = "$vmName.vhdx"

# Resolve script root (fallback to current location if not available)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }

# Ensure archive directory exists relative to script location
$archiveDir = Join-Path -Path $scriptRoot -ChildPath 'archive'
if (-not (Test-Path -LiteralPath $archiveDir)) {
	New-Item -ItemType Directory -Path $archiveDir | Out-Null
}

$vhdPath = Join-Path -Path $archiveDir -ChildPath $vhdFileName

Write-Host "Creating PXE VM '$vmName' (Gen$generation, UEFI=$UEFI) with VHD: $vhdPath" -ForegroundColor Cyan

New-VM -Name $vmName -MemoryStartupBytes ($MemoryGB * 1GB) -Generation $generation -SwitchName $SwitchName | Out-Null
Write-Host "VM '$vmName' created." -ForegroundColor Green

# Disable automatic checkpoints (idempotent)
try { Set-VM -Name $vmName -AutomaticCheckpointsEnabled $false -ErrorAction Stop; Write-Host "Automatic checkpoints disabled." -ForegroundColor Green } catch { Write-Host "Could not disable automatic checkpoints: $($_.Exception.Message)" -ForegroundColor Yellow }


# set nested virtualization if supported
if ($NestedVirtualization -and $CPUCount -ge 2 -and $generation -eq 2) {
	try {
		Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true -ErrorAction Stop
		Write-Host "Nested virtualization enabled." -ForegroundColor Green
	} catch { Write-Host "Could not enable nested virtualization: $($_.Exception.Message)" -ForegroundColor Yellow }
} else {
	if ($generation -eq 1) { Write-Host "Nested virtualization not supported on Gen1 VMs." -ForegroundColor DarkCyan }
	if ($CPUCount -lt 2) { Write-Host "Nested virtualization requires at least 2 vCPUs." -ForegroundColor DarkCyan }
}

# Configure processor count
Set-VMProcessor -VMName $vmName -Count $CPUCount

# Create VHD if it does not exist
if (-not (Test-Path -LiteralPath $vhdPath)) {
	New-VHD -Path $vhdPath -SizeBytes ($VhdSizeGB * 1GB) -Dynamic | Out-Null
	Write-Host "VHD created: $vhdPath" -ForegroundColor Green
} else {
	Write-Host "VHD already exists: $vhdPath" -ForegroundColor Yellow
}

# Attach VHD to VM if not already attached
$attached = (Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $vhdPath })
if (-not $attached) {
	# Remove any existing disk with same controller/location if needed (optional logic could be added)
	Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath
	Write-Host "VHD attached to VM." -ForegroundColor Green
} else {
	Write-Host "VHD already attached to VM." -ForegroundColor Yellow
}

# Connect / ensure network adapter is attached to desired switch
try {
	$vmNic = Get-VMNetworkAdapter -VMName $vmName -ErrorAction Stop | Select-Object -First 1
	if ($vmNic.SwitchName -ne $SwitchName) {
		if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
			Write-Host "Virtual switch '$SwitchName' not found. Create it first: New-VMSwitch -Name $SwitchName -SwitchType Internal/External" -ForegroundColor Red
		} else {
			Connect-VMNetworkAdapter -VMName $vmName -SwitchName $SwitchName
			Write-Host "Network adapter connected to switch '$SwitchName'." -ForegroundColor Green
		}
	} else { Write-Host "Network adapter already on switch '$SwitchName'." -ForegroundColor Yellow }
} catch { Write-Host "Failed to evaluate or connect network adapter: $($_.Exception.Message)" -ForegroundColor Red }

if ($UEFI) {
	# Firmware / Boot order (Generation 2 only)
	try {
		$vmObj = Get-VM -Name $vmName -ErrorAction Stop
		$nicForBoot = Get-VMNetworkAdapter -VMName $vmName | Select-Object -First 1
		$diskForBoot = Get-VMHardDiskDrive -VMName $vmName | Where-Object { $_.Path -ieq $vhdPath } | Select-Object -First 1
		if ($nicForBoot -and $diskForBoot) {
			Set-VMFirmware -VMName $vmName -EnableSecureBoot $secureBootState -BootOrder $diskForBoot, $nicForBoot
			Write-Host "Firmware configured: SecureBoot=$secureBootState; BootOrder=DISK then NIC" -ForegroundColor Green
		} else { Write-Host "Skipping firmware config (NIC or Disk unresolved)." -ForegroundColor Yellow }
	} catch { Write-Host "Firmware configuration skipped/failed: $($_.Exception.Message)" -ForegroundColor Red }
} else {
	Write-Host "Legacy Gen1 VM created (no UEFI firmware settings applied)." -ForegroundColor Yellow
}

Write-Host "Setup complete." -ForegroundColor Cyan

if ($Start) {
	try { Start-VM -Name $vmName -ErrorAction Stop; Write-Host "VM started: $vmName" -ForegroundColor Green } catch { Write-Host "Failed to start VM: $($_.Exception.Message)" -ForegroundColor Red }
} else { Write-Host "(Not started) Use: Start-VM -Name $vmName" -ForegroundColor DarkCyan }

[pscustomobject]@{ VMName = $vmName; VhdPath = $vhdPath; UEFI = $UEFI; Generation = $generation }

