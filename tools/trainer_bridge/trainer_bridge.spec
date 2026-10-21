# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for a one-file Windows console exe of the trainer bridge (BRIEF 4.2).
#
#   cd tools/trainer_bridge
#   uv run --with bleak --with websockets --with pyinstaller pyinstaller --noconfirm \
#       --distpath ../../build/trainer_bridge/dist --workpath ../../build/trainer_bridge/work trainer_bridge.spec
#
# Output: build/trainer_bridge/dist/trainer_bridge.exe (same commands as python -m trainer_bridge).
import os

from PyInstaller.utils.hooks import collect_submodules

here = SPECPATH  # noqa: F821 (defined by PyInstaller)

# bleak picks its backend at run time (WinRT on Windows) and websockets loads its asyncio
# implementation lazily, so neither is found by static analysis alone.
hiddenimports = []
for package in ("bleak", "winrt", "websockets"):
    try:
        hiddenimports += collect_submodules(package)
    except Exception:
        pass

a = Analysis(  # noqa: F821
    [os.path.join(here, "bridge.py")],
    pathex=[here],
    binaries=[],
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "tests"],
    noarchive=False,
)
pyz = PYZ(a.pure)  # noqa: F821
exe = EXE(  # noqa: F821
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="trainer_bridge",
    debug=False,
    strip=False,
    upx=False,
    console=True,
)
