#!/usr/bin/env bash

# SCRIPT_DESC: Setup AMD Ryzen AI 300 / AI PRO 300 Processors iGPU VRAM allocation
# SCRIPT_DETECT: grep -q "amdgpu.gttsize" /proc/cmdline 2>/dev/null

# Get script directory and source config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../includes/config.sh"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=../includes/config.sh
    source "$CONFIG_FILE"
fi

# Default to 16GB if not set
IGPU_VRAM_GB=${IGPU_VRAM_GB:-16}

echo ">>> Setting iGPU VRAM to ${IGPU_VRAM_GB}GB and related parameters"

# Calculate parameters
# 1 GB = 1024 MB
# 1 Page = 4096 Bytes
VRAM_MB=$((IGPU_VRAM_GB * 1024))
VRAM_BYTES=$((IGPU_VRAM_GB * 1024 * 1024 * 1024))
VRAM_PAGES=$((VRAM_BYTES / 4096))

echo "    - GTT Size: ${VRAM_MB} MB"
echo "    - Pages:    ${VRAM_PAGES}"

# Define the parameters to add
amdgpu_vram_string="amdgpu.gttsize=${VRAM_MB} ttm.pages_limit=${VRAM_PAGES} ttm.page_pool_size=${VRAM_PAGES}"

# Check if the system is using ZFS (has /etc/kernel/cmdline)
if [ -f /etc/kernel/cmdline ]; then
    echo ">>> Detected ZFS system - using /etc/kernel/cmdline"
    
    # Check if the string is already in the first line
    if grep -q "amdgpu.gttsize" /etc/kernel/cmdline; then
        echo ">>> Existing VRAM configuration found. Updating..."
        # Remove existing params and append new ones (simplistic approach for now)
        # Note: A proper sed replace for variable numbers is complex, advising manual check if values differ
        current_cmdline=$(cat /etc/kernel/cmdline)
        if [[ "$current_cmdline" == *"$amdgpu_vram_string"* ]]; then
             echo ">>> Configuration matches. No changes needed."
        else
             echo ">>> WARNING: Different VRAM configuration detected."
             echo ">>> Please manually edit /etc/kernel/cmdline to remove old 'amdgpu.gttsize', 'ttm.pages_limit', and 'ttm.page_pool_size' entries."
             echo ">>> Then run this script again."
             exit 1
        fi
    else
        echo ">>> Adding parameters to kernel cmdline"
        sed -i "1s/$/ $amdgpu_vram_string/" /etc/kernel/cmdline
        echo ">>> Refreshing Proxmox boot tool to apply changes"
        proxmox-boot-tool refresh
        echo ">>> Please now reboot the system"
    fi
else
    echo ">>> Detected non-ZFS system - using /etc/default/grub"
    
    # Check if the parameters are already present in grub
    if grep -q "amdgpu.gttsize" /etc/default/grub; then
        echo ">>> Existing VRAM configuration found in GRUB."
        # Similar check for GRUB
        if grep -q "$amdgpu_vram_string" /etc/default/grub; then
             echo ">>> Configuration matches. No changes needed."
        else
             echo ">>> WARNING: Different VRAM configuration detected."
             echo ">>> Please manually edit /etc/default/grub to remove old 'amdgpu.gttsize', 'ttm.pages_limit', and 'ttm.page_pool_size' entries."
             echo ">>> Then run this script again."
             exit 1
        fi
    else
        echo ">>> Adding parameters to GRUB configuration"
        # Get the current GRUB_CMDLINE_LINUX_DEFAULT value
        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/\1/')
        
        # Append the new parameters to the existing value
        new_cmdline="$current_cmdline $amdgpu_vram_string"
        
        # Update the grub configuration
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" /etc/default/grub
        
        echo ">>> Updating GRUB"
        update-grub
        echo ">>> Please now reboot the system"
    fi
fi
