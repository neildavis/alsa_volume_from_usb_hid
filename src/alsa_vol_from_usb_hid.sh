#!/usr/bin/env bash

shopt -s extglob

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

# Func to determine if a device is a valid USB HID input device
is_device_usb_hid() {
  if [[ ! -c "$1" ]]; then
    return 1 # false, not a charcter device
  fi
  local regex_bus='ID_BUS=([[:print:]]+)'
  local regex_type='ID_TYPE=([[:print:]]+)'
  udevadm_out="$(udevadm info ${1})"
  local id_bus=""
  local id_type=""
  if [[ $udevadm_out =~ $regex_bus ]]; then
    id_bus="${BASH_REMATCH[1]}"
  fi
  if [[ $udevadm_out =~ $regex_type ]]; then
    id_type="${BASH_REMATCH[1]}"
  fi
  if [[ $id_bus != "usb" ]] || [[ $id_type != "hid" ]]; then
    return 1 # false, not a USB HID device
  fi
}

# Func to find a default USB HID input device
get_preferred_usb_hid_input_device() {
  if [[ -n "$1" ]]; then
    # Preferred device was specified on the command line.
    preferred_usb_hid_cc_dev="${1}"
    return
  fi
  # Find all non-dir entiries in /dev/input and loop over them
  for input_dev in $(find /dev/input -type c | sort); do
    echo "Inspecting device ${input_dev}"
    if is_device_usb_hid "${input_dev}"; then
      preferred_usb_hid_cc_dev="${input_dev}"
      break
    fi
  done
  if [[ -z "$preferred_usb_hid_cc_dev" ]]; then
    echo "ERROR: Could not find any preferred USB HID input device"
    exit 2
  fi
}

get_alsa_mixer_volume() {
  # Get data for current ALSA default device
  alsa_ctl=$(amixer -D default)

  # Find the mixer name
  local regex="'([[:print:]]+)'"
  if [[ $alsa_ctl =~ $regex ]]; then
    mixer_name="${BASH_REMATCH[1]}"
  else
    echo "ERROR: Unable to find default ALSA mixer."
    exit 1
  fi

  # Find the valid playback channels
  regex="Playback channels:[[:blank:]]+([[:print:]]+)"
  if [[ $alsa_ctl =~ $regex ]]; then
    local IFS='-'
    read -r -a playback_channels <<< "${BASH_REMATCH[1]}"
  else
    echo "ERROR: Unable to find default ALSA playback channels."
    exit 1
  fi
 
  # Find the current volume - we only consider the first playback channel
  local sanitized_channel_name="${playback_channels[0]%%+([[:space:]])}"
  regex="${sanitized_channel_name}:[[:blank:]]+(Playback[[:blank:]]+)?(-?[[:digit:]]+)[[:blank:]]*\[([[:digit:]]+)%\]"
  if [[ $alsa_ctl =~ $regex ]]; then
    cur_vol_abs="${BASH_REMATCH[2]}"
    cur_vol_percent="${BASH_REMATCH[3]}"
  else
    echo "ERROR: Unable to get volume for ALSA playback channel: '${sanitized_channel_name}'"
    exit 1
  fi
}

volume_delta() {
  # if muted, unmute
  if [[ -n "${muted_vol}" ]]; then
    volume_mute_toggle
  else
    amixer -M sset "${mixer_name}" -- $1 &> /dev/null
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
    amixer sset "${mixer_name}" 0% &> /dev/null
    get_alsa_mixer_volume
  elif [[ -n "${muted_vol}" && "${cur_vol_percent}" == "0"   ]]; then
    # Restore volume to pre-muted value
    amixer sset "${mixer_name}" "${muted_vol}"% &> /dev/null
    get_alsa_mixer_volume
    # Clear stored muted volume so we can mute again
    muted_vol=
  fi
}

#
# Main
#

# Get the ALSA mixer control and current state
get_alsa_mixer_volume
echo "Using '${mixer_name}' as the ALSA mixer control with current volume: ${cur_vol_percent}% (${cur_vol_abs})"

# Find the input device for USB HID Consumer Control
get_preferred_usb_hid_input_device $@
echo "Using '${preferred_usb_hid_cc_dev}' as the preferred USB HID input device"

# Forever loop
while true; do

  echo "Looking for preferred USB HID CC device: ${preferred_usb_hid_cc_dev}"
  while [[ ! -e "${preferred_usb_hid_cc_dev}" ]]; do
    sleep 1
  done
  sleep 1 # The character device is made available before the device is fully mounted as USB
  # In case the device was specified by user on command line
  # rather than found by default, check that the device is valid
  if ! is_device_usb_hid "${preferred_usb_hid_cc_dev}"; then
    echo "ERROR: ${preferred_usb_hid_cc_dev} is not a valid USB HID input device"
    exit 3
  fi 
  echo "Found USB HID CC device: ${preferred_usb_hid_cc_dev}"

  regex='\(EV_KEY\),code([[:digit:]]+)\(([[:upper:]_]+)\),value([[:digit:]]+)'
  evtest "${preferred_usb_hid_cc_dev}" 2> /dev/null | while read line; do
    line="${line//[$'\t\r\n ']}"
    if [[ $line =~ $regex ]]; then
      key_code="${BASH_REMATCH[1]}"
      key_str="${BASH_REMATCH[2]}"
      key_val="${BASH_REMATCH[3]}"
      if [[ "${key_val}" == "0" ]]; then
        continue
      fi
      # echo "RECEIVED: ${key_str} (${key_code})"
      if [[ "${key_str}" == "KEY_VOLUMEUP" ]]; then
        volume_delta "5%+"
      elif [[ "${key_str}" == "KEY_VOLUMEDOWN" ]]; then
        volume_delta "5%-"
      elif [[ "${key_str}" == "KEY_MUTE" ]]; then
        volume_mute_toggle
      fi
    fi
  done
  echo "Lost connection to USB HID CC device: ${preferred_usb_hid_cc_dev}"
done
