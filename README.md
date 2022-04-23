# Debian Package For Homebridge

This is a debian package for Homebridge.

```bash
curl -s --compressed "https://oznu.github.io/ppa/KEY.gpg" | sudo apt-key add -
echo "deb https://oznu.github.io/ppa ./" | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null
```

```bash
sudo apt-get update
sudo apt-get install homebridge
```