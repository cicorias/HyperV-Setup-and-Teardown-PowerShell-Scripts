# Hyper-V Setup and Teardown PowerShell Scripts

A collection of PowerShell scripts for automating the creation and cleanup of PXE client virtual machines in Hyper-V environments. These scripts are designed for testing, development, and educational purposes where you need to quickly provision and clean up PXE-bootable VMs.

## Overview

This repository contains two main PowerShell scripts:

- **`01-setup-vm.ps1`** - Creates PXE client VMs with configurable parameters
- **`99-delete-vm.ps1`** - Safely removes VMs and associated resources created by the setup script

The scripts support both Generation 1 (legacy BIOS) and Generation 2 (UEFI) virtual machines, with Generation 2 UEFI being the default for modern compatibility.

## Prerequisites

### System Requirements
- Windows Server or Windows 10/11 with Hyper-V feature enabled
- PowerShell 5.1 or later
- Hyper-V PowerShell module installed and available
- Administrator privileges (scripts must be run elevated)

### Hyper-V Setup
- Hyper-V role/feature must be enabled
- At least one virtual switch configured (default expects 'PXENetwork')
- Sufficient disk space for VM storage (VHD files stored in `archive/` subdirectory)

### Virtual Switch Setup
Before running the scripts, ensure you have a virtual switch created. The default switch name is `PXENetwork`, but this can be customized.

```powershell
# Example: Create an external virtual switch
New-VMSwitch -Name "PXENetwork" -NetAdapterName "Ethernet" -AllowManagementOS $true

# Example: Create an internal virtual switch
New-VMSwitch -Name "PXENetwork" -SwitchType Internal
```

## Repository Structure

```
HyperV-Setup-and-Teardown-PowerShell-Scripts/
├── README.md                 # This documentation file
├── 01-setup-vm.ps1          # VM creation and setup script
├── 99-delete-vm.ps1          # VM cleanup and removal script
└── archive/                  # Directory for VHD files (created automatically)
    └── *.vhdx               # Virtual hard disk files for created VMs
```

### Directory Explanation

- **`archive/`** - Automatically created subdirectory where all VHD files are stored. This directory is relative to the script location and helps organize VM storage files.
- **Script files** - PowerShell scripts with numeric prefixes indicating execution order (01 for setup, 99 for cleanup).

## Script Documentation

### 01-setup-vm.ps1 - VM Setup Script

Creates PXE client virtual machines with automatic unique naming and configurable parameters.

#### Features
- **Dual Generation Support**: Create either Generation 1 (BIOS) or Generation 2 (UEFI) VMs
- **Unique Naming**: Automatic random suffix generation to prevent name conflicts
- **Dynamic VHD Creation**: Creates VHD files in organized archive directory
- **Network Configuration**: Connects VMs to specified virtual switch
- **UEFI Boot Configuration**: Sets boot order (NIC first, then disk) for PXE booting
- **Safety Features**: Prevents overwriting existing VMs and handles errors gracefully

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `UEFI` | Switch | `$true` | Create Generation 2 (UEFI) VM. Use `-UEFI:$false` for Generation 1 (BIOS) |
| `CPUCount` | Int | `2` | Number of virtual processors to assign |
| `MemoryGB` | Int | `2` | Amount of RAM in gigabytes |
| `VhdSizeGB` | Int | `20` | Size of virtual hard disk in gigabytes |
| `SwitchName` | String | `'PXENetwork'` | Name of the virtual switch to connect to |
| `SecureBoot` | String | `'Off'` | Secure Boot setting (`'On'` or `'Off'`). Only applies to UEFI VMs |
| `Start` | Switch | Not set | Automatically start the VM after creation |

#### VM Naming Convention

VMs are created with unique names using the following pattern:
- **Generation 2 (UEFI)**: `PXE-CLIENT-UEFI-XXX` (where XXX is a random 3-character suffix)
- **Generation 1 (BIOS)**: `PXE-CLIENT-XXX` (where XXX is a random 3-character suffix)

VHD files are named to match the VM name: `{VMName}.vhdx`

#### Usage Examples

```powershell
# Basic usage - Create default UEFI PXE client
.\01-setup-vm.ps1

# Create Generation 1 (BIOS) PXE client
.\01-setup-vm.ps1 -UEFI:$false

# Create VM with custom specifications
.\01-setup-vm.ps1 -MemoryGB 4 -VhdSizeGB 40 -CPUCount 4

# Create VM with custom switch and auto-start
.\01-setup-vm.ps1 -SwitchName "MyTestNetwork" -Start

# Create UEFI VM with Secure Boot enabled
.\01-setup-vm.ps1 -SecureBoot On -Start

# Full customization example
.\01-setup-vm.ps1 -UEFI:$true -MemoryGB 8 -VhdSizeGB 80 -CPUCount 4 -SwitchName "TestLab" -SecureBoot Off -Start
```

#### Output
The script returns a PowerShell object with creation details:
```powershell
VMName     : PXE-CLIENT-UEFI-A7K
VhdPath    : C:\Scripts\archive\PXE-CLIENT-UEFI-A7K.vhdx
UEFI       : True
Generation : 2
```

### 99-delete-vm.ps1 - VM Cleanup Script

Safely removes all PXE client VMs and their associated resources created by the setup script.

#### Features
- **Batch Cleanup**: Removes all VMs matching the PXE client naming pattern
- **Safe VHD Removal**: Only deletes VHD files located in the archive directory
- **Snapshot Handling**: Automatically removes all VM snapshots before deletion
- **Graceful Shutdown**: Stops running VMs before removal
- **Directory Cleanup**: Removes empty archive directory after cleanup

#### VM Pattern Matching
The cleanup script targets VMs with names starting with `PXE-CLIENT-`, which includes:
- `PXE-CLIENT-UEFI-XXX` (Generation 2 VMs)
- `PXE-CLIENT-XXX` (Generation 1 VMs)

#### Safety Features
- **VHD Path Validation**: Only deletes VHD files located within the script's archive directory
- **External VHD Protection**: Skips VHD files located outside the archive directory
- **Error Handling**: Continues cleanup process even if individual operations fail

#### Usage

```powershell
# Run cleanup (no parameters required)
.\99-delete-vm.ps1
```

#### Example Output
```
Cleanup starting for VMs with prefix 'PXE-CLIENT-'
Processing VM 'PXE-CLIENT-UEFI-A7K'
  Stopping...
  Removing VM
    Deleted VHD: C:\Scripts\archive\PXE-CLIENT-UEFI-A7K.vhdx
Processing VM 'PXE-CLIENT-B3M'
  Removing VM
    Deleted VHD: C:\Scripts\archive\PXE-CLIENT-B3M.vhdx
Removed empty archive directory: C:\Scripts\archive
Cleanup complete.
```

## Common Use Cases

### 1. Quick PXE Testing Environment
```powershell
# Create a VM for PXE boot testing
.\01-setup-vm.ps1 -Start

# Test your PXE environment...

# Clean up when done
.\99-delete-vm.ps1
```

### 2. Multiple VM Creation for Testing
```powershell
# Create several VMs with different configurations
.\01-setup-vm.ps1 -MemoryGB 2 -VhdSizeGB 20    # Small VM
.\01-setup-vm.ps1 -MemoryGB 4 -VhdSizeGB 40    # Medium VM
.\01-setup-vm.ps1 -MemoryGB 8 -VhdSizeGB 80    # Large VM

# Clean up all at once
.\99-delete-vm.ps1
```

### 3. Legacy System Testing
```powershell
# Create Generation 1 VM for legacy system testing
.\01-setup-vm.ps1 -UEFI:$false -Start

# Test legacy boot scenarios...

# Clean up
.\99-delete-vm.ps1
```

### 4. Secure Boot Testing
```powershell
# Test with Secure Boot enabled
.\01-setup-vm.ps1 -SecureBoot On -Start

# Test secure boot scenarios...

# Clean up
.\99-delete-vm.ps1
```

## Troubleshooting

### Common Issues and Solutions

#### Virtual Switch Not Found
**Error**: `Virtual switch 'PXENetwork' not found`

**Solution**: Create the virtual switch before running the script:
```powershell
New-VMSwitch -Name "PXENetwork" -SwitchType Internal
```

#### Insufficient Permissions
**Error**: Permission-related errors during VM creation

**Solution**: Ensure PowerShell is running as Administrator:
```powershell
# Check if running as admin
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
```

#### Hyper-V Module Not Available
**Error**: Hyper-V cmdlets not recognized

**Solution**: Install and import the Hyper-V module:
```powershell
# Enable Hyper-V feature (requires restart)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Import module
Import-Module Hyper-V
```

#### Disk Space Issues
**Error**: Insufficient disk space for VHD creation

**Solution**: 
- Check available disk space in the script directory
- Consider using a different location by moving the scripts to a drive with more space
- Reduce VHD size using the `-VhdSizeGB` parameter

#### VM Name Conflicts
**Error**: Could not generate unique VM name after 10 attempts

**Solution**: This is rare but can happen if many VMs exist. Clean up unused VMs or temporarily stop some VMs to free up name space.

### Best Practices

1. **Always run as Administrator**: Hyper-V operations require elevated privileges
2. **Verify virtual switch exists**: Check your virtual switch configuration before running scripts
3. **Monitor disk space**: VHD files can consume significant disk space
4. **Regular cleanup**: Use the cleanup script to remove test VMs when no longer needed
5. **Backup important VMs**: These scripts are designed for disposable test VMs

### Advanced Configuration

#### Using Custom Virtual Switches
```powershell
# Create and use a custom switch
New-VMSwitch -Name "MyTestLab" -SwitchType Internal
.\01-setup-vm.ps1 -SwitchName "MyTestLab"
```

#### Scripted Batch Operations
```powershell
# Create multiple VMs in a loop
1..5 | ForEach-Object {
    .\01-setup-vm.ps1 -MemoryGB 2 -VhdSizeGB 20
    Start-Sleep -Seconds 2  # Brief pause between creations
}
```

## Safety Considerations

- **VHD File Management**: The cleanup script only removes VHD files from the `archive/` directory to prevent accidental deletion of important files
- **VM Identification**: Scripts use specific naming patterns to avoid affecting other VMs in your environment
- **Error Handling**: Scripts include error handling to prevent cascading failures
- **Confirmation**: Consider adding `-Confirm` parameter if modifying scripts for production use

## Contributing

When contributing to this repository:
1. Test scripts in isolated environments
2. Ensure compatibility with both PowerShell 5.1 and 7.x
3. Maintain the existing error handling patterns
4. Update documentation for any parameter or functionality changes

## License

This project is provided as-is for educational and testing purposes. Please review and test thoroughly before using in any production environment.