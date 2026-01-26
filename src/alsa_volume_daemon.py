import logging
import subprocess
from time import sleep
from typing import Optional
from evdev import InputDevice, ecodes, list_devices, categorize, KeyEvent
from alsaaudio import mixers, ALSAAudioError

from alsa_mixer import AlsaMixer


class ErrorExitCode:
    ERROR_NONE = 0
    ERROR_NO_ALSA_MIXER = 1


class AlsaVolumeDaemon:
    def __init__(self, args):
        self.args = args
        self.mixer: Optional[AlsaMixer] = None
        self.input_dev: Optional[InputDevice] = None

    def get_alsa_mixer(self) -> Optional[AlsaMixer]:
        """Find or create an AlsaMixer based on args."""
        mixer_ret = None
        try:
            if None == self.args.alsa_ctrl:
                for mixer_control in mixers(device=self.args.alsa_dev):
                    m = AlsaMixer(device=self.args.alsa_dev, control=mixer_control)
                    if m.supports_playback_volume():
                        mixer_ret = m
                        break
            else:
                mixer_ret = AlsaMixer(device=self.args.alsa_dev, control=self.args.alsa_ctrl)
                if not mixer_ret.supports_playback_volume():
                    logging.error(f"ALSA mixer '{mixer_ret.mixer()}' on card '{mixer_ret.cardname()}' does not support playback volume control")
                    mixer_ret = None
        except ALSAAudioError as alsa_err:
            mixer_ret = None
            logging.error(alsa_err)
        return mixer_ret

    def input_device_supports_volume_control(self, input_dev: InputDevice) -> bool:
        key_caps = input_dev.capabilities().get(ecodes.EV_KEY)
        return key_caps is not None and ecodes.KEY_VOLUMEUP in key_caps

    def get_usb_hid_input(self) -> Optional[InputDevice]:
        input_dev_ret = None
        try:
            if None == self.args.input_dev:
                input_devices = [InputDevice(path) for path in list_devices()]
                hid_devices = [dev for dev in input_devices if dev.info.bustype == 3 and self.input_device_supports_volume_control(dev)]
                if len(hid_devices) > 0:
                    input_dev_ret = hid_devices[0]
            else:
                input_dev_ret = InputDevice(self.args.input_dev)
                if not self.input_device_supports_volume_control(input_dev_ret):
                    logging.warning(f'Input device at {input_dev_ret.path} ({input_dev_ret.name}) does not appear to support volume control events')
        except FileNotFoundError:
            input_dev_ret = None
            logging.debug(f'Input device at {self.args.input_dev} not found')
        except PermissionError as perm_err:
            input_dev_ret = None
            logging.debug(perm_err)
        return input_dev_ret

    def handle_key_event(self, key_event) -> Optional[bool]:
        # return True to signal power-off/stop, None otherwise
        if key_event.keystate != KeyEvent.key_up:
            logging.debug(f'Received key code {key_event.scancode} ({key_event.keycode})')
            if key_event.scancode == ecodes.KEY_VOLUMEUP:
                self.mixer.change_playback_volume(self.args.volume_delta, wrap=self.args.volume_wrap)
            elif key_event.scancode == ecodes.KEY_VOLUMEDOWN:
                self.mixer.change_playback_volume(-self.args.volume_delta, wrap=self.args.volume_wrap)
            elif key_event.scancode == ecodes.KEY_MUTE:
                # Delegate mute handling to the mixer (native or simulated)
                self.mixer.toggle_mute()
            elif key_event.scancode == ecodes.KEY_POWER:
                self.on_power_off()
                return True
        return None

    def do_event_loop(self, input_dev: InputDevice) -> bool:
        for event in input_dev.read_loop():
            if event.type == ecodes.EV_KEY:
                key_event = categorize(event)
                res = self.handle_key_event(key_event)
                if res:
                    return True
        return False

    def on_power_off(self) -> None:
        logging.debug('KEY_POWER event received')
        if self.args.power_off_cmd is not None:
            logging.debug(f"Executing power_off_cmd='{self.args.power_off_cmd}'")
            subprocess.run(args=self.args.power_off_cmd, shell=True)
        else:
            logging.debug('No power_off_cmd to execute')

    def start(self) -> None:
        # Acquire ALSA mixer control
        self.mixer = self.get_alsa_mixer()
        if self.mixer is None:
            logging.error('No ALSA mixer playback volume control available')
            exit(code=ErrorExitCode.ERROR_NO_ALSA_MIXER)
        logging.info(f"Using ALSA mixer '{self.mixer.mixer()}' on card '{self.mixer.cardname()}' for playback volume control")

        # loop forever until we find an input device
        while True:
            try:
                self.input_dev = self.get_usb_hid_input()
                if self.input_dev is None:
                    sleep(1.0)
                    continue
                logging.info(f'Using USB HID input device at {self.input_dev.path} ({self.input_dev.name})')

                power_off = self.do_event_loop(self.input_dev)
                if power_off:
                    break
            except KeyboardInterrupt:
                logging.info('Terminating due to KeyboardInterrupt')
                break
            except OSError:
                logging.info(f'Lost connection to USB HID input device at {self.input_dev.path} ({self.input_dev.name})')

        # Cleanup before exit: if mixer uses simulated mute and it's currently muted, restore volume
        try:
            if self.mixer is not None and not self.mixer.supports_playback_mute():
                if self.mixer.is_simulated_muted():
                    logging.info('Simulated mute in effect; restoring volume before exit')
                    self.mixer.toggle_mute()
        except Exception as e:
            logging.debug(f'Error while clearing simulated mute on exit: {e}')
