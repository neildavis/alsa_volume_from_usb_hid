# ALSA Volume From USB HID #

## Overview ##
This is a small script-based daemon for Linux systems using the Advanced Linux Sound Architecture ([ALSA](https://alsa-project.org/wiki/Main_Page)) to allow [USB HID](https://www.usb.org/hid) 'Consumer Control' volume events to adjust the ALSA mixer volume.

As far as I know, this should 'just work' for the default ALSA playback device without the need for this daemon. However, it seems some ALSA configurations break this. In my case I was using the [ALSA SoftVol](https://alsa.opensrc.org/Softvol) plugin to enable a volume control for an [Adafruit MAX98357 I2S Class-D Mono Amp](https://learn.adafruit.com/adafruit-max98357-i2s-class-d-mono-amp?view=all) PCM device which has no volume control itself.

The daemon installs as a [systemd](https://www.linux.com/training-tutorials/understanding-and-using-systemd/) service.

## Usage ##
### Alsa Mixer ###
The script uses the default ALSA playback mixer control. This is one returned from the following command:
```sh
amixer -D default
```

### USB HID Device ###
By default, with no other command line arguments the daemon will select the first
USB HID input device found under `/dev/input`. 
This can be overridden by specifying an alternative device when starting the daemon.
e.g. from the root of this repo:
```sh
src/alsa_vol_from_usb_hid.sh /dev/input/event1
```
However most of the time you will want the daemon to install and start automatically instead of starting it manually like this. See the ['Installation'](#installation]) section below.

### Installation

To install with automatic USB HID device selection
(the first USB HID input device found under `/dev/input`):
```sh
sudo make install
```
To install specifying a particular USB HID device (e.g. `/dev/input/event1`):
```sh
sudo make install USBHID_DEVICE=/dev/input/event1
```
To uninstall:
```sh
sudo make uninstall
```
