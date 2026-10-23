"""Command line: ``serve`` (the GATT proxy for the app) and ``probe`` (read-only look at a trainer).

    python -m trainer_bridge serve [--port 8765]
    python -m trainer_bridge probe [--seconds 30] [--address AA:BB:...] [--allow-control]
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from typing import Optional, Sequence

from . import __version__
from .backend import BleakBackend, bleak_available
from .server import DEFAULT_PORT


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="trainer_bridge", description="Wattlands trainer bridge (BRIEF 4.2)")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="command", required=True)
    s = sub.add_parser("serve", help="run the GATT proxy on ws://127.0.0.1:<port>")
    s.add_argument("--port", type=int, default=DEFAULT_PORT)
    pr = sub.add_parser("probe", help="scan, read features and ranges, print Indoor Bike Data (read-only)")
    pr.add_argument("--seconds", type=float, default=30.0, help="how long to print bike data (default 30)")
    pr.add_argument("--address", default=None, help="trainer address (default: the first FTMS trainer found)")
    pr.add_argument("--scan-seconds", type=float, default=10.0)
    pr.add_argument("--allow-control", action="store_true",
                    help="also send Request Control and SIM flat, after a typed confirmation")
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if not bleak_available():
        print("trainer_bridge: bleak is not installed; install it with 'pip install bleak websockets'",
              file=sys.stderr)
        return 2
    try:
        if args.command == "serve":
            from .server import serve

            asyncio.run(serve(BleakBackend(), port=args.port, backend_factory=BleakBackend))
            return 0
        from .probe import run_probe

        return asyncio.run(run_probe(BleakBackend(), seconds=args.seconds, address=args.address,
                                     allow_control=args.allow_control, scan_seconds=args.scan_seconds))
    except KeyboardInterrupt:
        return 130
