#!/bin/bash

# Find the ALSA mixer control
regex="name='([[:print:]]+)'"
alsa_ctl=$(amixer -D default controls)
if [[ $alsa_ctl =~ $regex ]]; then
  mixer_name="${BASH_REMATCH[1]}"
else
  echo "ERROR: Unable to find default ALSA mixer."
  exit 1
fi
echo "Using ALSA mixer control: ${mixer_name}"

# Find the input device for USB HID Consumer Control
usb_hid_cc_dev=$(ls /dev/input/by-id/usb-Pimoroni_Tiny_2040__2MB__*-event-if03)
if [ -z $usb_hid_cc_dev ]; then
  echo "ERROR: Unable to find the USB HID Consumer Control input device ${usb_hid_cc_dev}"
  exit 2
fi
echo "Using USB HID CC device: ${usb_hid_cc_dev}"

regex='Event:[[:space:]]+time[[:space:]]+[[:digit:]]+\.[[:digit:]]+,[[:space:]]+type[[:space:]]+[[:digit:]]+[[:space:]]+\(EV_KEY\),[[:space:]]+code[[:space:]]+([[:digit:]]+)[[:space:]]+\(([[:upper:]_]+)\),[[:space:]]+value[[:space:]]+1'
evtest "${usb_hid_cc_dev}" | while read line; do
  if [[ $line =~ $regex ]]; then
    key_code="${BASH_REMEATCH[1]}"
    key_str="${BASH_REMATCH[2]}"
    if [[ "${key_str}" == "KEY_VOLUMEUP" ]]; then
      amixer set "${mixer_name}" 2+ &> /dev/null
    elif [[ "${key_str}" == "KEY_VOLUMEDOWN" ]]; then
      amixer set "${mixer_name}" 2- &> /dev/null
    fi
  fi
done
