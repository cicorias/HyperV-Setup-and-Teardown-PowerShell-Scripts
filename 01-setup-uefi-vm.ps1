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
    [int]$CPUCount = 2,
    [int]$MemoryGB = 2,
    [int]$VhdSizeGB = 20,
    [string]$SwitchName = 'PXENetwork',
    [ValidateSet('On','Off')][string]$SecureBoot = 'Off',
    [switch]$Start
)

$ErrorActionPreference = 'Stop'
try { Import-Module Hyper-V -ErrorAction SilentlyContinue } catch {}
$ErrorActionPreference = 'Continue'

# Random suffix function
function New-RandomSuffix {
    param([int]$Length = 3)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })
}

$baseName = 'PXE-CLIENT-UEFI'
for ($i=0; $i -lt 10; $i++) {
    $suffix = New-RandomSuffix
    $VMName = "$baseName-$suffix"
    if (-not (Get-VM -Name $VMName -ErrorAction SilentlyContinue)) { break }
    if ($i -eq 9) { throw "Could not generate unique VM name after 10 attempts." }
}

# Resolve script root and per-VM VHD path
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }
$ArchiveDir = Join-Path $ScriptRoot 'archive'
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }
$VhdFileName = "$VMName.vhdx"
$VhdPath = Join-Path $ArchiveDir $VhdFileName

Write-Host "[INFO] Preparing UEFI PXE VM '$VMName' (Gen2)" -ForegroundColor Cyan

# Create VM if needed
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
New-VM -Name $VMName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -SwitchName $SwitchName | Out-Null
$vm = Get-VM -Name $VMName
Write-Host "[OK] VM created: $VMName" -ForegroundColor Green

# Disable automatic checkpoints
try { Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -ErrorAction Stop; Write-Host "[OK] Automatic checkpoints disabled." -ForegroundColor Green } catch { Write-Host "[WARN] Unable to disable automatic checkpoints: $($_.Exception.Message)" -ForegroundColor Yellow }

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

if ($Start) {
    try { Start-VM -Name $VMName -ErrorAction Stop; Write-Host "[OK] VM started: $VMName" -ForegroundColor Green } catch { Write-Host "[FAIL] Start failed: $($_.Exception.Message)" -ForegroundColor Red }
} else {
    Write-Host "[INFO] Not started. Run: Start-VM -Name '$VMName'" -ForegroundColor DarkCyan
}

# Emit object for automation
[pscustomobject]@{ VMName = $VMName; VhdPath = $VhdPath }
