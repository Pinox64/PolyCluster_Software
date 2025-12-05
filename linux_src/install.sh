#!/usr/bin/env bash
set -euo pipefail

# PCluster Linux installer / configurator
# Modes:
#   1) Configure permissions only (udev + group) so the backend can talk to the device
#   2) Full install: binaries to /usr/local/bin + permissions + systemd service (auto-start)
#   3) Install binaries + permissions + systemd service, but DO NOT auto-start on boot
#   4) Uninstall everything this installer may have set up (binaries, service, udev rule, group entry)

# -----------------------------
# Configuration
# -----------------------------
INSTALL_DIR="/usr/local/bin"
BACKEND_NAME="PCluster_Backend"
UI_NAME="PCluster_UI"

BACKEND_DEST="${INSTALL_DIR}/${BACKEND_NAME}"
UI_DEST="${INSTALL_DIR}/${UI_NAME}"

LEGACY_BIN="${INSTALL_DIR}/PCluster_Driver"   # Legacy shim name
SERVICE_ID="pcluster_backend"
SERVICE_NAME="${SERVICE_ID}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

UDEV_RULE_FILE="/etc/udev/rules.d/99-pcluster.rules"
# HID Vendor/Product IDs for PCluster (from your snippet)
PCLUSTER_UDEV_RULE='KERNEL=="hidraw*", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="fe07", MODE="0660", GROUP="pcluster"'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BACKEND_SRC="${SCRIPT_DIR}/${BACKEND_NAME}"
UI_SRC="${SCRIPT_DIR}/${UI_NAME}"

# -----------------------------
# Root check / user detection
# -----------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Error: this script must be run as root."
    echo "Use: sudo ./install.sh"
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
    TARGET_USER=""
fi

# -----------------------------
# Helper functions
# -----------------------------

setup_udev_and_group() {
    echo "Configuring udev rule and pcluster group..."

    echo "Installing udev rule at ${UDEV_RULE_FILE}..."
    printf '%s\n' "${PCLUSTER_UDEV_RULE}" > "${UDEV_RULE_FILE}"

    echo "Ensuring group 'pcluster' exists..."
    groupadd pcluster 2>/dev/null || true

    if [[ -n "${TARGET_USER}" ]]; then
        echo "Adding user '${TARGET_USER}' to group 'pcluster'..."
        usermod -aG pcluster "${TARGET_USER}"
        echo "User '${TARGET_USER}' added to pcluster group."
        echo "You may need to log out and back in for group changes to take effect."
    else
        echo "Warning: could not detect a non-root invoking user."
        echo "Add your user to the 'pcluster' group manually, for example:"
        echo "  sudo usermod -aG pcluster <your-username>"
    fi

    echo "Reloading udev rules..."
    udevadm control --reload-rules
    udevadm trigger

    # If a PCluster is currently plugged in, ask the user to replug it
    if cd /sys/class/hidraw 2>/dev/null; then
        if ls | xargs readlink 2>/dev/null | grep -qi "1A86:FE07"; then
            echo
            echo "A PCluster device appears to be plugged in."
            echo "Unplug and replug your PCluster for the new permissions to take effect!"
        fi
    fi

    echo "Udev and group configuration complete."
    echo
}

install_binaries() {
    echo "Installing binaries to ${INSTALL_DIR}..."

    if [[ ! -f "${BACKEND_SRC}" ]]; then
        echo "Error: ${BACKEND_SRC} not found."
        echo "Make sure ${BACKEND_NAME} is in the same folder as this script."
        exit 1
    fi

    if [[ ! -f "${UI_SRC}" ]]; then
        echo "Warning: ${UI_SRC} not found."
        echo "Continuing without installing ${UI_NAME}."
    fi

    install -m 0755 "${BACKEND_SRC}" "${BACKEND_DEST}"
    echo "Installed backend: ${BACKEND_DEST}"

    if [[ -f "${UI_SRC}" ]]; then
        install -m 0755 "${UI_SRC}" "${UI_DEST}"
        echo "Installed UI:      ${UI_DEST}"
    fi

    # Legacy compatibility shim
    ln -sf "${BACKEND_DEST}" "${LEGACY_BIN}"
    echo "Legacy shim installed at ${LEGACY_BIN} (symlink to ${BACKEND_DEST})."
    echo
}

create_systemd_unit() {
    echo "Creating systemd unit at ${SERVICE_FILE}..."

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=PCluster Backend (hardware monitoring service)
After=network.target

[Service]
Type=simple
ExecStart=${BACKEND_DEST}
Restart=always
RestartSec=2
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    echo "Reloading systemd daemon..."
    systemctl daemon-reload
    echo
}

enable_and_start_service() {
    echo "Enabling and starting ${SERVICE_NAME}..."
    systemctl enable --now "${SERVICE_NAME}"
    echo "Service ${SERVICE_NAME} is enabled and running."
    echo
}

start_service_once() {
    echo "Starting ${SERVICE_NAME} (not enabled on boot)..."
    systemctl start "${SERVICE_NAME}"
    echo "Service ${SERVICE_NAME} started (but not enabled for autostart)."
    echo
}

print_summary_permissions_only() {
    echo "======================================="
    echo "   PCluster permissions configured"
    echo "======================================="
    echo "- Udev rule installed: ${UDEV_RULE_FILE}"
    echo "- Group 'pcluster' ensured."
    if [[ -n "${TARGET_USER}" ]]; then
        echo "- User '${TARGET_USER}' added to 'pcluster' group."
    else
        echo "- Remember to add your user to 'pcluster' group manually."
    fi
    echo
    echo "You can now run ${BACKEND_NAME} manually (once it is installed or built)"
    echo "without requiring root, after re-logging and replugging the device."
    echo
}

print_summary_full_install() {
    echo "======================================="
    echo "     PCluster full install complete"
    echo "======================================="
    echo "- Backend installed: ${BACKEND_DEST}"
    if [[ -f "${UI_DEST}" ]]; then
        echo "- UI installed:      ${UI_DEST}"
    fi
    echo "- Udev rule:         ${UDEV_RULE_FILE}"
    echo "- Group:             pcluster"
    echo "- Systemd service:   ${SERVICE_NAME} (enabled at boot)"
    echo
    echo "Run UI with:"
    echo "  ${UI_NAME}"
    echo
}

print_summary_install_no_autostart() {
    echo "======================================="
    echo "  PCluster install (no autostart)"
    echo "======================================="
    echo "- Backend installed: ${BACKEND_DEST}"
    if [[ -f "${UI_DEST}" ]]; then
        echo "- UI installed:      ${UI_DEST}"
    fi
    echo "- Udev rule:         ${UDEV_RULE_FILE}"
    echo "- Group:             pcluster"
    echo "- Systemd service:   ${SERVICE_NAME} (NOT enabled at boot)"
    echo
    echo "To start the backend manually (current session):"
    echo "  sudo systemctl start ${SERVICE_NAME}"
    echo
    echo "To enable autostart later:"
    echo "  sudo systemctl enable --now ${SERVICE_NAME}"
    echo
    echo "Run UI with:"
    echo "  ${UI_NAME}"
    echo
}

uninstall_all() {
    echo "Uninstalling PCluster backend, service, and permissions..."

    if command -v systemctl >/dev/null 2>&1; then
        echo "Stopping/disabling ${SERVICE_NAME} (if present)..."
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    fi

    if [[ -f "${SERVICE_FILE}" ]]; then
        echo "Removing systemd unit ${SERVICE_FILE}..."
        rm -f "${SERVICE_FILE}"
        command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload
    fi

    echo "Removing binaries..."
    rm -f "${BACKEND_DEST}" "${UI_DEST}" "${LEGACY_BIN}"

    if [[ -f "${UDEV_RULE_FILE}" ]]; then
        echo "Removing udev rule ${UDEV_RULE_FILE}..."
        rm -f "${UDEV_RULE_FILE}"
        udevadm control --reload-rules
        udevadm trigger
    fi

    if getent group pcluster >/dev/null 2>&1; then
        if [[ -n "${TARGET_USER}" ]]; then
            echo "Attempting to remove user '${TARGET_USER}' from group 'pcluster' (if present)..."
            gpasswd -d "${TARGET_USER}" pcluster 2>/dev/null || true
        fi
        # Remove group if now empty
        if ! getent group pcluster | awk -F: '{print $4}' | grep -q '.'; then
            echo "Removing empty group 'pcluster'..."
            groupdel pcluster 2>/dev/null || true
        else
            echo "Group 'pcluster' still has members; leaving it in place."
        fi
    fi

    echo
    echo "Uninstall complete. If you unplugged/plugged the device earlier, you may need to replug once more."
    echo
}

# -----------------------------
# Menu
# -----------------------------

echo "======================================="
echo "       PCluster Linux Installer"
echo "======================================="
echo
echo "Select an option:"
echo
echo "  1) Configure permissions only"
echo "     - Install udev rule"
echo "     - Create 'pcluster' group"
echo "     - Add your user to 'pcluster' (if detectable)"
echo "     - Reload udev and prompt to replug device"
echo "     - Does NOT install binaries or systemd units"
echo
echo "  2) Full install"
echo "     - Install backend and UI to ${INSTALL_DIR}"
echo "     - Install udev rule and group"
echo "     - Create systemd service ${SERVICE_NAME}"
echo "     - Enable and start backend at boot"
echo
echo "  3) Install binaries + permissions, but NO autostart"
echo "     - Install backend and UI to ${INSTALL_DIR}"
echo "     - Install udev rule and group"
echo "     - Create systemd service ${SERVICE_NAME}"
echo "     - Do NOT enable service on boot"
echo
echo "  4) Uninstall everything created by this installer"
echo "     - Remove systemd service, binaries, legacy shim"
echo "     - Remove udev rule and reload udev"
echo "     - Remove pcluster group if empty (and remove invoking user from it if present)"
echo
read -rp "Enter choice [1/2/3/4] (or anything else to cancel): " CHOICE
echo

case "${CHOICE}" in
    1)
        setup_udev_and_group
        print_summary_permissions_only
        ;;
    2)
        setup_udev_and_group
        install_binaries
        if command -v systemctl >/dev/null 2>&1; then
            create_systemd_unit
            enable_and_start_service
        else
            echo "Warning: systemd not found; backend will not be managed as a service."
            echo "You can still run the backend manually with:"
            echo "  ${BACKEND_DEST}"
            echo
        fi
        print_summary_full_install
        ;;
    3)
        setup_udev_and_group
        install_binaries
        if command -v systemctl >/dev/null 2>&1; then
            create_systemd_unit
            echo "Systemd unit created but NOT enabled."
            echo "You may start it manually with:"
            echo "  sudo systemctl start ${SERVICE_NAME}"
            echo
        else
            echo "Warning: systemd not found; backend will not be managed as a service."
            echo "You can still run the backend manually with:"
            echo "  ${BACKEND_DEST}"
            echo
        fi
        print_summary_install_no_autostart
        ;;
    4)
        uninstall_all
        ;;
    *)
        echo "Installation cancelled."
        exit 0
        ;;
esac
