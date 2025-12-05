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

echo "The PCluster driver has been installed!"
