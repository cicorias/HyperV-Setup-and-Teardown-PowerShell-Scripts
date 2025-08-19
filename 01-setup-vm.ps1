<#
 Script: 01-setup-vm.ps1
 Purpose: Creates a Hyper-V VM and its VHD in a local ./archive folder located beside this script.
 Note: Run in an elevated (Administrator) PowerShell session with Hyper-V module available.
#>

# Optional Start switch
param(
	[switch]$Start
)

# Base config (VM name will get a random 3-char suffix each run)
$memory = 2GB
$vhdSize = 20GB
$switchName = 'PXENetwork'
$secureBootEnabled = $false  # Set to $true to keep Secure Boot enabled
$secureBootState = if ($secureBootEnabled) { 'On' } else { 'Off' }

function New-RandomSuffix {
	param([int]$Length = 3)
	$chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
	-join (1..$Length | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })
}

$baseName = 'PXE-CLIENT'
for ($i=0; $i -lt 10; $i++) {
	$suffix = New-RandomSuffix
	$vmName = "$baseName-$suffix"
	if (-not (Get-VM -Name $vmName -ErrorAction SilentlyContinue)) { break }
	if ($i -eq 9) { throw "Could not generate unique VM name with suffix after 10 attempts." }
}

# Unique VHD per VM (prevents collisions when multiple created)
$vhdFileName = "$vmName.vhdx"

# Resolve script root (fallback to current location if not available)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }

# Ensure archive directory exists relative to script location
$archiveDir = Join-Path -Path $scriptRoot -ChildPath 'archive'
if (-not (Test-Path -LiteralPath $archiveDir)) {
	New-Item -ItemType Directory -Path $archiveDir | Out-Null
}

$vhdPath = Join-Path -Path $archiveDir -ChildPath $vhdFileName

Write-Host "Creating / updating VM '$vmName' with VHD at: $vhdPath" -ForegroundColor Cyan

# Create VM if it doesn't already exist
New-VM -Name $vmName -MemoryStartupBytes $memory -Generation 2 | Out-Null
Write-Host "VM '$vmName' (Gen2) created." -ForegroundColor Green

# Disable automatic checkpoints (idempotent)
try { Set-VM -Name $vmName -AutomaticCheckpointsEnabled $false -ErrorAction Stop; Write-Host "Automatic checkpoints disabled." -ForegroundColor Green } catch { Write-Host "Could not disable automatic checkpoints: $($_.Exception.Message)" -ForegroundColor Yellow }

# Configure processor count
Set-VMProcessor -VMName $vmName -Count 2

# Create VHD if it does not exist
if (-not (Test-Path -LiteralPath $vhdPath)) {
	New-VHD -Path $vhdPath -SizeBytes $vhdSize -Dynamic | Out-Null
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
	$vmNic = Get-VMNetworkAdapter -VMName $vmName -ErrorAction Stop
	if ($vmNic.SwitchName -ne $switchName) {
		# Ensure switch exists
		if (-not (Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)) {
			Write-Host "Virtual switch '$switchName' not found. Create it first: New-VMSwitch -Name $switchName -SwitchType Internal/External" -ForegroundColor Red
		} else {
			Connect-VMNetworkAdapter -VMName $vmName -SwitchName $switchName
			Write-Host "Network adapter connected to switch '$switchName'." -ForegroundColor Green
		}
	} else {
		Write-Host "Network adapter already connected to switch '$switchName'." -ForegroundColor Yellow
	}
} catch {
	Write-Host "Failed to evaluate or connect network adapter: $($_.Exception.Message)" -ForegroundColor Red
}

# Firmware / Boot order (Generation 2 only)
try {
	$vmObj = Get-VM -Name $vmName -ErrorAction Stop
	if ($vmObj.Generation -eq 2) {
		$nicForBoot = Get-VMNetworkAdapter -VMName $vmName | Select-Object -First 1
		$diskForBoot = Get-VMHardDiskDrive -VMName $vmName | Where-Object { $_.Path -ieq $vhdPath } | Select-Object -First 1
		if ($nicForBoot -and $diskForBoot) {
			Set-VMFirmware -VMName $vmName -EnableSecureBoot $secureBootState -BootOrder $nicForBoot, $diskForBoot
			Write-Host "Firmware configured: SecureBoot=$secureBootState; BootOrder=NIC then Disk" -ForegroundColor Green
		} else {
			Write-Host "Skipping firmware boot order (NIC or Disk not resolved)." -ForegroundColor Yellow
		}
	}
} catch {
	Write-Host "Firmware configuration skipped/failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Setup complete." -ForegroundColor Cyan

if ($Start) {
	try {
		Start-VM -Name $vmName -ErrorAction Stop
		Write-Host "VM started: $vmName" -ForegroundColor Green
	} catch {
		Write-Host "Failed to start VM: $($_.Exception.Message)" -ForegroundColor Red
	}
} else {
	Write-Host "(Not started) Use: Start-VM -Name $vmName" -ForegroundColor DarkCyan
}

# Output object for scripting convenience
[pscustomobject]@{ VMName = $vmName; VhdPath = $vhdPath }

