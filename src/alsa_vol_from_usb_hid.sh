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

# Custom trap function that allows us to identify the signal received
trap_with_arg() {
    func="$1" ; shift
    for sig ; do
        trap "$func $sig" "$sig"
    done
}

# Function that is called from trap with signal
func_trap() {
  sig_num=$(kill -l $1)
  echo "Exiting in response to signal: ${1} (${sig_num})"
  exit $sig_num
}

# Exit on signals
trap_with_arg func_trap SIGINT SIGQUIT SIGTERM

# Forever loop
while true; do
  # Find the input device for USB HID Consumer Control
  preferred_usb_hid_cc_dev="usb-Pimoroni_Tiny_2040*-event-if03"
  echo "Looking for preferred USB HID CC device: ${preferred_usb_hid_cc_dev}"
  selected_usb_hid_cc_dev=""
  while
    selected_usb_hid_cc_dev=$(ls /dev/input/by-id/${preferred_usb_hid_cc_dev} 2> /dev/null) || true
    [[ -z "${selected_usb_hid_cc_dev}" ]]
    do sleep 1
  done
  echo "Found USB HID CC device: ${selected_usb_hid_cc_dev}"

  regex='Event:[[:space:]]+time[[:space:]]+[[:digit:]]+\.[[:digit:]]+,[[:space:]]+type[[:space:]]+[[:digit:]]+[[:space:]]+\(EV_KEY\),[[:space:]]+code[[:space:]]+([[:digit:]]+)[[:space:]]+\(([[:upper:]_]+)\),[[:space:]]+value[[:space:]]+1'
  evtest "${selected_usb_hid_cc_dev}" 2> /dev/null | while read line; do
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
  echo "Lost connection to USB HID CC device: ${selected_usb_hid_cc_dev}"
done
