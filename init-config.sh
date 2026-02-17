#!/usr/bin/env bash

# SCRIPT_DESC: Initialize configuration and detect install path
# SCRIPT_DETECT: [ -f includes/config.sh ]

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source colors
if [ -f "${SCRIPT_DIR}/includes/colors.sh" ]; then
    # shellcheck source=includes/colors.sh
    source "${SCRIPT_DIR}/includes/colors.sh"
else
    # Fallback if colors.sh is missing
    GREEN=""
    YELLOW=""
    RED=""
    NC=""
fi

CONFIG_FILE="${SCRIPT_DIR}/includes/config.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Proxmox Setup Scripts - Initialization${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Detect installation path
echo -e "Detecting installation path..."
echo -e "${YELLOW}Detected:${NC} $SCRIPT_DIR"
echo ""

# Prompt for iGPU VRAM size
IGPU_VRAM_GB="16" # Fallback default

# Try to auto-detect VRAM
DETECTED_VRAM_BYTES=""
if [ -f "/sys/class/drm/card0/device/mem_info_vram_total" ]; then
    DETECTED_VRAM_BYTES=$(cat /sys/class/drm/card0/device/mem_info_vram_total)
elif [ -f "/sys/class/drm/card1/device/mem_info_vram_total" ]; then
    DETECTED_VRAM_BYTES=$(cat /sys/class/drm/card1/device/mem_info_vram_total)
fi

if [ -n "$DETECTED_VRAM_BYTES" ]; then
    # Convert bytes to GB (Bytes / 1024^3)
    DETECTED_VRAM_GB=$((DETECTED_VRAM_BYTES / 1073741824))
    echo -e "${GREEN}Detected iGPU VRAM: ${DETECTED_VRAM_GB} GB${NC}"
    IGPU_VRAM_GB="$DETECTED_VRAM_GB"
fi

while true; do
    echo -e "Select iGPU VRAM allocation (detected: ${GREEN}${IGPU_VRAM_GB} GB${NC}):"
    echo -e "  1) 16 GB"
    echo -e "  2) 32 GB"
    echo -e "  3) 48 GB"
    echo -e "  4) 64 GB"
    echo -e "  5) 80 GB"
    echo -e "  6) 96 GB"
    echo -e "  7) Custom amount"
    echo -e "  8) Use detected/default (${IGPU_VRAM_GB} GB)"
    
    read -r -p "Enter choice [8]: " vram_choice
    vram_choice=${vram_choice:-8}
    
    case "$vram_choice" in
        1) IGPU_VRAM_GB="16"; break ;;
        2) IGPU_VRAM_GB="32"; break ;;
        3) IGPU_VRAM_GB="48"; break ;;
        4) IGPU_VRAM_GB="64"; break ;;
        5) IGPU_VRAM_GB="80"; break ;;
        6) IGPU_VRAM_GB="96"; break ;;
        7)
            read -r -p "Enter custom VRAM amount in GB: " custom_vram
            if [[ "$custom_vram" =~ ^[0-9]+$ ]]; then
                IGPU_VRAM_GB="$custom_vram"
                break
            else
                echo -e "${RED}Invalid number.${NC}"
            fi
            ;;
        8) break ;; # Keep current IGPU_VRAM_GB value
        *) echo -e "${RED}Invalid choice.${NC}" ;;
    esac
done

# Create includes directory if it doesn't exist (though it should)
if [ ! -d "${SCRIPT_DIR}/includes" ]; then
    mkdir -p "${SCRIPT_DIR}/includes"
fi

# Write config file
echo -e "Generating ${YELLOW}${CONFIG_FILE}${NC}..."

cat > "$CONFIG_FILE" << EOF
# Auto-generated configuration file
# Created on $(date)

# Root directory of the repository
# This is used to mount the scripts into LXC containers and locate resources
SCRIPT_ROOT="${SCRIPT_DIR}"

# Default mount point inside LXC containers
# It is recommended to keep this as-is for compatibility with internal scripts
LXC_MOUNT_POINT="/root/proxmox-gpu-setup-scripts"

# iGPU VRAM Allocation (in GB)
# Used by host/002 - setup-igpu-vram.sh
IGPU_VRAM_GB="${IGPU_VRAM_GB}"

EOF

echo -e "${GREEN}✓ Configuration file created.${NC}"
echo ""
echo -e "Installation path set to: ${YELLOW}$SCRIPT_DIR${NC}"
echo -e "iGPU VRAM set to: ${YELLOW}${IGPU_VRAM_GB} GB${NC}"
echo -e "You can now run ${GREEN}./guided-install.sh${NC} or individual scripts."
echo ""
