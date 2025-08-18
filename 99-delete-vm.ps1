<#
 Script: 99-delete-vm.ps1
 Purpose: Clean up (delete) the Hyper-V VM and its VHD created by 01-setup-vm.ps1.
 Usage: Run in elevated PowerShell. Adjust variables if you changed names in the setup script.
#>

$vmName      = 'PXE-UEFI-Client'
$vhdFileName = 'disk.vhdx'

# Resolve script root first (avoid inline if-in-expression parsing issues)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }
$archiveDir = Join-Path -Path $scriptRoot -ChildPath 'archive'
$vhdPath    = Join-Path -Path $archiveDir -ChildPath $vhdFileName

Write-Host "Cleanup starting for VM '$vmName'" -ForegroundColor Cyan

# Remove VM if it exists
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vm) {
    # Stop if running
    if ($vm.State -ne 'Off') {
        Write-Host "Stopping VM..." -ForegroundColor Yellow
        Stop-VM -Name $vmName -Force -TurnOff -ErrorAction SilentlyContinue
    }

    # Remove snapshots (they can block deletion of disk files)
    $snapshots = Get-VMSnapshot -VMName $vmName -ErrorAction SilentlyContinue
    if ($snapshots) {
        Write-Host "Removing $($snapshots.Count) snapshot(s)..." -ForegroundColor Yellow
        $snapshots | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
    }

    Write-Host "Removing VM..." -ForegroundColor Yellow
    Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue

    if (-not (Get-VM -Name $vmName -ErrorAction SilentlyContinue)) {
        Write-Host "VM removed." -ForegroundColor Green
    } else {
        Write-Host "VM removal may have failed; verify manually." -ForegroundColor Red
    }
} else {
    Write-Host "VM '$vmName' not found; skipping VM removal." -ForegroundColor Yellow
}

# Remove VHD if present
if (Test-Path -LiteralPath $vhdPath) {
    try {
        Remove-Item -LiteralPath $vhdPath -Force
        Write-Host "Deleted VHD: $vhdPath" -ForegroundColor Green
    } catch {
        Write-Host "Failed to delete VHD ($vhdPath): $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "VHD not found at $vhdPath; skipping." -ForegroundColor Yellow
}

# Remove archive directory if empty
if (Test-Path -LiteralPath $archiveDir) {
    $remaining = Get-ChildItem -LiteralPath $archiveDir -Force | Where-Object { -not $_.PSIsContainer }
    if (-not $remaining) {
        try {
            Remove-Item -LiteralPath $archiveDir -Force
            Write-Host "Removed empty archive directory: $archiveDir" -ForegroundColor Green
        } catch {
            Write-Host "Archive directory not removed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "Cleanup complete." -ForegroundColor Cyan
