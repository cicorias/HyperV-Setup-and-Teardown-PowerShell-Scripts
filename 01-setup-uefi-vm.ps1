<#
 Script: 01-setup-uefi-vm.ps1
 Purpose: Create / update a Generation 2 (UEFI) Hyper-V VM configured for PXE (network) boot first, then local disk.
 Notes:
   - Run elevated (Administrator) on a host with Hyper-V role.
   - Ensures a VHD exists in ./archive relative to this script.
   - Order: NIC first, then Disk. Secure Boot default: Off (set -SecureBoot On to enable).
 Usage Examples:
   .\01-setup-uefi-vm.ps1                      # uses defaults
   .\01-setup-uefi-vm.ps1 -VMName PXE-02 -MemoryGB 4 -VhdSizeGB 40 -SwitchName PXENetwork -SecureBoot On
#>

[CmdletBinding()]param(
    [string]$VMName = 'PXE-UEFI-Client',
    [int]$CPUCount = 2,
    [int]$MemoryGB = 2,
    [int]$VhdSizeGB = 20,
    [string]$VhdFileName = 'disk.vhdx',
    [string]$SwitchName = 'PXENetwork',
    [ValidateSet('On','Off')][string]$SecureBoot = 'Off'
)

$ErrorActionPreference = 'Stop'
try { Import-Module Hyper-V -ErrorAction SilentlyContinue } catch {}
$ErrorActionPreference = 'Continue'

# Resolve script root
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }
$ArchiveDir = Join-Path $ScriptRoot 'archive'
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }
$VhdPath = Join-Path $ArchiveDir $VhdFileName

Write-Host "[INFO] Preparing UEFI PXE VM '$VMName' (Gen2)" -ForegroundColor Cyan

# Create VM if needed
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    New-VM -Name $VMName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -SwitchName $SwitchName | Out-Null
    $vm = Get-VM -Name $VMName
    Write-Host "[OK] VM created." -ForegroundColor Green
} else {
    Write-Host "[SKIP] VM already exists." -ForegroundColor Yellow
    if ($vm.Generation -ne 2) {
        Write-Host "[WARN] VM is Generation $($vm.Generation); firmware settings will not apply." -ForegroundColor Red
    }
}

# Disable automatic checkpoints
try {
    Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -ErrorAction Stop
    Write-Host "[OK] Automatic checkpoints disabled." -ForegroundColor Green
} catch {
    Write-Host "[WARN] Unable to disable automatic checkpoints: $($_.Exception.Message)" -ForegroundColor Yellow
}

# CPU
Set-VMProcessor -VMName $VMName -Count $CPUCount

# Ensure switch connection (if VM existed without proper connection)
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    Write-Host "[WARN] Virtual switch '$SwitchName' not found. Create it first with New-VMSwitch." -ForegroundColor Red
} else {
    $nic = Get-VMNetworkAdapter -VMName $VMName | Select-Object -First 1
    if ($nic.SwitchName -ne $SwitchName) {
        Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName
        Write-Host "[OK] Connected NIC to switch '$SwitchName'." -ForegroundColor Green
    } else {
        Write-Host "[SKIP] NIC already on switch '$SwitchName'." -ForegroundColor Yellow
    }
}

# VHD creation / attach
if (-not (Test-Path $VhdPath)) {
    New-VHD -Path $VhdPath -SizeBytes ($VhdSizeGB * 1GB) -Dynamic | Out-Null
    Write-Host "[OK] VHD created: $VhdPath" -ForegroundColor Green
} else {
    Write-Host "[SKIP] VHD exists: $VhdPath" -ForegroundColor Yellow
}

if (-not (Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue | Where-Object Path -ieq $VhdPath)) {
    Add-VMHardDiskDrive -VMName $VMName -Path $VhdPath
    Write-Host "[OK] VHD attached." -ForegroundColor Green
} else {
    Write-Host "[SKIP] VHD already attached." -ForegroundColor Yellow
}

# Firmware: Secure Boot + Boot Order (NIC then Disk) for PXE
try {
    $vmObj = Get-VM -Name $VMName -ErrorAction Stop
    if ($vmObj.Generation -eq 2) {
        $nicForBoot  = Get-VMNetworkAdapter -VMName $VMName | Select-Object -First 1
        $diskForBoot = Get-VMHardDiskDrive -VMName $VMName | Where-Object Path -ieq $VhdPath | Select-Object -First 1
        if ($nicForBoot -and $diskForBoot) {
            Set-VMFirmware -VMName $VMName -EnableSecureBoot $SecureBoot -BootOrder $nicForBoot, $diskForBoot
            Write-Host "[OK] Firmware set: SecureBoot=$SecureBoot BootOrder=NIC->Disk" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Could not resolve NIC or Disk for boot order." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "[FAIL] Firmware configuration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "[DONE] UEFI PXE VM setup complete." -ForegroundColor Cyan

# Suggest start command
Write-Host "Start with: Start-VM -Name '$VMName'" -ForegroundColor DarkCyan
