# PalworldEasyCheats

## Requirements

- **Windows** (Nuitka standalone build targets Win64)
- **Python 3.12+** on `PATH` as `py` (Windows Python launcher)
- **C compiler** for Nuitka (Visual Studio Build Tools / MSVC recommended)
- Python packages from `requirements.txt`:
  - [PySide6](https://pypi.org/project/PySide6/) — GUI
  - [Nuitka](https://nuitka.net/) — freeze to standalone `.exe`

```bat
py -m pip install -r requirements.txt
```

## Run from source

```bat
py PalworldEasyCheats.py
```

## Build release package

```bat
build.bat
```