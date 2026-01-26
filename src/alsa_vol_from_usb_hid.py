import logging
from argparse import ArgumentParser, Namespace

from alsa_volume_daemon import AlsaVolumeDaemon
 
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
    parser.add_argument('-w', '--volume-wrap',
                            action='store_true',
        help='Volume will \'wrap around\' if starting at 0%% or 100%%'
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

if __name__ == "__main__":
    args = parse_args()
    setup_logging(args)
    daemon = AlsaVolumeDaemon(args)
    daemon.start()
