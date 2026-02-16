#!/usr/bin/env bash

# SCRIPT_DESC: Generate Steam LXC configuration
# SCRIPT_DETECT: [ -f steam/lxc.conf ]

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/lxc.conf.template"
OUTPUT_FILE="${SCRIPT_DIR}/lxc.conf"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/../includes/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found. Running init-config.sh..."
    if [ -f "${SCRIPT_DIR}/../init-config.sh" ]; then
        bash "${SCRIPT_DIR}/../init-config.sh"
    else
        echo "Error: init-config.sh not found."
        exit 1
    fi
fi

# Source config to get SCRIPT_ROOT and LXC_MOUNT_POINT
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Set defaults if not present
SCRIPT_ROOT=${SCRIPT_ROOT:-"$(dirname "$SCRIPT_DIR")"}
LXC_MOUNT_POINT=${LXC_MOUNT_POINT:-"/root/proxmox-gpu-setup-scripts"}

echo "Generating lxc.conf..."
echo "  Script Root: $SCRIPT_ROOT"
echo "  LXC Mount:   $LXC_MOUNT_POINT"

# Replace placeholders
sed -e "s|{{SCRIPT_ROOT}}|$SCRIPT_ROOT|g" \
    -e "s|{{LXC_MOUNT_POINT}}|$LXC_MOUNT_POINT|g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "✓ lxc.conf generated successfully."
echo ""
echo "To create the container, run:"
echo "  pct create 111 $OUTPUT_FILE" 
