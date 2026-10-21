"""PyInstaller entry point (trainer_bridge.spec): the same CLI as ``python -m trainer_bridge``."""

import sys

from trainer_bridge.cli import main

if __name__ == "__main__":
    sys.exit(main())
