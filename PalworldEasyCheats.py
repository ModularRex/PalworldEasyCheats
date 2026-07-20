#!/usr/bin/env python3
"""
PalworldEasyCheats settings GUI (PySide6).

Replaces PalworldEasyCheatsMenu.bat + helper.ps1.
Reads/writes Scripts/settings.json next to the mod root, and enables the
mod in the parent UE4SS mods.txt on launch.

Run:  python PalworldEasyCheats.py
Build:  build.bat  (Nuitka standalone → dist\ → PalworldEasyCheats\)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices, QFont, QMouseEvent
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QDoubleSpinBox,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLayout,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QStatusBar,
    QVBoxLayout,
    QWidget,
)

APP_NAME = "PalworldEasyCheats"
APP_VERSION = "1.0"
APP_AUTHOR = "ModularRex"
APP_AUTHOR_URL = "https://www.nexusmods.com/profile/ModularRex"

# ---------------------------------------------------------------------------
# Paths (works as .py and as frozen one-file exe under gui/)
# ---------------------------------------------------------------------------


def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def mod_root() -> Path:
    # gui/ lives inside the mod folder
    return app_dir().parent


def scripts_dir() -> Path:
    return mod_root() / "Scripts"


def settings_path() -> Path:
    return scripts_dir() / "settings.json"


def mods_txt_path() -> Path:
    return mod_root().parent / "mods.txt"


def scripts_dir_status() -> tuple[bool, str]:
    path = scripts_dir()
    if path.is_dir():
        return True, "Scripts folder found"
    return False, "Scripts folder not found"


def mod_folder_name() -> str:
    return mod_root().name


# ---------------------------------------------------------------------------
# Defaults / load / save (mirrors helper.ps1)
# ---------------------------------------------------------------------------


def default_settings() -> dict[str, Any]:
    return {
        "movement": {
            "speedMultiplier": 2.0,
            "speedStep": 0.25,
            "minSpeedMultiplier": 0.25,
            "maxSpeedMultiplier": 10.0,
            "defaultSpeedMultiplier": 1.0,
            "matchSwimSpeed": False,
        },
        "jump": {
            "highJumpEnabled": False,
            "jumpHeightMultiplier": 2.0,
        },
        "fuel": {
            "infiniteFuel": False,
        },
        "stamina": {
            "infiniteStamina": False,
        },
        "combat": {
            "godModeEnabled": False,
            "includePalsGodMode": False,
        },
        "hunger": {
            "disableHunger": False,
            "includePalsHunger": False,
        },
        "map": {
            "revealMap": False,
            "revealMapClearSize": 50000,
        },
        "system": {
            "skipModDisclaimer": True,
            "persistModifications": True,
            "maintainIntervalMs": 10000,
            "applyOnLoadDelayMs": 2000,
        },
    }


def _as_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return default


def _as_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _as_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def ensure_shape(raw: Any) -> dict[str, Any]:
    s = default_settings()
    if not isinstance(raw, dict):
        return s

    for section in s:
        if isinstance(raw.get(section), dict):
            s[section].update(raw[section])

    # Legacy fuel keys from older menus
    fuel = s["fuel"]
    if "infiniteFuel" not in (raw.get("fuel") or {}):
        if "infiniteFuelEnabled" in (raw.get("fuel") or {}):
            fuel["infiniteFuel"] = _as_bool(raw["fuel"]["infiniteFuelEnabled"])
        elif "fuelDurationMultiplier" in (raw.get("fuel") or {}):
            mult = _as_float(raw["fuel"]["fuelDurationMultiplier"], 1.0)
            fuel["infiniteFuel"] = abs(mult - 1.0) > 0.001

    # Normalize types
    m = s["movement"]
    m["speedMultiplier"] = _as_float(m.get("speedMultiplier"), 2.0)
    m["speedStep"] = _as_float(m.get("speedStep"), 0.25)
    m["minSpeedMultiplier"] = _as_float(m.get("minSpeedMultiplier"), 0.25)
    m["maxSpeedMultiplier"] = _as_float(m.get("maxSpeedMultiplier"), 10.0)
    m["defaultSpeedMultiplier"] = _as_float(m.get("defaultSpeedMultiplier"), 1.0)
    m["matchSwimSpeed"] = _as_bool(m.get("matchSwimSpeed"))

    j = s["jump"]
    j["highJumpEnabled"] = _as_bool(j.get("highJumpEnabled"))
    j["jumpHeightMultiplier"] = _as_float(j.get("jumpHeightMultiplier"), 2.0)

    s["fuel"]["infiniteFuel"] = _as_bool(s["fuel"].get("infiniteFuel"))
    s["stamina"]["infiniteStamina"] = _as_bool(s["stamina"].get("infiniteStamina"))

    c = s["combat"]
    c["godModeEnabled"] = _as_bool(c.get("godModeEnabled"))
    c["includePalsGodMode"] = _as_bool(c.get("includePalsGodMode"))

    h = s["hunger"]
    h["disableHunger"] = _as_bool(h.get("disableHunger"))
    h["includePalsHunger"] = _as_bool(h.get("includePalsHunger"))

    mp = s["map"]
    mp["revealMap"] = _as_bool(mp.get("revealMap"))
    mp["revealMapClearSize"] = _as_int(mp.get("revealMapClearSize"), 50000)

    sys_s = s["system"]
    sys_s["skipModDisclaimer"] = _as_bool(sys_s.get("skipModDisclaimer"), True)
    sys_s["persistModifications"] = _as_bool(sys_s.get("persistModifications"), True)
    sys_s["maintainIntervalMs"] = _as_int(sys_s.get("maintainIntervalMs"), 10000)
    sys_s["applyOnLoadDelayMs"] = _as_int(sys_s.get("applyOnLoadDelayMs"), 2000)

    return s


def load_settings(path: Path) -> dict[str, Any]:
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return ensure_shape(data)
        except (OSError, json.JSONDecodeError):
            pass
    return default_settings()


def save_settings(path: Path, settings: dict[str, Any]) -> None:
    out = {
        "movement": {
            "speedMultiplier": float(settings["movement"]["speedMultiplier"]),
            "speedStep": float(settings["movement"]["speedStep"]),
            "minSpeedMultiplier": float(settings["movement"]["minSpeedMultiplier"]),
            "maxSpeedMultiplier": float(settings["movement"]["maxSpeedMultiplier"]),
            "defaultSpeedMultiplier": float(settings["movement"]["defaultSpeedMultiplier"]),
            "matchSwimSpeed": bool(settings["movement"]["matchSwimSpeed"]),
        },
        "jump": {
            "highJumpEnabled": bool(settings["jump"]["highJumpEnabled"]),
            "jumpHeightMultiplier": float(settings["jump"]["jumpHeightMultiplier"]),
        },
        "fuel": {
            "infiniteFuel": bool(settings["fuel"]["infiniteFuel"]),
        },
        "stamina": {
            "infiniteStamina": bool(settings["stamina"]["infiniteStamina"]),
        },
        "combat": {
            "godModeEnabled": bool(settings["combat"]["godModeEnabled"]),
            "includePalsGodMode": bool(settings["combat"]["includePalsGodMode"]),
        },
        "hunger": {
            "disableHunger": bool(settings["hunger"]["disableHunger"]),
            "includePalsHunger": bool(settings["hunger"]["includePalsHunger"]),
        },
        "map": {
            "revealMap": bool(settings["map"]["revealMap"]),
            "revealMapClearSize": int(settings["map"]["revealMapClearSize"]),
        },
        "system": {
            "skipModDisclaimer": bool(settings["system"]["skipModDisclaimer"]),
            "persistModifications": bool(settings["system"]["persistModifications"]),
            "maintainIntervalMs": int(settings["system"]["maintainIntervalMs"]),
            "applyOnLoadDelayMs": int(settings["system"]["applyOnLoadDelayMs"]),
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(out, indent=2) + "\n"
    # UTF-8 without BOM for the mod's Lua JSON reader
    path.write_text(text, encoding="utf-8", newline="\n")


# ---------------------------------------------------------------------------
# mods.txt enable (mirrors helper.ps1 Ensure-ModsTxtEntry)
# ---------------------------------------------------------------------------


def ensure_mods_txt_entry() -> tuple[bool, str]:
    """Enable this mod in parent mods.txt.

    Returns (ok, message). ok is True when mods.txt exists and this mod
    is listed as enabled (already was, or was just written).
    """
    path = mods_txt_path()
    name = mod_folder_name()
    entry = f"{name} : 1"

    if not path.is_file():
        return (
            False,
            f"mods.txt not found - add \"{entry}\" to the mods.txt file manually.",
        )

    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return False, f"Could not read mods.txt: {exc}"

    lines = raw.splitlines()
    name_re = re.compile(rf"^\s*{re.escape(name)}\s*:")
    found_index = -1
    for i, line in enumerate(lines):
        trim = line.strip()
        if trim.startswith(";"):
            continue
        if name_re.match(trim):
            found_index = i
            break

    if found_index >= 0:
        trim = lines[found_index].strip()
        if re.search(r":\s*1\s*$", trim):
            return True, f"mods.txt found · {name} is enabled"
        lines[found_index] = entry
        try:
            path.write_text("\r\n".join(lines), encoding="utf-8", newline="")
        except OSError as exc:
            return False, f"Could not update mods.txt: {exc}"
        return True, f"mods.txt found · enabled {name}"

    # Insert before Keybinds (must stay last in many UE4SS setups)
    insert_at = -1
    for i, line in enumerate(lines):
        trim = line.strip()
        if re.match(r"^\s*;.*Keybinds", trim) or re.match(r"^\s*Keybinds\s*:", trim):
            insert_at = i
            break

    block = ["", f"; {name}", entry, ""]
    if insert_at >= 0:
        for item in reversed(block):
            lines.insert(insert_at, item)
    else:
        if lines and lines[-1].strip() != "":
            lines.append("")
        lines.extend(block)

    try:
        path.write_text("\r\n".join(lines), encoding="utf-8", newline="")
    except OSError as exc:
        return False, f"Could not update mods.txt: {exc}"
    return True, f"mods.txt found · added {entry}"


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

STYLESHEET = """
QMainWindow, QWidget {
    background-color: #1a1d23;
    color: #e8eaed;
    font-size: 13px;
}
QScrollArea {
    border: none;
    background: transparent;
}
QGroupBox {
    border: 1px solid #2f3540;
    border-radius: 8px;
    margin-top: 14px;
    padding: 12px 10px 10px 10px;
    font-weight: 600;
    color: #c5cad3;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 12px;
    padding: 0 6px;
    color: #8ab4f8;
}
QCheckBox {
    spacing: 10px;
    padding: 4px 2px;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
    border-radius: 4px;
    border: 1px solid #5a6270;
    background: #252a33;
}
QCheckBox::indicator:checked {
    background: #3b82f6;
    border-color: #60a5fa;
}
QDoubleSpinBox {
    background: #252a33;
    border: 1px solid #3a4150;
    border-radius: 6px;
    padding: 4px 8px;
    min-height: 26px;
    selection-background-color: #3b82f6;
}
QDoubleSpinBox:focus {
    border-color: #60a5fa;
}
QPushButton {
    background: #2b3240;
    border: 1px solid #3a4150;
    border-radius: 6px;
    padding: 8px 14px;
    min-height: 20px;
}
QPushButton:hover {
    background: #363e4f;
    border-color: #5a6578;
}
QPushButton:pressed {
    background: #222831;
}
QPushButton#dangerBtn {
    background: #3f1d1d;
    border-color: #7f1d1d;
    color: #fecaca;
}
QPushButton#dangerBtn:hover {
    background: #5b2525;
}
QLabel#titleLabel {
    font-size: 18px;
    font-weight: 700;
    color: #f1f3f5;
}
QLabel#authorLink {
    color: #2563eb;
    font-size: 13px;
    font-weight: 600;
}
QLabel#authorLink:hover {
    color: #3b82f6;
}
QLabel#hintLabel {
    color: #8b939e;
    font-size: 12px;
}
QLabel#modsOkLabel {
    color: #86efac;
    font-size: 12px;
    font-weight: 600;
}
QLabel#modsBadLabel {
    color: #f87171;
    font-size: 12px;
    font-weight: 600;
}
QLabel#hotkeyLabel {
    font-family: Consolas, "Cascadia Mono", monospace;
    color: #cbd5e1;
    padding: 1px 0;
}
QFrame#divider {
    background: #2f3540;
    max-height: 1px;
    min-height: 1px;
}
QStatusBar {
    background: #14171c;
    color: #9aa3b2;
    border-top: 1px solid #2f3540;
}
"""


def make_divider() -> QFrame:
    line = QFrame()
    line.setObjectName("divider")
    line.setFrameShape(QFrame.Shape.HLine)
    return line


class LinkLabel(QLabel):
    """Plain blue text that opens a URL on click (avoids gray Qt rich-text links)."""

    def __init__(self, text: str, url: str, parent: QWidget | None = None) -> None:
        super().__init__(text, parent)
        self._url = url
        self.setObjectName("authorLink")
        # Widget stylesheet beats the global QWidget { color: gray } rule
        self.setStyleSheet(
            "QLabel#authorLink { color: #2563eb; font-size: 13px; font-weight: 600; }"
            "QLabel#authorLink:hover { color: #3b82f6; }"
        )
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setToolTip(url)
        self.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            QDesktopServices.openUrl(QUrl(self._url))
            event.accept()
            return
        super().mousePressEvent(event)


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_NAME)
        self.setMinimumSize(520, 360)
        self.resize(870, 730)

        self._path = settings_path()
        self._settings = load_settings(self._path)
        self._suppress = False

        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # Scrollable content — keep natural sizes, never squash controls
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        root.addWidget(scroll, 1)

        body = QWidget()
        body.setSizePolicy(
            QSizePolicy.Policy.Preferred,
            QSizePolicy.Policy.Minimum,
        )
        scroll.setWidget(body)

        body_layout = QVBoxLayout(body)
        body_layout.setContentsMargins(16, 16, 16, 12)
        body_layout.setSpacing(10)
        # Honor content min size so the viewport scrolls instead of compressing
        body_layout.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)

        # Header: title left, ModularRex link top-right
        header_row = QHBoxLayout()
        header_row.setSpacing(8)

        title = QLabel(f"{APP_NAME} - v{APP_VERSION}")
        title.setObjectName("titleLabel")
        title.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )

        author = LinkLabel(APP_AUTHOR, APP_AUTHOR_URL)
        author.setAlignment(
            Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
        )

        header_row.addWidget(title, 1)
        header_row.addWidget(author, 0, Qt.AlignmentFlag.AlignRight)
        body_layout.addLayout(header_row)

        self.mods_lbl = QLabel()
        self.mods_lbl.setWordWrap(True)
        self.scripts_lbl = QLabel()
        self.scripts_lbl.setWordWrap(True)

        status_col = QVBoxLayout()
        status_col.setContentsMargins(0, 0, 0, 0)
        status_col.setSpacing(1)
        status_col.addWidget(self.mods_lbl)
        status_col.addWidget(self.scripts_lbl)
        body_layout.addLayout(status_col)
        body_layout.addWidget(make_divider())

        # Two-column body
        columns = QHBoxLayout()
        columns.setSpacing(12)
        body_layout.addLayout(columns)

        left = QVBoxLayout()
        left.setSpacing(8)
        right = QVBoxLayout()
        right.setSpacing(8)
        columns.addLayout(left, 1)
        columns.addLayout(right, 1)

        # ---- Left: Permanent + On / Off ----
        permanent = QGroupBox("Permanent")
        permanent.setSizePolicy(
            QSizePolicy.Policy.Preferred,
            QSizePolicy.Policy.Maximum,
        )
        pf = QVBoxLayout(permanent)
        self.chk_reveal_map = QCheckBox("Reveal Full Map")
        self.chk_reveal_map.setToolTip(
            "Sets world map clear size so the full map is revealed. "
            "Confirm when enabling."
        )
        pf.addWidget(self.chk_reveal_map)
        left.addWidget(permanent)

        toggles = QGroupBox("On / Off")
        toggles.setSizePolicy(
            QSizePolicy.Policy.Preferred,
            QSizePolicy.Policy.Maximum,
        )
        tf = QVBoxLayout(toggles)
        self.chk_skip_disclaimer = QCheckBox("Skip Mod Disclaimer")
        self.chk_high_jump = QCheckBox("High Jump")
        self.chk_swim = QCheckBox("Sync Swim Speed")
        self.chk_fuel = QCheckBox("Infinite Fuel")
        self.chk_stamina = QCheckBox("Infinite Stamina")
        self.chk_god = QCheckBox("God Mode On Start")
        self.chk_god_pals = QCheckBox("Include Pals (God Mode)")
        self.chk_hunger = QCheckBox("Disable Hunger On Start")
        self.chk_hunger_pals = QCheckBox("Include Pals (Hunger)")

        self.chk_god_pals.setToolTip(
            "When God Mode is ON, party pals also get muteki + full heal."
        )
        self.chk_hunger_pals.setToolTip(
            "When disable-hunger is ON, party pals also never get hungry."
        )
        self.chk_swim.setToolTip("Match swimming speed to character speed multiplier.")

        for w in (
            self.chk_skip_disclaimer,
            self.chk_high_jump,
            self.chk_swim,
            self.chk_fuel,
            self.chk_stamina,
            self.chk_god,
            self.chk_god_pals,
            self.chk_hunger,
            self.chk_hunger_pals,
        ):
            tf.addWidget(w)
        left.addWidget(toggles)

        # ---- Right: Hotkeys + Values ----
        hotkeys = QGroupBox("Hotkeys (in game)")
        hotkeys.setSizePolicy(
            QSizePolicy.Policy.Preferred,
            QSizePolicy.Policy.Maximum,
        )
        hk = QVBoxLayout(hotkeys)
        for line in (
            "+ / -          Character speed up / down",
            "Alt + 0        Reset character speed",
            "Alt + J        Toggle high jump",
            "Alt + F        Toggle unlimited fuel",
            "Alt + S        Toggle unlimited stamina",
            "Alt + G        Toggle god mode + full heal",
            "Alt + H        Toggle disable hunger",
        ):
            lbl = QLabel(line)
            lbl.setObjectName("hotkeyLabel")
            hk.addWidget(lbl)
        right.addWidget(hotkeys)

        values = QGroupBox("Values")
        values.setSizePolicy(
            QSizePolicy.Policy.Preferred,
            QSizePolicy.Policy.Maximum,
        )
        form = QFormLayout(values)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignLeft)
        form.setFormAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        form.setHorizontalSpacing(16)
        form.setVerticalSpacing(10)

        self.spin_speed = QDoubleSpinBox()
        self.spin_speed.setRange(0.05, 50.0)
        self.spin_speed.setSingleStep(0.25)
        self.spin_speed.setDecimals(2)
        self.spin_speed.setToolTip("1.0 = normal · 1.5 = faster · 2.0 = double")

        self.spin_jump = QDoubleSpinBox()
        self.spin_jump.setRange(0.1, 50.0)
        self.spin_jump.setSingleStep(0.25)
        self.spin_jump.setDecimals(2)
        self.spin_jump.setSuffix("x")
        self.spin_jump.setToolTip("Jump height multiplier when High Jump is on.")

        form.addRow("Character Speed", self.spin_speed)
        form.addRow("High Jump Height", self.spin_jump)
        right.addWidget(values)

        # Footer (full width, still inside scroll)
        actions = QHBoxLayout()
        self.btn_reload = QPushButton("Reload")
        self.btn_reload.setToolTip("Reload settings.json from disk")
        self.btn_reset = QPushButton("Reset Everything To Normal")
        self.btn_reset.setObjectName("dangerBtn")
        actions.addWidget(self.btn_reload)
        actions.addWidget(self.btn_reset)
        actions.addStretch(1)
        body_layout.addLayout(actions)

        note = QLabel(
            "Restart Palworld after changing options, or refresh mods in UE4SS."
        )
        note.setObjectName("hintLabel")
        note.setWordWrap(True)
        body_layout.addWidget(note)

        self.status = QStatusBar()
        self.setStatusBar(self.status)

        self._wire_signals()
        self._apply_to_ui()

        mods_ok, mods_msg = ensure_mods_txt_entry()
        self._set_status_label(self.mods_lbl, mods_ok, mods_msg)
        scripts_ok, scripts_msg = scripts_dir_status()
        self._set_status_label(self.scripts_lbl, scripts_ok, scripts_msg)
        self.status.showMessage(mods_msg, 8000)

    # ---- status ------------------------------------------------------------

    def _set_status_label(self, label: QLabel, ok: bool, message: str) -> None:
        label.setText(message)
        label.setObjectName("modsOkLabel" if ok else "modsBadLabel")
        # Re-polish so the objectName stylesheet takes effect
        style = label.style()
        style.unpolish(label)
        style.polish(label)
        label.update()

    # ---- signals -----------------------------------------------------------

    def _wire_signals(self) -> None:
        # Reveal map needs confirmation when turning ON
        self.chk_reveal_map.clicked.connect(self._on_reveal_map_clicked)

        for chk in (
            self.chk_skip_disclaimer,
            self.chk_high_jump,
            self.chk_swim,
            self.chk_fuel,
            self.chk_stamina,
            self.chk_god,
            self.chk_god_pals,
            self.chk_hunger,
            self.chk_hunger_pals,
        ):
            chk.toggled.connect(self._on_toggle_changed)

        self.spin_speed.valueChanged.connect(self._on_value_changed)
        self.spin_jump.valueChanged.connect(self._on_value_changed)

        self.btn_reload.clicked.connect(self._reload)
        self.btn_reset.clicked.connect(self._reset)

    # ---- UI <-> settings ---------------------------------------------------

    def _apply_to_ui(self) -> None:
        self._suppress = True
        s = self._settings
        self.chk_reveal_map.setChecked(bool(s["map"]["revealMap"]))
        self.chk_skip_disclaimer.setChecked(bool(s["system"]["skipModDisclaimer"]))
        self.chk_high_jump.setChecked(bool(s["jump"]["highJumpEnabled"]))
        self.chk_swim.setChecked(bool(s["movement"]["matchSwimSpeed"]))
        self.chk_fuel.setChecked(bool(s["fuel"]["infiniteFuel"]))
        self.chk_stamina.setChecked(bool(s["stamina"]["infiniteStamina"]))
        self.chk_god.setChecked(bool(s["combat"]["godModeEnabled"]))
        self.chk_god_pals.setChecked(bool(s["combat"]["includePalsGodMode"]))
        self.chk_hunger.setChecked(bool(s["hunger"]["disableHunger"]))
        self.chk_hunger_pals.setChecked(bool(s["hunger"]["includePalsHunger"]))
        self.spin_speed.setValue(float(s["movement"]["speedMultiplier"]))
        self.spin_jump.setValue(float(s["jump"]["jumpHeightMultiplier"]))
        self._suppress = False

    def _collect_from_ui(self) -> None:
        s = self._settings
        s["map"]["revealMap"] = self.chk_reveal_map.isChecked()
        s["system"]["skipModDisclaimer"] = self.chk_skip_disclaimer.isChecked()
        s["jump"]["highJumpEnabled"] = self.chk_high_jump.isChecked()
        s["movement"]["matchSwimSpeed"] = self.chk_swim.isChecked()
        s["fuel"]["infiniteFuel"] = self.chk_fuel.isChecked()
        s["stamina"]["infiniteStamina"] = self.chk_stamina.isChecked()
        s["combat"]["godModeEnabled"] = self.chk_god.isChecked()
        s["combat"]["includePalsGodMode"] = self.chk_god_pals.isChecked()
        s["hunger"]["disableHunger"] = self.chk_hunger.isChecked()
        s["hunger"]["includePalsHunger"] = self.chk_hunger_pals.isChecked()
        s["movement"]["speedMultiplier"] = float(self.spin_speed.value())
        s["jump"]["jumpHeightMultiplier"] = float(self.spin_jump.value())

    # ---- actions -----------------------------------------------------------

    def _on_reveal_map_clicked(self, checked: bool) -> None:
        if self._suppress:
            return
        if checked:
            reply = QMessageBox.question(
                self,
                "Reveal Full Map",
                "This action is permanent and cannot be undone.\n\n"
                "Reveal the entire map?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                self._suppress = True
                self.chk_reveal_map.setChecked(False)
                self._suppress = False
                return
        self._autosave("Reveal Full Map")

    def _on_toggle_changed(self, _checked: bool = False) -> None:
        if self._suppress:
            return
        self._autosave()

    def _on_value_changed(self, _value: float = 0.0) -> None:
        if self._suppress:
            return
        self._autosave()

    def _autosave(self, label: str | None = None) -> None:
        self._collect_from_ui()
        try:
            save_settings(self._path, self._settings)
            msg = "Saved."
            if label:
                msg = f"Saved · {label}"
            self.status.showMessage(msg, 3000)
        except OSError as exc:
            self.status.showMessage(f"Save failed: {exc}", 8000)
            QMessageBox.critical(self, "Save failed", str(exc))

    def _reload(self) -> None:
        self._settings = load_settings(self._path)
        self._apply_to_ui()
        self.status.showMessage("Reloaded from disk.", 3000)

    def _reset(self) -> None:
        reply = QMessageBox.question(
            self,
            "Reset Everything",
            "Reset ALL options back to normal defaults?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        self._settings = default_settings()
        self._apply_to_ui()
        self._autosave("reset to defaults")


def main() -> int:
    # High-DPI friendly defaults
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setOrganizationName(APP_AUTHOR)
    app.setStyle("Fusion")
    app.setStyleSheet(STYLESHEET)

    font = QFont("Segoe UI", 10)
    app.setFont(font)

    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
