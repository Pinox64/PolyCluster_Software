# PolyCluster — USB Needle Gauge Hardware Monitor

PolyCluster is a multi-purpose needle gauge display featuring 4 analog dials and 4 small OLED screens used as dynamic labels. When connected to a computer, PCluster displays real-time system information using a physical, mechanical interface.

This repository contains the platform-specific software required to communicate with the PCluster hardware.

## Features

- USB HID interface (no OS driver required)
- Real-time hardware monitoring
- Four fully controllable needle gauges
- Four dynamic label screens
- Lightweight Linux backend + UI
- Separate Windows and Linux implementations
- The code is source-available with protections against commercial cloning

## Installation (Windows)

Download the Windows version from Releases and run `PCluster_Installer_vx.x.x.exe`.
Please note that due to the fact that the software needs admin privilege to run, you will be prompted to allow the software to run as admin at every startup if you check the "run at startup option.

## Installation (Linux)

1. Download the lastest release archive from the release section of the repo. Make sure the files `PCluster_Backend`, `PCluster_UI`, and `install.sh` are present in a folder together.
2. Make installer executable:

```
chmod +x install.sh
```

3. Run installer:

```
sudo ./install.sh
```

Backend installs to `/usr/local/bin` and runs as `pcluster_backend.service`.

4. Post installation:
   
After the installation, the PCluster display should light up and start displaying the hardware usage info.
It might be necessary to unplug and replug the device.
For setting up colors, brightness and info to be displayed on the device, see the next section.

### Usage of the UI (linux)

#### Start UI:
To start the user interface open a terminal and type:
```
PCluster_UI
```
#### Changing the color and brightness
To change color, hover the mouse above one of the RGB sliders and rotate the scroll wheel.
### Change the info for each dial
To change the info displayed on a specific dial, place the mouce cursor above the screen label of the dial and rotate the scroll wheel.


### Managing Backend (linux)

```
systemctl status pcluster_backend.service
systemctl stop pcluster_backend.service
systemctl start pcluster_backend.service
systemctl disable pcluster_backend.service
```

## License

Licensed under **MIT + Commons Clause**.

### Allowed:
- Commercial use
- Modification, forking, personal or internal business use
- Free redistribution

### Not allowed:
- Selling the software
- Including it in a paid product
- Selling modified versions
- Using it to create a competing commercial hardware/software product
