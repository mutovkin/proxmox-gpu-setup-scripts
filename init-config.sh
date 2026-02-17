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

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ROCm Version Selection${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Function to fetch ROCm versions and dates
fetch_rocm_versions() {
    echo -e "${YELLOW}Fetching available ROCm versions from repo.radeon.com...${NC}" >&2
    # Fetch directory listing
    local listing
    listing=$(curl -s --connect-timeout 5 https://repo.radeon.com/rocm/apt/)
    
    if [ -z "$listing" ]; then
        echo -e "${RED}Failed to fetch versions. Check internet connection.${NC}" >&2
        return 1
    fi

    # Parse versions and dates
    # Format matches: <a href="7.2/">7.2/</a> ... 13-Jan-2026 02:08
    # Using sed -E to extract version and date
    local parsed_versions
    parsed_versions=$(echo "$listing" | \
        sed -nE 's/.*<a href="([0-9]+\.[0-9]+(\.[0-9]+)?)\/">.*<\/a>[[:space:]]+([0-9]{2}-[A-Z][a-z]{2}-[0-9]{4}).*/\1|\3/p' | \
        sort -t. -k1,1nr -k2,2nr -k3,3nr | head -n 5)
        # Note: sort -V is standard GNU but may act differently on partial matches with pipes. 
        # Using numeric sort on fields roughly or just trusting -V. 
        # On second thought, sort -V is usually available on Debian/Ubuntu/Proxmox.
        # Let's use sort -V -r. On mac it might behave differently but the target is Proxmox.
    
    # Re-doing the sort command to be safe: valid versions are like 7.2 or 6.1.1
    # We can rely on sort -V -r
    parsed_versions=$(echo "$listing" | \
        sed -nE 's/.*<a href="([0-9]+\.[0-9]+(\.[0-9]+)?)\/">.*<\/a>[[:space:]]+([0-9]{2}-[A-Z][a-z]{2}-[0-9]{4}).*/\1|\3/p' | \
        sort -V -r | head -n 5)

    if [ -z "$parsed_versions" ]; then
        echo -e "${RED}Could not parse version list.${NC}" >&2
        return 1
    fi
    
    echo "$parsed_versions"
    return 0
}

# Fetch versions
ROCM_VERSION_OPTIONS=$(fetch_rocm_versions)
ROCM_VERSION_DEFAULT="7.2" # Hard fallback

if [ $? -eq 0 ] && [ -n "$ROCM_VERSION_OPTIONS" ]; then
    echo -e "Available ROCm versions:"
    
    # Read into array
    # We'll display a menu
    IFS=$'\n' read -rd '' -a versions_array <<< "$ROCM_VERSION_OPTIONS"
    
    # Default to the first one (latest)
    latest_entry="${versions_array[0]}"
    ROCM_VERSION_DEFAULT="${latest_entry%%|*}"
    
    select_opts=()
    for entry in "${versions_array[@]}"; do
        ver="${entry%%|*}"
        date="${entry##*|}"
        echo -e "  ${#select_opts[@]}) ${GREEN}${ver}${NC} \t(Released: ${YELLOW}${date}${NC})"
        select_opts+=("$ver")
    done
    
    echo -e "  ${#select_opts[@]}) Manual Entry"
    
    read -r -p "Select ROCm version [0]: " ver_choice
    ver_choice=${ver_choice:-0}
    
    if [[ "$ver_choice" =~ ^[0-9]+$ ]] && [ "$ver_choice" -lt "${#select_opts[@]}" ]; then
        ROCM_VERSION="${select_opts[$ver_choice]}"
    elif [ "$ver_choice" -eq "${#select_opts[@]}" ]; then
        read -r -p "Enter manual ROCm version (e.g., 6.2.4): " ROCM_VERSION
    else
        echo -e "${YELLOW}Invalid choice, using default: ${ROCM_VERSION_DEFAULT}${NC}"
        ROCM_VERSION="$ROCM_VERSION_DEFAULT"
    fi
else
    echo -e "${YELLOW}Using default/fallback version mechanism.${NC}"
    read -r -p "Enter ROCm version [${ROCM_VERSION_DEFAULT}]: " input_ver
    ROCM_VERSION="${input_ver:-$ROCM_VERSION_DEFAULT}"
fi

echo -e "Selected ROCm Version: ${GREEN}${ROCM_VERSION}${NC}"
echo ""

# Function to fetch Ubuntu codenames for the selected version
fetch_codenames() {
    local version=$1
    echo -e "${YELLOW}Fetching supported Ubuntu codenames for ROCm ${version}...${NC}" >&2
    
    local listing
    listing=$(curl -s --connect-timeout 5 "https://repo.radeon.com/rocm/apt/${version}/dists/")
    
    if [ -z "$listing" ]; then
        echo -e "${RED}Failed to fetch codenames.${NC}" >&2
        return 1
    fi
    
    # Parse directory names ending in /
    # Exclude parent directory / and others if needed
    # Also exclude external links (starting with http/https or containing :)
    local codenames
    codenames=$(echo "$listing" | grep -E 'href="[^"]+/"' | cut -d'"' -f2 | grep -v 'http' | grep -v ':' | tr -d '/' | grep -v '^\.\.$' | grep -v 'debian')
    
    if [ -z "$codenames" ]; then
        return 1
    fi
    
    echo "$codenames"
    return 0
}

# Fetch codenames
ROCM_CODENAME_OPTIONS=$(fetch_codenames "$ROCM_VERSION")
ROCM_UBUNTU_CODENAME_DEFAULT="noble"

# Logic to pick default logic:
# 1. noble (24.04)
# 2. jammy (22.04)
# 3. first available
if [[ "$ROCM_CODENAME_OPTIONS" == *"noble"* ]]; then
    ROCM_UBUNTU_CODENAME_DEFAULT="noble"
elif [[ "$ROCM_CODENAME_OPTIONS" == *"jammy"* ]]; then
    ROCM_UBUNTU_CODENAME_DEFAULT="jammy"
elif [ -n "$ROCM_CODENAME_OPTIONS" ]; then
    ROCM_UBUNTU_CODENAME_DEFAULT=$(echo "$ROCM_CODENAME_OPTIONS" | head -n1)
fi


if [ -n "$ROCM_CODENAME_OPTIONS" ]; then
    echo -e "Available Ubuntu codenames for ROCm ${ROCM_VERSION}:"
    
    IFS=$'\n' read -rd '' -a codenames_array <<< "$ROCM_CODENAME_OPTIONS"
    
    select_opts=()
    for cn in "${codenames_array[@]}"; do
        marker=""
        if [ "$cn" == "$ROCM_UBUNTU_CODENAME_DEFAULT" ]; then
            marker="*"
        fi
        echo -e "  ${#select_opts[@]}) ${cn} ${marker}"
        select_opts+=("$cn")
    done
    
    echo -e "  ${#select_opts[@]}) Manual Entry"
    
    # Find index of default
    default_idx=0
    for i in "${!select_opts[@]}"; do
        if [[ "${select_opts[$i]}" == "$ROCM_UBUNTU_CODENAME_DEFAULT" ]]; then
            default_idx=$i
            break
        fi
    done
    
    read -r -p "Select Ubuntu Codename [${default_idx}]: " cn_choice
    cn_choice=${cn_choice:-$default_idx}
    
    if [[ "$cn_choice" =~ ^[0-9]+$ ]] && [ "$cn_choice" -lt "${#select_opts[@]}" ]; then
        ROCM_UBUNTU_CODENAME="${select_opts[$cn_choice]}"
    elif [ "$cn_choice" -eq "${#select_opts[@]}" ]; then
        read -r -p "Enter manual codename (e.g., noble): " ROCM_UBUNTU_CODENAME
    else
         echo -e "${YELLOW}Invalid choice, using default: ${ROCM_UBUNTU_CODENAME_DEFAULT}${NC}"
         ROCM_UBUNTU_CODENAME="$ROCM_UBUNTU_CODENAME_DEFAULT"
    fi

else
     echo -e "${YELLOW}Could not fetch codenames. Using default.${NC}"
     read -r -p "Enter Ubuntu codename [${ROCM_UBUNTU_CODENAME_DEFAULT}]: " input_cn
     ROCM_UBUNTU_CODENAME="${input_cn:-$ROCM_UBUNTU_CODENAME_DEFAULT}"
fi

echo -e "Selected OS Codename: ${GREEN}${ROCM_UBUNTU_CODENAME}${NC}"


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

# ROCm Configuration
# Automatically detected/selected on $(date)
ROCM_VERSION="${ROCM_VERSION}"
ROCM_UBUNTU_CODENAME="${ROCM_UBUNTU_CODENAME}"

EOF

echo -e "${GREEN}✓ Configuration file created.${NC}"
echo ""
echo -e "Installation path set to: ${YELLOW}$SCRIPT_DIR${NC}"
echo -e "iGPU VRAM set to: ${YELLOW}${IGPU_VRAM_GB} GB${NC}"
echo -e "ROCm Version: ${YELLOW}${ROCM_VERSION}${NC} (${ROCM_UBUNTU_CODENAME})"
echo -e "You can now run ${GREEN}./guided-install.sh${NC} or individual scripts."
echo ""
