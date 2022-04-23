# Debian Package For Homebridge

This repo is for testing a Debian package for Homebridge.

This should work on Ubuntu / Debian based systems.

Supported architectures:

* x86_64
* i386
* arm
* aarch64

## Using APT

Add package source:

```bash
curl -s --compressed "https://oznu.github.io/ppa/KEY.gpg" | sudo apt-key add -
echo "deb https://oznu.github.io/ppa ./" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
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

You might want to remove the ppa after testing as this is only temporary:

```
rm -rf /etc/apt/sources.list.d/homebridge.list
```

## Manual Install

Download from https://github.com/oznu/deb-pkg-homebridge/releases/latest

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

## About

This package contains a self-contained Node.js installation and environment for Homebridge to run in.

The bundled Node.js runtime is isolated and not exposed on the default PATH.

To assist in debugging, a shell command `hb-shell` is added to the default PATH to allow the user to enter the Homebridge Shell Environment. When in the Homebridge Shell, users will have access to `node` and `pnpm` as they would expect.

```shell
# Node.js and package scripts are stored in /usr/lib/homebridge

/usr/lib/homebridge
  |-- bin
  |   |-- corepack
  |   |-- node
  |   |-- npm 
  |   |-- npx
  |   |-- pnpm
  |   |-- pnpx
  |-- lib
  |   |-- node_modules
  |       |-- npm
  |       |-- pnpm
  |       |-- corepack
  |-- bashrc
  |-- bashrc-hb-shell
  |-- CHANGELOG.md
  |-- hb-shell
  |-- LICENSE
  |-- README.md
  |-- source.sh
  |-- start.sh

# "hb-shell" command to allow user access to the Homebridge env from the cli
/usr/bin
  |-- hb-shell -> /usr/lib/homebridge/hb-shell

# homebridge storage directory, plugins are stored in node_modules
/var/lib/homebridge
  |-- node_modules
  |   |-- homebridge
  |   |-- homebridge-config-ui-x
  |   |-- homebridge-dummy
  |   |-- homebridge-hue
  |-- accessories
  |-- persist
  |-- config.json
```
