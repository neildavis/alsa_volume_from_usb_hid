#!/bin/bash

# Custom trap function that allows us to identify the signal received
trap_with_arg() {
    func="$1" ; shift
    for sig ; do
        trap "$func $sig" "$sig"
    done
}

# Function that is called from trap with signal and causes us to exit
func_trap() {
  sig_num=$(kill -l $1)
  echo "Exiting in response to signal: ${1} (${sig_num})"
  exit $sig_num
}

# Exit on signals
trap_with_arg func_trap SIGINT SIGQUIT SIGTERM

# Func to find the default ALSA mixer control
get_alsa_mixer_control() {
  local regex="name='([[:print:]]+)'"
  alsa_ctl=$(amixer -D default controls)
  if [[ $alsa_ctl =~ $regex ]]; then
    mixer_name="${BASH_REMATCH[1]}"
  else
    echo "ERROR: Unable to find default ALSA mixer."
    exit 1
  fi
}

get_alsa_mixer_volume() {
  local regex='FrontLeft:([[:digit:]]+)\[([[:digit:]]+)%\]'
  amixer_out="$(amixer get ${mixer_name})"
  amixer_out="${amixer_out//[$'\t\r\n ']}"
  if [[ $amixer_out =~ $regex ]]; then
    cur_vol_abs="${BASH_REMATCH[1]}"
    cur_vol_percent="${BASH_REMATCH[2]}"
  fi
}

volume_increment() {
  # if muted, unmute
  if [[ -n "${muted_vol}" ]]; then
    volume_mute_toggle
  else
    amixer set "${mixer_name}" 2+ &> /dev/null
    get_alsa_mixer_volume
  fi
}

volume_decrement() {
  # if muted, unmute
  if [[ -n "${muted_vol}" ]]; then
    volume_mute_toggle
  else
    amixer set "${mixer_name}" 2- &> /dev/null
    get_alsa_mixer_volume
  fi
}

volume_mute_toggle() {
  # Criteria for being able to mute:
  # 1. We don't have a value stored for when volume was muted ($muted_vol) 
  # 2. Current volume is not zero

  # Criteria for being able to unmute:
  # 1. We have a value stored for when volume was muted ($muted_vol) 
  # 2. Current volume is zero

  if [[ -z "${muted_vol}" && "${cur_vol_percent}" != "0" ]]; then
    # Store the volume when it was muted to use when unmuting
    muted_vol="${cur_vol_percent}"
    # Set the volume to zero
    amixer set "${mixer_name}" 0 &> /dev/null
    get_alsa_mixer_volume
  elif [[ -n "${muted_vol}" && "${cur_vol_percent}" == "0"   ]]; then
    # Restore volume to pre-muted value
    amixer set "${mixer_name}" "${muted_vol}"% &> /dev/null
    get_alsa_mixer_volume
    # Clear stored muted volume so we can mute again
    muted_vol=
  fi
}

#
# Main
#

# Get the ALSA mixer control and current state
get_alsa_mixer_control
get_alsa_mixer_volume
echo "Using ALSA mixer control '${mixer_name}' with current volume: ${cur_vol_percent}% (${cur_vol_abs})"

# Forever loop
while true; do
  # Find the input device for USB HID Consumer Control
  preferred_usb_hid_cc_dev="usb-Pimoroni_Tiny_2040*-event-if03"
  #preferred_usb_hid_cc_dev="usb-Apple_Inc._Apple_Keyboard-event-kbd"

  echo "Looking for preferred USB HID CC device: ${preferred_usb_hid_cc_dev}"
  selected_usb_hid_cc_dev=""
  while
    selected_usb_hid_cc_dev=$(ls /dev/input/by-id/${preferred_usb_hid_cc_dev} 2> /dev/null) || true
    [[ -z "${selected_usb_hid_cc_dev}" ]]
    do sleep 1
  done
  echo "Found USB HID CC device: ${selected_usb_hid_cc_dev}"

  regex='\(EV_KEY\),code([[:digit:]]+)\(([[:upper:]_]+)\),value([[:digit:]]+)'
  evtest "${selected_usb_hid_cc_dev}" 2> /dev/null | while read line; do
    line="${line//[$'\t\r\n ']}"
    if [[ $line =~ $regex ]]; then
      key_code="${BASH_REMATCH[1]}"
      key_str="${BASH_REMATCH[2]}"
      key_val="${BASH_REMATCH[3]}"
      if [[ "${key_val}" == "0" ]]; then
        continue
      fi
      if [[ "${key_str}" == "KEY_VOLUMEUP" ]]; then
        volume_increment
      elif [[ "${key_str}" == "KEY_VOLUMEDOWN" ]]; then
        volume_decrement
      elif [[ "${key_str}" == "KEY_MUTE" ]]; then
        volume_mute_toggle
      fi
    fi
  done
  echo "Lost connection to USB HID CC device: ${selected_usb_hid_cc_dev}"
done
