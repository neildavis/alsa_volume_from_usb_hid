import logging, subprocess
from time import sleep
from enum import Enum
from argparse import ArgumentParser, Namespace
from  alsaaudio import Mixer, mixers, ALSAAudioError, PCM_PLAYBACK, MIXER_CHANNEL_ALL
from  evdev import InputDevice, ecodes, list_devices, categorize, KeyEvent

class PowerOffException(Exception):
    '''
    PowerOffException is raised in response to a KEY_POWER event to terminate the evdev event read loop
    '''
    pass

class ErrorExitCode(Enum):
    '''
    ErrorExitCode is an enumerated type for valid exit codes
    '''
    ERROR_NONE              = 0
    ERROR_NO_ALSA_MIXER     = 1

'''
valid_playback_volume_caps lists all possible valid ALSA volume caps that a mixer control may use for playback volume
'''
valid_playback_volume_caps = ['Volume', 'Joined Volume', 'Playback Volume', 'Joined Playback Volume']
'''
valid_playback_mute_caps lists all possible valid ALSA switch caps that a mixer control may use for playback muting
'''
valid_playback_mute_caps = ['Mute', 'Joined Mute', 'Playback Mute', 'Joined Playback Mute']

'''
muted_vol is used to store the volume when using a simulated mute
'''
muted_vol = 0

def parse_args() -> Namespace:
    '''
    parse_args sets up argparse to parse command line args and provide usage/help info
    '''
    parser = ArgumentParser(
        description='Adjust ALSA mixer volume from USB HID Consumer Control device events'
    )
    parser.add_argument('-d', '--alsa-dev',
        default='default',
        help='ALSA device to use, e.g. "hw:0" (uses \'default\' device if not specified)'
    )
    parser.add_argument('-c', '--alsa-ctrl',
        help='ALSA control to use, e.g. "Master" (defaults to first playback capable control on the device)'
    )
    parser.add_argument('-i', '--input-dev',
        help='Device to use for USB input (defaults to first USB HID device found under /dev/input/)'
    )
    parser.add_argument('-v', '--volume-delta',
        type=int,
        choices=list(range(0,26,5))[1:],
        default=10,
        help='Set the volume delta increments/decrements as a percentage (default=10%%)'
    )
    parser.add_argument('-p', '--power-off-cmd',
        help='Command to execute uppon receiving a KEY_POWER event (default=None)'
    )
    parser.add_argument('-l', '--log-level',
        choices=['critical', 'error', 'warning', 'info', 'debug'],
        default='info',
        help='Set the logging level (default=\'info\')'
    )
    return parser.parse_args()

def setup_logging(args : Namespace):
    '''
    setup_logging initializes our logging framework
    '''
    logging.basicConfig(level=getattr(logging, args.log_level.upper()))


def print_mixer(mixer: Mixer):
    '''
    print_mixer is a debug helper to print out some ALSA mixer info
    '''
    logging.debug(f'''
    Mixer '{mixer.mixer()}' with ID {mixer.mixerid()} on card '{mixer.cardname()}'
        Volume caps: {mixer.volumecap()}
        Switch caps: {mixer.switchcap()}
        Enum ctrls:  {mixer.getenum()}
    ''')

def mixer_supports_playback_volume(mixer: Mixer) -> bool:
    '''
    mixer_supports_playback_volume determines if an ALSA mixer supports a playback volume capability
    '''
    mixer_playback_volume_caps = [val for val in mixer.volumecap() if val in valid_playback_volume_caps]
    if len(mixer_playback_volume_caps) > 0:
        return True
    return False

def mixer_supports_playback_mute(mixer: Mixer) -> bool:
    '''
    mixer_supports_playback_mute determines if an ALSA mixer supports a native playback muting capability
    '''
    mixer_playback_mute_caps = [val for val in mixer.switchcap() if val in valid_playback_mute_caps]
    if len(mixer_playback_mute_caps) > 0:
        return True
    return False

def get_alsa_mixer(args : Namespace) -> Mixer:
    '''
    get_alsa_mixer tries to find an ALSA mixer based on argparse'd command line args
    '''
    mixer_ret = None
    try:
        if None == args.alsa_ctrl:
            # No Mixer control was specified, find the first one on the device that supports playback volume
            for mixer_control in mixers(device=args.alsa_dev):
                mixer = Mixer(device=args.alsa_dev, control=mixer_control)
                #print_mixer(mixer)
                if mixer_supports_playback_volume(mixer):
                    mixer_ret = mixer
                    break
        else:
            # Mixer control was specified on command line so try to use it
            mixer_ret = Mixer(device=args.alsa_dev, control=args.alsa_ctrl)
            #print_mixer(mixer_ret)
            if not mixer_supports_playback_volume(mixer_ret):
                logging.error(f'ALSA mixer \'{mixer_ret.mixer()}\' on card \'{mixer_ret.cardname()}\' does not support playback volume control')
                mixer_ret = None
    except ALSAAudioError as alsa_err:
        mixer_ret = None
        logging.error(alsa_err)
    return mixer_ret

def input_device_supports_volume_control(input_dev: InputDevice) -> bool:
    '''
    input_device_supports_volume_control determines if an input device supports volume control
    This means it reports EV_KEY events including KEY_VOLUMEUP (we assume they also report KEY_VOLUMEDOWN)
    '''
    key_caps = input_dev.capabilities().get(ecodes.EV_KEY)
    return key_caps != None and ecodes.KEY_VOLUMEUP in key_caps

def get_usb_hid_input(args : Namespace) -> InputDevice:
    '''
    get_usb_hid_input tries to find a USB HID input device capable of adjusting volume
    '''
    input_dev_ret = None
    try:
        if None == args.input_dev:
            # No input device was specified. Try to find a USB HID device that supports volume control events
            input_devices = [InputDevice(path) for path in list_devices()]
            # filter all input devices to those that are HID capable (bus type == 3) and report volume key events
            hid_devices = [dev for dev in input_devices if dev.info.bustype == 3 and input_device_supports_volume_control(dev)]
            if len(hid_devices) > 0:
                input_dev_ret = hid_devices[0]
        else:
            # Input device was specified on command line so try to use it
            input_dev_ret = InputDevice(args.input_dev)
            if not input_device_supports_volume_control(input_dev_ret):
                logging.warning(f'Input device at {input_dev_ret.path} ({input_dev_ret.name}) does not appear to support volume control events')
    except FileNotFoundError:
        input_dev_ret = None
        logging.debug(f'Input device at {args.input_dev} not found')
    except PermissionError as perm_err:
        # Get this sometimes on reconnecting. Looks like a race condition. Just return nothing and wait for retry
        input_dev_ret = None
        logging.debug(perm_err)
    return input_dev_ret

def alsa_volume_delta(mixer: Mixer, delta: int):
    '''
    alsa_volume_delta changes the ALSA mixer volume by delta %
    '''
    current_vol = mixer.getvolume(pcmtype=PCM_PLAYBACK)[0]
    new_vol = max(0, min(100, current_vol + delta))
    logging.debug(f'Volume change: deta={delta} {current_vol} -> {new_vol}')
    mixer.setvolume(new_vol, channel=MIXER_CHANNEL_ALL, pcmtype=PCM_PLAYBACK)

def asla_mute_toggle(mixer: Mixer):
    '''
    asla_mute_toggle toggles the muted status of the ALSA mixer
    '''
    if mixer_supports_playback_mute(mixer=mixer):
        # This mixer has a native 'mute' switch, so use it
        current_mute=mixer.getmute()[0]
        new_mute=int(not bool(current_mute))
        logging.debug(f'Native MUTE switch change: {current_mute} -> {new_mute}')
        mixer.setmute(new_mute)
    else:
        # This mixer does not have a native 'mute' switch so we simlulate a [un]mute via volume level
        global muted_vol
        current_vol = mixer.getvolume(pcmtype=PCM_PLAYBACK)[0]
        new_vol = current_vol
        # Criteria for being able to mute:
            # 1. We don't have a value stored for when volume was muted (muted_vol) 
            # 2. Current volume is not zero
        if 0 == muted_vol and 0 != current_vol:
            muted_vol = current_vol
            new_vol = 0
        # Criteria for being able to unmute:
            # 1. We have a value stored for when volume was muted (muted_vol) 
            # 2. Current volume is zero
        elif 0 != muted_vol and 0 == current_vol:
            new_vol = muted_vol
            muted_vol = 0
        logging.debug(f'Simulated MUTE volume change: {current_vol} -> {new_vol}')
        mixer.setvolume(new_vol, channel=MIXER_CHANNEL_ALL, pcmtype=PCM_PLAYBACK)

def on_power_off(power_off_cmd: str):
    '''
    on_power_off() is called in response to a PowerOffException
    '''
    logging.debug(f'KEY_POWER event received')
    if power_off_cmd != None:
        logging.debug(f'Executing power_off_cmd=\'{power_off_cmd}\'')
        subprocess.run(args=power_off_cmd, shell=True)
    else:
        logging.debug('No power_off_cmd to execute')

def do_event_loop(input_dev: InputDevice, mixer: Mixer, volume_delta: int):
    '''
    do_event_loop contains the main kernel event handler loop to process evdev events
    '''
    for event in input_dev.read_loop():
        if event.type == ecodes.EV_KEY:
            key_event = categorize(event)
            if key_event.keystate != KeyEvent.key_up:
                logging.debug(f'Received key code {key_event.scancode} ({key_event.keycode})')
                if key_event.scancode == ecodes.KEY_VOLUMEUP:
                    alsa_volume_delta(mixer, volume_delta)
                elif key_event.scancode == ecodes.KEY_VOLUMEDOWN:
                    alsa_volume_delta(mixer, -volume_delta)
                elif key_event.scancode == ecodes.KEY_MUTE:
                    asla_mute_toggle(mixer)
                elif key_event.scancode == ecodes.KEY_POWER:
                    raise(PowerOffException())


def start():
    '''
    start is the main function to start the daemon
    '''
    # Parse command line args    
    args = parse_args()

    # Setup logging
    setup_logging(args)

    # Acquire ALSA mixer control
    mixer = get_alsa_mixer(args)
    if None == mixer:
        logging.error('No ALSA mixer playback volume control available')
        exit(code=ErrorExitCode.ERROR_NO_ALSA_MIXER)
    logging.info(f'Using ALSA mixer \'{mixer.mixer()}\' on card \'{mixer.cardname()}\' for playback volume control')

    # loop forever until we find an input device
    while True:
        # Acquire USB HID input device
        input_dev = get_usb_hid_input(args)
        if None == input_dev:
            sleep(1.0)
            continue
        logging.info(f'Using USB HID input device at {input_dev.path} ({input_dev.name})')

        # Start main event loop
        try:
            do_event_loop(input_dev=input_dev, mixer=mixer, volume_delta=args.volume_delta)
        except OSError:
            logging.info(f'Lost connection to USB HID input device at {input_dev.path} ({input_dev.name})')
        except PowerOffException:
            on_power_off(args.power_off_cmd)
            break


if __name__ == "__main__":
    try:
        start()
    except KeyboardInterrupt:
        logging.info('Terminating due to KeyboardInterrupt')
        pass