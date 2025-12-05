#!/usr/bin/env bash

# User-space backend installer for PCluster. This sets up permissions and
# installs/enables the backend service (it is not a kernel/OS driver).

BACKEND_BIN="/usr/local/bin/PCluster_Backend"
LEGACY_BIN="/usr/local/bin/PCluster_Driver"
SERVICE_NAME="pcluster_backend.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install a udev rule to allow members of the group "pcluster" to talk with the PCluster
PCLUSTER_UDEV_RULE='KERNEL=="hidraw*", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="fe07", MODE="0660", GROUP="pcluster"'
echo "$PCLUSTER_UDEV_RULE" | sudo tee /etc/udev/rules.d/99-pcluster.rules >/dev/null

# Add the pcluster group if it doesnt exist
sudo groupadd pcluster 2>/dev/null
sudo usermod -aG pcluster $USER

# Restart udev to pickup the new rule
sudo udevadm control --reload-rules
sudo udevadm trigger

# If a PCluster in plugged in ask to replug it
if cd /sys/class/hidraw; ls | xargs readlink | grep -q "1A86:FE07"; then
    echo "Unplug and replug your PCluster for the changes to take effect!"
fi

if [ -f "${SCRIPT_DIR}/pcluster_backend.service" ]; then
    echo "Installing ${SERVICE_NAME} systemd unit..."
    sudo cp "${SCRIPT_DIR}/pcluster_backend.service" "${SERVICE_PATH}"
    sudo systemctl daemon-reload
    if [ -x "${BACKEND_BIN}" ]; then
        sudo systemctl enable --now "${SERVICE_NAME}"
    else
        echo "Backend binary ${BACKEND_BIN} not found; unit installed but not started."
        echo "Install the binary, then run: sudo systemctl enable --now ${SERVICE_NAME}"
    fi
fi

if [ -x "${BACKEND_BIN}" ]; then
    sudo ln -sf "${BACKEND_BIN}" "${LEGACY_BIN}"
    echo "Legacy compatibility shim installed at ${LEGACY_BIN} (calls ${BACKEND_BIN})."
fi

echo "The PCluster backend service has been installed!"
