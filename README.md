# Debian Package For Homebridge

[![GitHub release (latest by date)](https://badgen.net/github/release/homebridge/homebridge-apt-pkg?label=Version)](https://github.com/homebridge/homebridge-apt-pkg/releases/latest)
[![GitHub All Releases](https://img.shields.io/github/downloads/homebridge/homebridge-apt-pkg/total)](https://somsubhra.github.io/github-release-stats/?username=homebridge&repository=homebridge-apt-pkg&page=1&per_page=30)

This project builds and publishes a debian-based package that can be installed using `apt` on Ubuntu / Debian / Raspberry Pi OS based Linux systems.

The project aims to deploy Homebridge and the Homebridge UI in a secure and stable way, with no dependencies outside those available in the standard distribution repos. It comes bundled with it's own Node.js runtime and runs Homebridge in an isolated environment as a service user with no sudo / admin priviledges.

Supported architectures:

* x86_64
* armhf ( armv7) (Pls note that support for 32 Bit OS's will end in Spring of 2027)
* aarch64 (arm64)

## Using APT

Add package source:

```bash
# make sure the tools needed to add the repo exist
sudo apt-get update
sudo apt-get install -y curl gpg

# add the homebridge gpg key
curl -sSfL https://repo.homebridge.io/KEY.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/homebridge.gpg  > /dev/null

# add the homebridge repo
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io stable main" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
```

Update and install:

```bash
sudo apt-get update
sudo apt-get install homebridge
```

Remove:

```
sudo apt-get remove homebridge
```

Purge (this will delete `/var/lib/homebridge`):

```
sudo apt-get purge homebridge
```

## Manual Install

Download the correct file for your system from https://github.com/homebridge/homebridge-apt-pkg/releases/latest

```
dpkg -i homebridge_x.x.x_xxxx.deb
```

Remove:

```
dpkg --remove homebridge
```

Purge (this will delete `/var/lib/homebridge`):

```
dpkg --purge homebridge
```

## Updating / Downgrading

### To install the latest version

To update Homebridge, Homebridge UI and NodeJS when installed via this APT package, run:

```bash
sudo apt update
sudo apt install homebridge
```

This will upgrade all related components managed by this package.

⚠️ Your configuration files and plugins are stored in /var/lib/homebridge and will not be affected by updates.

### Downgrading to a previous release

Downgrading will return NodeJS, Homebridge and the Homebridge UI to the version bundled within the apt package. You can view the release manifest of older versions from this page on GitHub - https://github.com/homebridge/homebridge-apt-pkg/releases

If you need to install an older version or previous release of Homebridge:

```bash
sudo apt update
apt list -a homebridge  # Shows available versions
sudo apt install homebridge=<version>
```

NOTE: apt versions do not start with a v, while the verion on GitHub starts with v
## About

This package contains a self-contained Node.js installation and environment for Homebridge to run in.

The bundled Node.js runtime is isolated and not exposed on the default PATH.

To assist in debugging, a shell command `hb-shell` is added to the default PATH to allow the user to enter the Homebridge Shell Environment. When in the Homebridge Shell, users will have access to `node` and `npm` as they would expect.

```shell
# Node.js and package scripts are stored in /opt/homebridge

/opt/homebridge # This directory is managed by the homebridge apt package and the contents are overwritten during updates
  |-- bin
  |   |-- node
  |   |-- npm 
  |   |-- npx
  |-- lib
  |   |-- node_modules
  |       |-- npm
  |       |-- homebridge-config-ui-x
  |-- bashrc
  |-- bashrc-hb-shell
  |-- CHANGELOG.md
  |-- hb-shell
  |-- homebridge_apt_pkg_....manifest
  |-- LICENSE
  |-- README.md
  |-- source.sh
  |-- start.sh

# "hb-shell" command to allow user access to the Homebridge env from the cli
/usr/local/bin # These links are managed by the homebridge apt package and the contents are overwritten during updates
  |-- hb-service -> /opt/homebridge/hb-service-shim
  |-- hb-shell -> /opt/homebridge/hb-shell

# homebridge storage directory, plugins are stored in node_modules
/var/lib/homebridge
  |-- node_modules
  |   |-- homebridge
  |   |-- homebridge-dummy
  |   |-- homebridge-hue
  |-- accessories
  |-- persist
  |-- config.json
```

## Customising Homebridge

### Environment Variables

The Homebridge systemd service will automatically load any environment variables defined in `/etc/default/homebridge`.

This file can be used to customize the behavior of Homebridge or its plugins at runtime.

After making changes to the file, please use `Restart HB Service & UI` for your changes to be picked up.

#### Example

To disable the terminal feature in the Homebridge UI, add the following:

```bash
# /etc/default/homebridge
HOMEBRIDGE_CONFIG_UI_TERMINAL=0
```
### Customising the Systemd Service File

You should not edit the service file included with the package as any changes made here will be overwritten during updates.

You should use a systemd override file to make any changes.

To preview the current unit file run:

```bash
cat /lib/systemd/system/homebridge.service
```

Use systemctl to create an override file at `/etc/systemd/system/homebridge.service.d/override.conf`:

```bash
sudo systemctl edit homebridge
```

Add the config items you want to override. **You should only add the settings you want to change.**

For example, to change the user the service runs as:

```bash
[Service]
User=pi    # replace with the user you want to run the service as
```

Or to add additional startup flags to Homebridge:

```bash
[Service]
ExecStart=
ExecStart=/opt/homebridge/start.sh -T
```

Or to run as root, and allow the UI to shutdown/restart the host:

```
[Service]
User=root
ExecStart=
ExecStart=/opt/homebridge/start.sh --allow-root
Environment="UIX_CAN_SHUTDOWN_RESTART_HOST=1"
```

Save the file and restart Homebridge:

```bash
sudo systemctl restart homebridge
```

To revert any changes run:

```bash
sudo systemctl revert homebridge
```

## Beta Builds

Beta builds of the homebridge package are supplied with the latest beta versions of Homebridge and Homebridge UI.

### Installing Beta Version via APT

Add package source:

```bash
# make sure the tools needed to add the repo exist
sudo apt-get update
sudo apt-get install -y curl gpg

# add the homebridge gpg key
curl -sSfL https://repo.homebridge.io/KEY.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/homebridge.gpg  > /dev/null

# add the homebridge repo
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io beta main" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
```

Update and install:

```bash
sudo apt-get update
sudo apt-get install homebridge
```

## Packaging Notes

Package scripts workflow (preinst, postinst, postrm etc.):

https://wiki.debian.org/MaintainerScripts

## License

Copyright (C) 2025 homebridge

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.
