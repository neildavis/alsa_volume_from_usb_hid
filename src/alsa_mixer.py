import logging
from typing import Optional
from alsaaudio import Mixer, PCM_PLAYBACK, MIXER_CHANNEL_ALL

valid_playback_volume_caps = ['Volume', 'Joined Volume', 'Playback Volume', 'Joined Playback Volume']
valid_playback_mute_caps = ['Mute', 'Joined Mute', 'Playback Mute', 'Joined Playback Mute']


class AlsaMixer:
    """Wrapper around alsaaudio.Mixer exposing helper methods via composition.

    The original attempt to subclass `alsaaudio.Mixer` fails because it's
    implemented as a native type that doesn't support subclassing, so we
    hold a private `Mixer` instance instead and provide the convenience
    methods used by the daemon.
    """
    def __init__(self, device: str = 'default', control: Optional[str] = None):
        self._mixer = Mixer(device=device, control=control)
        # stored volume for simulated mute/unmute
        self.muted_vol: int = 0

    # Pass-through helpers used by other modules
    def mixer(self):
        return self._mixer.mixer()

    def cardname(self):
        return self._mixer.cardname()

    # Playback helpers
    def print_info(self) -> None:
        logging.debug(f'''\
    Mixer '{self.mixer()}' with ID {self._mixer.mixerid()} on card '{self.cardname()}'
        Volume caps: {self._mixer.volumecap()}
        Switch caps: {self._mixer.switchcap()}
        Enum ctrls:  {self._mixer.getenum()}
    ''')

    def supports_playback_volume(self) -> bool:
        caps = [val for val in self._mixer.volumecap() if val in valid_playback_volume_caps]
        return len(caps) > 0

    def supports_playback_mute(self) -> bool:
        caps = [val for val in self._mixer.switchcap() if val in valid_playback_mute_caps]
        return len(caps) > 0

    def get_playback_volume(self) -> int:
        return self._mixer.getvolume(pcmtype=PCM_PLAYBACK)[0]

    def set_playback_volume(self, value: int) -> None:
        self._mixer.setvolume(value, channel=MIXER_CHANNEL_ALL, pcmtype=PCM_PLAYBACK)

    def change_playback_volume(self, delta: int) -> None:
        current_vol = self.get_playback_volume()
        new_vol = max(0, min(100, current_vol + delta))
        logging.debug(f'Volume change: delta={delta} {current_vol} -> {new_vol}')
        self.set_playback_volume(new_vol)

    def get_mute(self) -> int:
        return self._mixer.getmute()[0]

    def set_mute(self, value: int) -> None:
        self._mixer.setmute(int(bool(value)))

    def toggle_mute(self) -> None:
        """Toggle mute state. Use native mute if available, otherwise simulate via stored volume."""
        if self.supports_playback_mute():
            current_mute = self.get_mute()
            new_mute = int(not bool(current_mute))
            logging.debug(f'Native MUTE switch change: {current_mute} -> {new_mute}')
            self.set_mute(new_mute)
        else:
            # simulated mute via volume level using self.muted_vol
            current_vol = self.get_playback_volume()
            new_vol = current_vol
            if 0 == self.muted_vol and 0 != current_vol:
                self.muted_vol = current_vol
                new_vol = 0
            elif 0 != self.muted_vol and 0 == current_vol:
                new_vol = self.muted_vol
                self.muted_vol = 0
            logging.debug(f'Simulated MUTE volume change: {current_vol} -> {new_vol}')
            self.set_playback_volume(new_vol)

    def is_simulated_muted(self) -> bool:
        """Return True if this mixer is currently using a simulated mute (not native) and is muted."""
        if self.supports_playback_mute():
            return False
        try:
            return self.muted_vol != 0 and self.get_playback_volume() == 0
        except Exception:
            return False
