# ALSA Volume From USB HID #

## Overview ##
This is a small Python based daemon for Linux systems using the Advanced Linux Sound Architecture ([ALSA](https://alsa-project.org/wiki/Main_Page)) to allow [USB HID](https://www.usb.org/hid) 'Consumer Control' volume events to adjust the ALSA mixer volume. These events are typically sent by USB peripheral devices like keyboards which include volume controls. 

As far as I know, this should 'just work' without the need for this daemon, and indeed this is the case on most modern Linux Desktops.
However, it seems some environments and/or ALSA configurations break this,
or are otherwise not supported. e.g. minimal CLI systems.
In my case I was using a Raspberry Pi in CLI boot mode with the [ALSA SoftVol](https://alsa.opensrc.org/Softvol) plugin to enable a volume control for an [Adafruit MAX98357 I2S Class-D Mono Amp](https://learn.adafruit.com/adafruit-max98357-i2s-class-d-mono-amp?view=all) PCM device which has no volume control itself.

The daemon installs as a [systemd](https://www.linux.com/training-tutorials/understanding-and-using-systemd/) service.

## Usage ##

### Prerequisites
Since the daemon runs using [Python](https://www.python.org/) we need to setup the Python environment. In particular we require Python version 3, not the deprecated Python 2. Most modern Linux distros include Python3 by default, but the commands below will install it if it's missing.

These commands are for [Debian](https://www.debian.org/) based Linux distros  (e.g. [Ubuntu](https://ubuntu.com/), [Linux Mint](https://linuxmint.com/) and [Raspberry Pi OS](https://www.raspberrypi.com/documentation/computers/os.html)) using the Debian [`apt` package manager](https://wiki.debian.org/Apt). If you are using a non-Debian system you will need to find the best way to install these packages using your system.

A note on Python versions.
Debian repositories tend to lag Python versions, sometimes by a number of years! If you want to use the latest/greatest version of Python 3 I'm assuming you know how to build/install it for your system.
I'm not sure what the absolute minimum version of Python is required to run the daemon, but I have tested on v3.7.3 which dates to early 2019 and is included in [Debian 10 ('Buster')](https://www.debian.org/releases/buster/)

Along with the base Python language & runtime support, we will need a few more tools. Namely:

* [pip](https://pypi.org/project/pip/) for easy Python package management
* [venv](https://docs.python.org/3/library/venv.html) to create virtual Python environments.

    ```shell 
    sudo apt install python3 python3-pip python3-venv
    ```

### Running manually ###
You can run daemon manually in a terminal using the steps below.
However most of the time you will want the daemon to install and start automatically instead of starting it manually like this. In that case, skip the rest of this section and see the following sections below including:
* ['Identifying ALSA cards and mixers'](#Identifying-ALSA-cards-and-mixers)
* ['Identifying USB HID input devices](#Identifying-USB-HID-input-devices)
* ['Installation'](#installation])

But back to running manually in a terminal:

1. Create & activate a new Python virtual environment (venv). This step is optional but recommended, to avoid polluting your system's base Python environment with otherwise unnecessary packages. 
    ```shell 
    python3 -m venv env
    source env/bin/activate
    ```
    The first line to create the venv only has to be done once, although you will need to activate the env each time you login with the second line.
2. Install some Python library dependencies using pip. in particular we require:
    * [evdev](https://python-evdev.readthedocs.io/en/latest/) - for receiving USB HID events from the Linux kernel.
    * [pyalsaaudio](https://larsimmisch.github.io/pyalsaaudio/) - for controlling ALSA audio mixers.
    ```shell 
    pip install evdev pyalsaaudio
    ```
    Again, this only has to be done once.
3. Add your user to the `input` group if necessary. This is required to allow the daemon to receive Linux evdev input events from USB HID devices. First check to see if your user is already in the `input` group:
    ```shell 
    groups
    ```
    This command will display all of the groups your user is a member of. if you see `input` listed in the results you're all set. If not, you need to add your user to the `input` group using this command:
    ```shell 
    sudo usermod -a -G input $USER
    ```
    You will need to log out and log in again (or reboot) for this change to take effect. Again, this only has to be done once.
4. Finally, run the daemon. Without any args it will try to find the best ALSA mixer device and USB HID device automatically. These, and other options can be specified manually on the command line with the `-h` flag. See the help for details:
```shell
    python3 src/alsa_vol_from_usb_hid.py -h
    usage: alsa_vol_from_usb_hid.py [-h] [-d ALSA_DEV] [-c ALSA_CTRL]
                                    [-i INPUT_DEV] [-v {5,10,15,20,25}]
                                    [-l {critical,error,warning,info,debug}]

    Adjust ALSA mixer volume from USB HID Consumer Control device events

    optional arguments:
    -h, --help            show this help message and exit
    -d ALSA_DEV, --alsa-dev ALSA_DEV
                            ALSA device to use, e.g. "hw:0" (uses 'default' device
                            if not specified)
    -c ALSA_CTRL, --alsa-ctrl ALSA_CTRL
                            ALSA control to use, e.g. "Master" (defaults to first
                            playback capable control on the device)
    -i INPUT_DEV, --input-dev INPUT_DEV
                            Device to use for USB input (defaults to first USB HID
                            device found under /dev/input/)
    -v {5,10,15,20,25}, --volume-delta {5,10,15,20,25}
                            Set the volume delta increments/decrements as a
                            percentage (default=10%)
    -l {critical,error,warning,info,debug}, --log-level {critical,error,warning,info,debug}
                            Set the logging level (default='info')
```
Press CTRL+C to exit.

### Identifying ALSA cards and mixers ###
Without any `-d` argument, the daemon will attempt to use the '`default`' ALSA device.
This is often a 'virtual device' with a 'Master' mixer control and exactly what you want!
However, sometimes the default behaviour isn't what you want and you need to override this.

The `-d` option will allow you to specify the ALSA device to use. But how do you find these?
Well, to get a list of all sound-card devices on the system you can use this command:
```shell
cat /proc/asound/cards
```
This will produce output something like this:
```shell
0 [Headphones     ]: bcm2835_headpho - bcm2835 Headphones
                      bcm2835 Headphones
1 [T20402MB       ]: USB-Audio - Tiny 2040 (2MB)
                      Pimoroni Tiny 2040 (2MB) at usb-0000:01:00.0-1.3, full speed
``` 
The number of cards and their details will vary wildly based on your system hardware
and what devices you have plugged in, but what's important is the 'card index' number
on the left. Make a note of this index number for the device you want to use.

Once you know the 'card index' of the device you can simply pass this as an option
to the daemon using the `-d` argument like this:
```shell
python3 src/alsa_vol_from_usb_hid.py -d hw:N
```
where `N` is the card index, e.g. if I wanted to use the BCM2835 headphones output
I would use `hw:0`

Without any `-c` argument, the daemon will look for a suitable 'playback' control
on the specified card and use the first one it finds.
Again, this default behaviour may be exactly what you want, but you have the option
to override this.

You can find a list of the 'simple mixer controls' on your chosen card with a command
like this:
```shell
amixer -D hw:0 scontrols
```
Again, substitute `hw:0` with your chosen device id as above. This will list the 
available mixer controls in a format something like this:
```shell
Simple mixer control 'Headphone',0
```
Again, your output will vary. I have only one result here but you may have more.
The important bit is the name in quotes after '`Simple mixer control`',
i.e. '`Headphone`' which is the name of the ALSA mixer control you use with `-c` e.g.
```shell
python3 src/alsa_vol_from_usb_hid.py -d hw:0 -c Headphone
```

### Identifying USB HID input devices ###
Without any `-i` argument, the daemon will attempt to find a suitable input device automatically.
It does this by iterating all available USB input devices which identify themselves as
'device class 3' which corresponds to USB HID devices. These are further queried to find those
which declare a capability to send the relevant volume events:
(`KEY_VOLUMEUP`, `KEY_VOLUMEDOWN`, `KEY_MUTE`)

You can manually select an input device by passing its path using `-c` e.g.
```shell
python3 src/alsa_vol_from_usb_hid.py -c /dev/input/event2
```
To find the input device you want, you may try looking at the output of this command
before and after adding & removing the device:
```shell
ls -l /dev/input/by-id
```
For example, my Raspberry Pi which has a Logitech Gamepad and an Apple keyboard attached lists these:
```shell
total 0
lrwxrwxrwx 1 root root 9 Dec  8 14:08 usb-Apple_Inc._Apple_Keyboard-event-if01 -> ../event4
lrwxrwxrwx 1 root root 9 Dec  8 14:08 usb-Apple_Inc._Apple_Keyboard-event-kbd -> ../event3
lrwxrwxrwx 1 root root 9 Dec  8 11:08 usb-Logitech_Logitech_Dual_Action_D4BEAFFB-event-joystick -> ../event0
lrwxrwxrwx 1 root root 6 Dec  8 11:08 usb-Logitech_Logitech_Dual_Action_D4BEAFFB-joystick -> ../js0
```
If I wanted to use the Apple keyboard I would try to use `/dev/input/event3` or `/dev/input/event4`
and see which works. (Spoiler: it's `event4`)

### Installation

To install with automatic ALSA device/control & USB HID device selection
```sh
sudo make install
```
To install specifying any additional command line args as described above, pass `ARGS` to make. e.g:
```sh
sudo make install ARGS="-d hw:0 -c Headphone -v 5 -l warning"
```
To uninstall:
```sh
sudo make uninstall
```
