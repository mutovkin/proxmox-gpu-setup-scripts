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

EOF

echo -e "${GREEN}✓ Configuration file created.${NC}"
echo ""
echo -e "Installation path set to: ${YELLOW}$SCRIPT_DIR${NC}"
echo -e "You can now run ${GREEN}./guided-install.sh${NC} or individual scripts."
echo ""
