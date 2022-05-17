# ALSA Volume From USB HID #

## Overview ##
This is a small script-based daemon for Linux systems using the Advanced Linux Sound Architecture ([ALSA](https://alsa-project.org/wiki/Main_Page)) to allow [USB HID](https://www.usb.org/hid) 'Consumer Control' volume events to adjust the ALSA mixer volume.

As far as I know, this should 'just work' for the default ALSA playback device without the need for this daemon. However, it seems some ALSA configurations break this. In my case I was using the [ALSA SoftVol](https://alsa.opensrc.org/Softvol) plugin to enable a volume control for an [Adafruit MAX98357 I2S Class-D Mono Amp](https://learn.adafruit.com/adafruit-max98357-i2s-class-d-mono-amp?view=all) PCM device which has no volume control itself.

The daemon installs as a [systemd](https://www.linux.com/training-tutorials/understanding-and-using-systemd/) service, and uses [udev](https://www.linux.com/news/udev-introduction-device-management-modern-linux-system/) rules to start/stop the service when the selected USB HID device is plugged in or removed.

## Usage ##
The script uses the default ALSA playback mixer control.

You may wish to edit the script (`src/alsa_vol)from_usb_hid.sh`) and udev rules file (`config/etc/udev/rules.d/80-alsa-vol-from-usb-hid.rules`) to choose attributes to match your USB HID device. It's currently hardcoded for a [2MB Pimoroni Tiny2040](https://shop.pimoroni.com/products/tiny-2040?variant=39560012300371) which is what I am using.

### Installation

To install:
```sh
sudo make install
```
To uninstall:
```sh
sudo make uninstall
```
