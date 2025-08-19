<#
 Script: 99-delete-vm.ps1
 Purpose: Clean up (delete) the Hyper-V VM and its VHD created by 01-setup-vm.ps1.
 Usage: Run in elevated PowerShell. Adjust variables if you changed names in the setup script.
#>

$vmPrefix = 'PXE-CLIENT-'

# Resolve script root and archive dir
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }
$archiveDir = Join-Path -Path $scriptRoot -ChildPath 'archive'

Write-Host "Cleanup starting for VMs with prefix '$vmPrefix'" -ForegroundColor Cyan

$vms = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$vmPrefix*" }
if (-not $vms) {
    Write-Host "No VMs found with prefix." -ForegroundColor Yellow
} else {
    foreach ($vm in $vms) {
        Write-Host "Processing VM '$($vm.Name)'" -ForegroundColor Cyan
        if ($vm.State -ne 'Off') {
            Write-Host "  Stopping..." -ForegroundColor Yellow
            Stop-VM -Name $vm.Name -Force -TurnOff -ErrorAction SilentlyContinue
        }
        $snaps = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue
        if ($snaps) { Write-Host "  Removing $($snaps.Count) snapshot(s)" -ForegroundColor Yellow; $snaps | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue }
        # Collect attached VHD paths before removal
        $diskPaths = Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue
        Write-Host "  Removing VM" -ForegroundColor Yellow
        Remove-VM -Name $vm.Name -Force -ErrorAction SilentlyContinue
        foreach ($dp in $diskPaths) {
            if ($dp -and (Test-Path -LiteralPath $dp)) {
                # Only delete if inside archive directory (safety)
                if ($dp.StartsWith($archiveDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                    try { Remove-Item -LiteralPath $dp -Force; Write-Host "    Deleted VHD: $dp" -ForegroundColor Green } catch { Write-Host "    Failed VHD delete: $dp :: $($_.Exception.Message)" -ForegroundColor Red }
                } else {
                    Write-Host "    Skipping VHD outside archive: $dp" -ForegroundColor DarkYellow
                }
            }
        }
    }
}

# Remove archive directory if empty
if (Test-Path -LiteralPath $archiveDir) {
    $remaining = Get-ChildItem -LiteralPath $archiveDir -Force -File -ErrorAction SilentlyContinue
    if (-not $remaining) {
        try { Remove-Item -LiteralPath $archiveDir -Force; Write-Host "Removed empty archive directory: $archiveDir" -ForegroundColor Green } catch { Write-Host "Archive directory not removed: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

Write-Host "Cleanup complete." -ForegroundColor Cyan
