# Debian Package For Homebridge

[![GitHub release (latest by date)](https://badgen.net/github/release/homebridge/homebridge-apt-pkg?label=Version)](https://github.com/homebridge/homebridge-apt-pkg/releases/latest)
[![GitHub All Releases](https://img.shields.io/github/downloads/homebridge/homebridge-apt-pkg/total)](https://somsubhra.github.io/github-release-stats/?username=homebridge&repository=homebridge-apt-pkg&page=1&per_page=30)

This project builds and publishes a debian-based package that can be installed using `apt` on Ubuntu / Debian / Raspberry Pi OS based Linux systems.

The project aims to deploy Homebridge and the Homebridge UI in a secure and stable way, with no dependencies outside those available in the standard distribution repos. It comes bundled with its own Node.js runtime and runs Homebridge in an isolated environment as a service user with no sudo / admin privileges.

Supported architectures:

* x86_64 (64-bit Intel/AMD)
* armhf (armv7) - 32-bit ARM (⚠️ **Node.js version limited to ≤22**)
* aarch64 (arm64) - 64-bit ARM

**Important:** Node.js dropped 32-bit support starting with version 23. The 32-bit ARM (armhf) packages are limited to Node.js 22.x and earlier. Support for 32-bit operating systems will end in Spring of 2027, when Node.js 22 reaches its end of life.

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

Remove (keeps `/var/lib/homebridge`: your config and the list of your plugins. The plugins are installed again if you install the package again):

```
sudo apt-get remove homebridge
```

Purge (this will delete `/var/lib/homebridge`):

```
sudo apt-get purge homebridge
```

A purge does not remove the `homebridge` user and group, `/home/homebridge`, `/etc/default/homebridge`, a systemd override in `/etc/systemd/system/homebridge.service.d/`, or a firewall rule that was added for the UI port.

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

NOTE: apt versions do not start with a v, while the version on GitHub starts with v

#### How many older versions are kept

* The apt repository does not keep every old version. `apt list -a homebridge` shows the versions it offers right now. As a rule you can count on the newest 3 stable versions, and the newest 2 versions of the beta, alpha and legacy channels.
* Every stable release stays on the [GitHub releases page](https://github.com/homebridge/homebridge-apt-pkg/releases). To go back further than the apt repository allows, download the `.deb` file for your system there and install it with `sudo apt install ./homebridge_<version>_<arch>.deb`.
* For beta, alpha and legacy only the newest 15 releases are kept on GitHub.
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
  |-- CHANGELOG.md     # these three files are the ones of Node.js itself
  |-- LICENSE
  |-- README.md
  |-- bashrc
  |-- bashrc-hb-shell
  |-- hb-service-shim
  |-- hb-shell
  |-- homebridge_apt_pkg_....manifest
  |-- package.json     # the Node.js, Homebridge and UI versions this package was built with
  |-- rebuild-package-json.sh
  |-- source.sh
  |-- start.sh

# the "hb-service" and "hb-shell" commands
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

## Alpha Builds

Alpha builds of the homebridge package are supplied with the latest alpha versions of Homebridge and Homebridge UI for testing new features before they reach beta.

⚠️ **Warning**: Alpha builds are experimental and may contain bugs or unstable features. Use only for testing purposes.

### Installing Alpha Version via APT

Add package source:

```bash
# make sure the tools needed to add the repo exist
sudo apt-get update
sudo apt-get install -y curl gpg

# add the homebridge gpg key
curl -sSfL https://repo.homebridge.io/KEY.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/homebridge.gpg  > /dev/null

# add the homebridge repo
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io alpha main" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
```

Update and install:

```bash
sudo apt-get update
sudo apt-get install homebridge
```

## Legacy Builds

The `legacy` channel is for systems that must stay on Homebridge 1.x. It ships the last Homebridge 1.x release with the current Homebridge UI, on a Node.js version that Homebridge 1.x supports.

To use it, add the package source as shown under "Using APT", with `legacy` in place of `stable`:

```bash
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io legacy main" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
```

## Packaging Notes

How this package is built, tested and released: [BUILD.md](./BUILD.md)

Package scripts workflow (preinst, postinst, postrm etc.):

https://wiki.debian.org/MaintainerScripts

## License

Copyright (C) 2022-2026 homebridge

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.
