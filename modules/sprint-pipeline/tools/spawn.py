#!/usr/bin/env python3
"""spawn.py - Cross-platform Claude Code session launcher.

Launches multiple CC sessions in terminal tabs with model selection
(Opus, Sonnet, Duo) and channel routing. Single file, stdlib only.

Usage:
    python spawn.py                         # GUI mode
    python spawn.py <mode> <count>          # headless mode
    python spawn.py --check [--json]        # dependency audit
    python spawn.py --setup [--interactive] # configure terminal
    python spawn.py --dry-run <mode> <count># simulate spawn
    python spawn.py --config                # print config
"""

import abc
import argparse
import ctypes
import ctypes.util
import json
import os
import pathlib
import platform
import queue
import shutil
import subprocess
import sys
import threading
import time

if sys.platform == "win32":
    import ctypes.wintypes

# -- Constants ----------------------------------------------------------------

CONFIG_PATH = pathlib.Path.home() / ".claude" / "tools" / "spawn.json"

MODES = ("opus", "sonnet", "duo")

TERMINAL_PRIORITY = {
    "windows": ["wt", "cmd"],
    "linux": ["gnome-terminal", "konsole", "xfce4-terminal", "xterm"],
    "darwin": ["iterm2", "terminal.app"],
}


# -- Config -------------------------------------------------------------------

class Config:
    """Read/write ~/.claude/tools/spawn.json."""

    DEFAULTS = {
        "terminal": "",
        "tabs_supported": False,
        "key_sender": "",
        "startup_delay": 5,
        "command_delay": 3,
        "tab_init_delay": 2,
        "trust_prompt_delay": 3,
        "project_dir": "",  # empty = use current working directory
    }

    def __init__(self, path=None):
        self.path = pathlib.Path(path) if path else CONFIG_PATH
        self._data = {}

    def load(self):
        if self.path.exists():
            try:
                with open(self.path, encoding="utf-8") as f:
                    self._data = json.load(f)
            except (json.JSONDecodeError, ValueError):
                print("[!] Warning: corrupted %s, using defaults" % self.path,
                      file=sys.stderr)
                self._data = {}
        else:
            self._data = {}
        return self

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2)
        return self

    def get(self, key, default=None):
        if default is None:
            default = self.DEFAULTS.get(key)
        return self._data.get(key, default)

    def set(self, key, value):
        self._data[key] = value
        return self

    @property
    def data(self):
        merged = dict(self.DEFAULTS)
        merged.update(self._data)
        return merged

    def exists(self):
        return self.path.exists()


# -- KeySender ----------------------------------------------------------------

class KeySender(abc.ABC):
    """ABC for sending keystrokes to the foreground window."""

    @abc.abstractmethod
    def type_text(self, text: str) -> None:
        """Type text character by character."""

    @abc.abstractmethod
    def press_enter(self) -> None:
        """Press the Enter key."""

    def type_line(self, text: str) -> None:
        """Type text and press Enter."""
        self.type_text(text)
        self.press_enter()


class Win32KeySender(KeySender):
    """Windows: ctypes -> user32.SendInput."""

    VK_RETURN = 0x0D
    INPUT_KEYBOARD = 1
    KEYEVENTF_UNICODE = 0x0004
    KEYEVENTF_KEYUP = 0x0002

    def __init__(self):
        if sys.platform != "win32":
            raise RuntimeError("Win32KeySender requires Windows")

        class KEYBDINPUT(ctypes.Structure):
            _fields_ = [
                ("wVk", ctypes.wintypes.WORD),
                ("wScan", ctypes.wintypes.WORD),
                ("dwFlags", ctypes.wintypes.DWORD),
                ("time", ctypes.wintypes.DWORD),
                ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
            ]

        class MOUSEINPUT(ctypes.Structure):
            _fields_ = [
                ("dx", ctypes.wintypes.LONG),
                ("dy", ctypes.wintypes.LONG),
                ("mouseData", ctypes.wintypes.DWORD),
                ("dwFlags", ctypes.wintypes.DWORD),
                ("time", ctypes.wintypes.DWORD),
                ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
            ]

        class INPUT_UNION(ctypes.Union):
            _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT)]

        class INPUT(ctypes.Structure):
            _fields_ = [
                ("type", ctypes.wintypes.DWORD),
                ("_input", INPUT_UNION),
            ]

        self._INPUT = INPUT
        self._send_input = ctypes.windll.user32.SendInput
        self._send_input.argtypes = [
            ctypes.wintypes.UINT,
            ctypes.POINTER(INPUT),
            ctypes.c_int,
        ]
        self._send_input.restype = ctypes.wintypes.UINT

    def _send_key(self, vk=0, scan=0, flags=0):
        inp = self._INPUT()
        inp.type = self.INPUT_KEYBOARD
        inp._input.ki.wVk = vk
        inp._input.ki.wScan = scan
        inp._input.ki.dwFlags = flags
        inp._input.ki.time = 0
        inp._input.ki.dwExtraInfo = ctypes.pointer(ctypes.c_ulong(0))
        self._send_input(1, ctypes.byref(inp), ctypes.sizeof(inp))

    def type_text(self, text):
        for char in text:
            self._send_key(scan=ord(char), flags=self.KEYEVENTF_UNICODE)
            self._send_key(
                scan=ord(char),
                flags=self.KEYEVENTF_UNICODE | self.KEYEVENTF_KEYUP,
            )
            time.sleep(0.01)

    def press_enter(self):
        self._send_key(vk=self.VK_RETURN)
        self._send_key(vk=self.VK_RETURN, flags=self.KEYEVENTF_KEYUP)


class X11KeySender(KeySender):
    """Linux X11: ctypes -> libX11/libXtst XTest, or xdotool fallback."""

    def __init__(self):
        if sys.platform != "linux":
            raise RuntimeError("X11KeySender requires Linux")

        self._use_xdotool = False
        try:
            x11_name = ctypes.util.find_library("X11") or "libX11.so.6"
            xtst_name = ctypes.util.find_library("Xtst") or "libXtst.so.6"
            self._x11 = ctypes.cdll.LoadLibrary(x11_name)
            self._xtst = ctypes.cdll.LoadLibrary(xtst_name)
            self._display = self._x11.XOpenDisplay(None)
            if not self._display:
                raise OSError("Cannot open X11 display")
        except OSError:
            if shutil.which("xdotool"):
                self._use_xdotool = True
            else:
                raise RuntimeError(
                    "Neither libXtst nor xdotool available. "
                    "Install: sudo apt install libxtst6 (or xdotool)"
                )

    def type_text(self, text):
        if self._use_xdotool:
            subprocess.run(
                ["xdotool", "type", "--delay", "10", text], check=True
            )
        else:
            for char in text:
                keysym = self._x11.XStringToKeysym(char.encode("ascii"))
                if keysym == 0:
                    continue  # skip unmappable chars
                keycode = self._x11.XKeysymToKeycode(self._display, keysym)
                self._xtst.XTestFakeKeyEvent(self._display, keycode, True, 0)
                self._xtst.XTestFakeKeyEvent(self._display, keycode, False, 0)
                self._x11.XFlush(self._display)
                time.sleep(0.01)

    def press_enter(self):
        if self._use_xdotool:
            subprocess.run(["xdotool", "key", "Return"], check=True)
        else:
            keysym = self._x11.XStringToKeysym(b"Return")
            keycode = self._x11.XKeysymToKeycode(self._display, keysym)
            self._xtst.XTestFakeKeyEvent(self._display, keycode, True, 0)
            self._xtst.XTestFakeKeyEvent(self._display, keycode, False, 0)
            self._x11.XFlush(self._display)


class AppleScriptKeySender(KeySender):
    """macOS: osascript -> AppleScript keystroke."""

    def __init__(self):
        if sys.platform != "darwin":
            raise RuntimeError("AppleScriptKeySender requires macOS")

    def _run_applescript(self, script):
        subprocess.run(
            ["osascript", "-e", script], check=True, capture_output=True
        )

    def type_text(self, text):
        escaped = text.replace("\\", "\\\\").replace('"', '\\"')
        self._run_applescript(
            f'tell application "System Events" to keystroke "{escaped}"'
        )

    def press_enter(self):
        self._run_applescript(
            'tell application "System Events" to key code 36'
        )


# -- TerminalDriver -----------------------------------------------------------

class TerminalDriver(abc.ABC):
    """ABC for terminal window/tab management."""

    @abc.abstractmethod
    def open_window(self, window_name: str, project_dir: str) -> None:
        """Open a new terminal window."""

    @abc.abstractmethod
    def open_tab(self, window_name: str, project_dir: str) -> None:
        """Open a new tab in an existing window."""

    @abc.abstractmethod
    def activate(self, window_name: str) -> None:
        """Bring the named window to the foreground."""


def _xdotool_activate_by_pid(pid):
    """Activate a window by PID using xdotool (shared by Linux drivers)."""
    if not pid or not shutil.which("xdotool"):
        return
    result = subprocess.run(
        ["xdotool", "search", "--pid", str(pid)],
        capture_output=True, text=True,
    )
    window_ids = result.stdout.strip().split("\n")
    if window_ids and window_ids[0]:
        subprocess.run(
            ["xdotool", "windowactivate", window_ids[0]],
            check=False,
        )


class WTDriver(TerminalDriver):
    """Windows Terminal driver."""

    def open_window(self, window_name, project_dir):
        subprocess.run(
            ["wt", "-w", window_name, "-d", str(project_dir)], check=True
        )

    def open_tab(self, window_name, project_dir):
        subprocess.run(
            ["wt", "-w", window_name, "nt", "-d", str(project_dir)],
            check=True,
        )

    def activate(self, window_name):
        subprocess.run(["wt", "-w", window_name, "ft"], check=True)


class GnomeTermDriver(TerminalDriver):
    """gnome-terminal driver. Uses title-based activation (D-Bus architecture
    means Popen PID is useless for window identification)."""

    def open_window(self, window_name, project_dir):
        subprocess.Popen([
            "gnome-terminal",
            "--title=" + window_name,
            "--working-directory=" + str(project_dir),
        ])

    def open_tab(self, window_name, project_dir):
        subprocess.Popen([
            "gnome-terminal",
            "--tab",
            "--working-directory=" + str(project_dir),
        ])

    def activate(self, window_name):
        if shutil.which("xdotool"):
            result = subprocess.run(
                ["xdotool", "search", "--name", window_name],
                capture_output=True, text=True,
            )
            window_ids = result.stdout.strip().split("\n")
            if window_ids and window_ids[0]:
                subprocess.run(
                    ["xdotool", "windowactivate", window_ids[0]],
                    check=False,
                )
        # else: no-op, rely on tab open bringing focus


class _PidTrackingDriver(TerminalDriver):
    """Base for Linux drivers that track PID for xdotool activation."""

    def __init__(self):
        self._pid = None

    def activate(self, window_name):
        _xdotool_activate_by_pid(self._pid)


class KonsoleDriver(_PidTrackingDriver):
    """konsole driver. --new-tab requires single-process mode enabled."""

    def open_window(self, window_name, project_dir):
        proc = subprocess.Popen([
            "konsole", "--workdir", str(project_dir),
        ])
        self._pid = proc.pid

    def open_tab(self, window_name, project_dir):
        subprocess.Popen([
            "konsole", "--new-tab", "--workdir", str(project_dir),
        ])


class XfceTermDriver(_PidTrackingDriver):
    """xfce4-terminal driver."""

    def open_window(self, window_name, project_dir):
        proc = subprocess.Popen([
            "xfce4-terminal",
            "--working-directory=" + str(project_dir),
        ])
        self._pid = proc.pid

    def open_tab(self, window_name, project_dir):
        subprocess.Popen([
            "xfce4-terminal",
            "--tab",
            "--working-directory=" + str(project_dir),
        ])


class _AppleScriptDriverMixin:
    """Shared osascript helper for macOS terminal drivers."""

    def _applescript(self, script):
        subprocess.run(["osascript", "-e", script], check=True, capture_output=True)


class MacTermDriver(_AppleScriptDriverMixin, TerminalDriver):
    """macOS Terminal.app via osascript."""

    def open_window(self, window_name, project_dir):
        self._applescript(
            f'tell application "Terminal"\n'
            f'  activate\n'
            f'  do script "cd \'{project_dir}\'"\n'
            f'end tell'
        )

    def open_tab(self, window_name, project_dir):
        self._applescript(
            f'tell application "Terminal"\n'
            f'  activate\n'
            f'  tell application "System Events" to keystroke "t" '
            f'using command down\n'
            f'  do script "cd \'{project_dir}\'" in front window\n'
            f'end tell'
        )

    def activate(self, window_name):
        self._applescript(
            'tell application "Terminal" to set frontmost to true'
        )


class ITermDriver(_AppleScriptDriverMixin, TerminalDriver):
    """iTerm2 via osascript."""

    def open_window(self, window_name, project_dir):
        self._applescript(
            f'tell application "iTerm"\n'
            f'  create window with default profile\n'
            f'  tell current session of current window\n'
            f'    write text "cd \'{project_dir}\'"\n'
            f'  end tell\n'
            f'end tell'
        )

    def open_tab(self, window_name, project_dir):
        self._applescript(
            f'tell application "iTerm"\n'
            f'  tell current window\n'
            f'    create tab with default profile\n'
            f'    tell current session\n'
            f'      write text "cd \'{project_dir}\'"\n'
            f'    end tell\n'
            f'  end tell\n'
            f'end tell'
        )

    def activate(self, window_name):
        self._applescript(
            'tell application "iTerm" to activate'
        )


class FallbackDriver(TerminalDriver):
    """Fallback: opens separate windows. activate() is a no-op."""

    def __init__(self):
        self._platform = sys.platform

    def open_window(self, window_name, project_dir):
        self._open(project_dir)

    def open_tab(self, window_name, project_dir):
        self._open(project_dir)  # falls back to new window

    def _open(self, project_dir):
        if self._platform == "win32":
            subprocess.Popen(["cmd", "/k", 'cd /d "%s"' % project_dir])
        elif self._platform == "darwin":
            subprocess.Popen(["open", "-a", "Terminal", str(project_dir)])
        else:
            subprocess.Popen(["xterm", "-e", "cd '%s' && $SHELL" % project_dir])

    def activate(self, window_name):
        pass  # no-op: rely on new window stealing focus


# -- Setup / Detection --------------------------------------------------------

def detect_os():
    """Detect operating system: windows, linux, or darwin."""
    if sys.platform == "win32":
        return "windows"
    elif sys.platform == "darwin":
        return "darwin"
    return "linux"


def detect_display_server():
    """Detect display server: win32, aqua, wayland, or x11."""
    if sys.platform == "win32":
        return "win32"
    if sys.platform == "darwin":
        return "aqua"
    session_type = os.environ.get("XDG_SESSION_TYPE", "")
    if session_type == "wayland" or os.environ.get("WAYLAND_DISPLAY"):
        return "wayland"
    return "x11"


def _find_mac_app(candidates):
    """Return the first existing .app bundle path from candidates, or None."""
    for path in candidates:
        if os.path.isdir(path):
            return path
    return None


def detect_terminal():
    """Find the best available terminal using platform priority order."""
    os_name = detect_os()
    priority = TERMINAL_PRIORITY.get(os_name, [])

    # macOS apps are bundles, not executables on PATH.
    # Catalina+ moved built-in apps to /System/Applications/.
    mac_app_candidates = {
        "iterm2": ["/Applications/iTerm.app"],
        "terminal.app": [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app",
        ],
    }

    for term_name in priority:
        if os_name == "darwin" and term_name in mac_app_candidates:
            found = _find_mac_app(mac_app_candidates[term_name])
            if found:
                return {"name": term_name, "path": found, "tabs": True}
        else:
            path = shutil.which(term_name)
            if path:
                tabs = term_name not in ("cmd", "xterm")
                return {"name": term_name, "path": path, "tabs": tabs}

    return {"name": "", "path": "", "tabs": False}


def detect_key_sender():
    """Detect available keystroke injection method."""
    if sys.platform == "win32":
        return {"method": "win32", "available": True}
    if sys.platform == "darwin":
        result = {"method": "applescript", "available": True}
        # Check accessibility permission via test keystroke
        try:
            proc = subprocess.run(
                ["osascript", "-e",
                 'tell application "System Events" to key code 0'],
                capture_output=True, timeout=5,
            )
            if proc.returncode != 0:
                result["accessibility_permission"] = False
                result["fix"] = (
                    "Grant Accessibility permission to your terminal app "
                    "in System Settings > Privacy & Security > Accessibility"
                )
            else:
                result["accessibility_permission"] = True
        except Exception:
            result["accessibility_permission"] = False
            result["fix"] = "Could not test Accessibility permission"
        return result
    # Linux
    if detect_display_server() == "wayland":
        return {"method": "none", "available": False, "reason": "wayland"}
    # X11
    try:
        lib = ctypes.util.find_library("Xtst")
        if lib:
            return {"method": "x11_xtest", "available": True}
    except Exception:
        pass
    if shutil.which("xdotool"):
        return {"method": "xdotool", "available": True}
    return {
        "method": "none",
        "available": False,
        "install_cmd": "sudo apt install libxtst6",
    }


def detect_window_activation():
    """Detect window activation method."""
    if sys.platform == "win32":
        if shutil.which("wt"):
            return {"method": "wt_named_windows", "available": True}
        return {"method": "none", "available": False}
    if sys.platform == "darwin":
        return {"method": "applescript", "available": True}
    # Linux
    if shutil.which("xdotool"):
        return {"method": "xdotool", "available": True}
    if shutil.which("wmctrl"):
        return {"method": "wmctrl", "available": True}
    return {"method": "none", "available": False}


def run_check():
    """Run full dependency check, return dict."""
    os_name = detect_os()
    display = detect_display_server()
    terminal = detect_terminal()
    key_sender = detect_key_sender()
    win_activation = detect_window_activation()

    try:
        import tkinter as _tk
        has_tkinter = True
    except ImportError:
        has_tkinter = False

    missing = []
    if not terminal["name"]:
        rec = {"name": "tabbed terminal", "required_for": "tabbed sessions"}
        if os_name == "windows":
            rec["install_cmd"] = "winget install Microsoft.WindowsTerminal"
            rec["needs_sudo"] = False
        elif os_name == "linux":
            rec["install_cmd"] = "sudo apt install gnome-terminal"
            rec["needs_sudo"] = True
        else:
            rec["install_cmd"] = "Terminal.app should be available"
            rec["needs_sudo"] = False
        missing.append(rec)

    if not key_sender.get("available"):
        if os_name == "linux" and display != "wayland":
            missing.append({
                "name": "libxtst6",
                "install_cmd": "sudo apt install libxtst6",
                "needs_sudo": True,
                "required_for": "keystroke injection",
            })

    warnings = []
    if display == "wayland":
        warnings.append(
            "Wayland detected. Keystroke injection is not supported. "
            "You will need to type /rename and channel commands manually "
            "in each session."
        )

    # Check if project_dir will trigger trust prompt
    cfg = Config().load()
    check_project_dir = cfg.get("project_dir", "") or os.getcwd()
    if Spawner._needs_trust_prompt(check_project_dir):
        trust_delay = cfg.get("trust_prompt_delay", 3)
        warnings.append(
            "project_dir (%s) will trigger Claude Code's trust prompt, "
            "adding ~%.0fs per session. Set project_dir in "
            "~/.claude/tools/spawn.json to a trusted project directory "
            "to avoid this." % (check_project_dir, trust_delay)
        )

    result = {
        "os": os_name,
        "display_server": display,
        "python_version": platform.python_version(),
        "terminal": terminal,
        "key_sender": key_sender,
        "window_activation": win_activation,
        "tkinter": has_tkinter,
        "ready": (bool(terminal["name"]) or display == "wayland")
                 and key_sender.get("available", False),
        "accessibility_permission": key_sender.get("accessibility_permission"),
        "missing": missing,
    }
    if warnings:
        result["warnings"] = warnings
    return result


def run_setup(terminal_override=None):
    """Auto-detect environment and write config."""
    if terminal_override:
        path = shutil.which(terminal_override)
        terminal = {
            "name": terminal_override,
            "path": path or "",
            "tabs": terminal_override not in ("cmd", "xterm"),
        }
    else:
        terminal = detect_terminal()

    key_sender = detect_key_sender()

    cfg = Config().load()
    cfg.set("terminal", terminal["name"])
    cfg.set("tabs_supported", terminal["tabs"])
    cfg.set("key_sender", key_sender.get("method", ""))
    for key in ("startup_delay", "command_delay", "tab_init_delay", "trust_prompt_delay", "project_dir"):
        if key not in cfg._data:
            cfg.set(key, Config.DEFAULTS[key])
    cfg.save()

    # Print setup summary
    print("Terminal: %s (%s)" % (terminal["name"], terminal["path"]))
    print("Tabs: %s" % ("yes" if terminal["tabs"] else "no"))
    print("Key sender: %s" % key_sender.get("method", "none"))
    print("Config saved to: %s" % cfg.path)

    # Platform-specific notes
    if terminal["name"] == "konsole":
        print(
            "\nkonsole detected. For tab support, ensure "
            '"Run all Konsole windows in a single process" '
            "is enabled in konsole Settings > General."
        )

    return cfg


# -- Spawn Tooltip ------------------------------------------------------------

def _can_use_tkinter():
    """Check if tkinter can safely initialize.

    On macOS, Tk requires the AppKit main thread. Initializing Tk in a
    background thread (as SpawnTooltip does) triggers an Obj-C
    NSInternalInconsistencyException that kills the entire process before
    Python can catch it. Skip Tk when running on macOS in a subprocess
    (no controlling terminal) or when TERM_PROGRAM suggests a non-GUI
    context.
    """
    if sys.platform == "darwin":
        # If we're not in a real terminal (e.g. running from CC's Bash tool),
        # Tk cannot attach to AppKit. Also skip if running in a pipe.
        if not sys.stdout.isatty():
            return False
        if not os.environ.get("TERM_PROGRAM"):
            return False
    try:
        import tkinter  # noqa: F401
        return True
    except ImportError:
        return False


class SpawnTooltip:
    """Small always-on-top status window shown during spawn. Runs in a thread."""

    def __init__(self):
        self._queue = queue.Queue()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._ready = threading.Event()
        self.cancelled = threading.Event()
        self._disabled = not _can_use_tkinter()

    def start(self, text="Spawning..."):
        if self._disabled:
            self._ready.set()
            return
        self._queue.put(("update", text))
        self._thread.start()
        self._ready.wait(timeout=3)

    def update(self, text):
        if self._disabled:
            return
        self._queue.put(("update", text))

    def close(self):
        if self._disabled:
            return
        self._queue.put(("close", None))

    def _run(self):
        try:
            import tkinter as tk
        except ImportError:
            self._ready.set()
            return

        root = tk.Tk()
        root.overrideredirect(True)
        root.attributes("-topmost", True)
        try:
            root.attributes("-alpha", 0.9)
        except tk.TclError:
            pass

        root.configure(bg="#1a1a2e")
        label = tk.Label(
            root, text="Spawning...", font=("Segoe UI", 22),
            fg="#e0e0e0", bg="#1a1a2e", padx=32, pady=20,
        )
        label.pack()
        def cancel():
            if self.cancelled.is_set():
                return
            self.cancelled.set()
            label.config(text="Cancelling...")
            btn.config(state="disabled", text="Stopping...")

        btn = tk.Button(
            root, text="Cancel", font=("Segoe UI", 12, "bold"),
            fg="white", bg="#c0392b", activebackground="#e74c3c",
            activeforeground="white", relief="flat", cursor="hand2",
            padx=24, pady=6, command=cancel,
        )
        btn.pack(pady=(0, 16))

        # Position: center of primary screen
        root.update_idletasks()
        sw = root.winfo_screenwidth()
        sh = root.winfo_screenheight()
        w = root.winfo_width()
        h = root.winfo_height()
        root.geometry("+%d+%d" % ((sw - w) // 2, (sh - h) // 2))

        self._ready.set()

        def poll():
            try:
                while True:
                    cmd, data = self._queue.get_nowait()
                    if cmd == "close":
                        root.destroy()
                        return
                    elif cmd == "update":
                        label.config(text=data)
                        root.update_idletasks()
                        nw = root.winfo_width()
                        nh = root.winfo_height()
                        root.geometry("+%d+%d" % ((sw - nw) // 2, (sh - nh) // 2))
            except queue.Empty:
                pass
            root.after(100, poll)

        root.after(100, poll)
        root.mainloop()


# -- Spawner ------------------------------------------------------------------

class Spawner:
    """Orchestrates the spawn sequence."""

    @staticmethod
    def build_plan(mode, count):
        """Build list of session dicts: [{model, index, window, first}]."""
        models = ["opus", "sonnet"] if mode == "duo" else [mode]
        plan = []
        for model in models:
            for i in range(1, count + 1):
                plan.append({
                    "model": model, "index": i,
                    "window": model, "first": i == 1,
                })
        return plan

    @staticmethod
    def estimate_time(mode, count, cfg):
        """Estimate total spawn time in seconds."""
        project_dir = cfg.get("project_dir", "") or os.getcwd()
        trust_extra = cfg.get("trust_prompt_delay", 3) if Spawner._needs_trust_prompt(project_dir) else 0
        per_session = (
            cfg.get("tab_init_delay", 2)
            + 0.5
            + cfg.get("startup_delay", 5)
            + trust_extra
            + cfg.get("command_delay", 3) * 2
        )
        total_sessions = count * 2 if mode == "duo" else count
        return total_sessions * per_session

    @staticmethod
    def dry_run(mode, count, cfg, file=None):
        """Print the spawn plan without executing."""
        if file is None:
            file = sys.stdout
        plan = Spawner.build_plan(mode, count)
        project_dir = cfg.get("project_dir", "") or os.getcwd()
        tab_delay = cfg.get("tab_init_delay", 2)
        startup_delay = cfg.get("startup_delay", 5)
        cmd_delay = cfg.get("command_delay", 3)
        trust_prompt_delay = cfg.get("trust_prompt_delay", 3)
        needs_trust = Spawner._needs_trust_prompt(project_dir)

        for session in plan:
            model = session["model"]
            idx = session["index"]
            window = session["window"]
            model_cap = model.capitalize()

            if session["first"]:
                print('[dry-run] Would open window "%s" in %s' % (window, project_dir), file=file)
            else:
                print('[dry-run] Would open tab in window "%s"' % window, file=file)
            print("[dry-run] Would sleep %.1fs (tab init)" % tab_delay, file=file)
            print('[dry-run] Would activate window "%s"' % window, file=file)
            print("[dry-run] Would sleep 0.5s (post-activate)", file=file)
            print("[dry-run] Would type: claude --model %s" % model, file=file)
            print("[dry-run] Would sleep %.1fs (startup delay)" % startup_delay, file=file)
            if needs_trust:
                print("[dry-run] Would type: <Enter> (dismiss trust prompt)", file=file)
                print("[dry-run] Would sleep %.1fs (trust prompt delay)" % trust_prompt_delay, file=file)
            print("[dry-run] Would type: /rename %s %s" % (model_cap, idx), file=file)
            print("[dry-run] Would sleep %.1fs (command delay)" % cmd_delay, file=file)
            print("[dry-run] Would type: /%s %s" % (model, idx), file=file)
            print("[dry-run] Would sleep %.1fs (command delay)" % cmd_delay, file=file)

        total = Spawner.estimate_time(mode, count, cfg)
        print("Total estimated time: %.1fs" % total, file=file)

    @staticmethod
    def print_wayland_commands(mode, count, file=None):
        """Print commands for manual entry on Wayland."""
        if file is None:
            file = sys.stdout
        plan = Spawner.build_plan(mode, count)
        print("\nWayland detected. Type these commands in each tab:\n", file=file)
        for session in plan:
            model = session["model"]
            idx = session["index"]
            model_cap = model.capitalize()
            print("  Tab %s %s:" % (session["window"].capitalize(), idx), file=file)
            print("    claude --model %s" % model, file=file)
            print("    /rename %s %s" % (model_cap, idx), file=file)
            print("    /%s %s" % (model, idx), file=file)
            print(file=file)

    @staticmethod
    def _needs_trust_prompt(project_dir):
        """Check if CC will show a trust prompt for this directory.

        CC shows the trust prompt when the directory has no
        .claude/settings.json (not a trusted project).
        The home directory can never be marked as trusted.
        """
        p = pathlib.Path(project_dir).expanduser().resolve()
        home = pathlib.Path.home().resolve()
        if p == home:
            return True
        if not (p / ".claude" / "settings.json").exists():
            return True
        return False

    @staticmethod
    def _has_channel_infra(project_dir):
        """Check if project has channel infrastructure."""
        p = pathlib.Path(project_dir)
        return (
            (p / "channel-template.md").exists()
            or (p / ".claude" / "reference" / "channel-routing.md").exists()
        )

    @staticmethod
    def scaffold_channels(project_dir, count):
        """Create minimal channel infrastructure for duo mode."""
        p = pathlib.Path(project_dir)

        # Channel template
        template = p / "channel-template.md"
        if not template.exists():
            template.write_text(
                "# CURRENT TASK\n\n"
                "## Active Task: (none)\n\n"
                "**Channel:** N\n"
                "**Status:** No active task.\n\n"
                "---\n\n"
                "## Plan\n\n(Steps go here.)\n\n"
                "---\n\n"
                "## Completed Steps\n\n"
                "(Mark each step done here.)\n",
                encoding="utf-8",
            )

        # Channel routing reference
        routing_dir = p / ".claude" / "reference"
        routing_dir.mkdir(parents=True, exist_ok=True)
        routing_file = routing_dir / "channel-routing.md"
        if not routing_file.exists():
            routing_file.write_text(
                "# Channel Routing\n\n"
                "## Check\n\n"
                "Your channel is determined by session context:\n"
                "1. If `/opus N` was called: you are on channel N.\n"
                "2. After compaction: read `CURRENT_TASK_chN.md`.\n\n"
                "## Routing Rules (when channeled)\n\n"
                "1. Dispatch directory: `verification_findings/_pending/chN/`\n"
                "2. Result filenames: append `_chN` before extension.\n"
                "3. Squad directories: `squad_chN_sonnet/` / `squad_chN_opus/`\n",
                encoding="utf-8",
            )

        # Pending directories
        for i in range(1, count + 1):
            (p / "verification_findings" / "_pending" / ("ch%d" % i)).mkdir(
                parents=True, exist_ok=True,
            )

        print("Channel infrastructure scaffolded in %s" % project_dir)

    @staticmethod
    def spawn(mode, count, cfg, driver, key_sender):
        """Execute the spawn sequence."""
        plan = Spawner.build_plan(mode, count)
        project_dir = cfg.get("project_dir", "")
        if project_dir:
            project_dir = os.path.expanduser(project_dir)
        else:
            project_dir = os.getcwd()
        tab_delay = cfg.get("tab_init_delay", 2)
        startup_delay = cfg.get("startup_delay", 5)
        cmd_delay = cfg.get("command_delay", 3)
        trust_prompt_delay = cfg.get("trust_prompt_delay", 3)
        needs_trust = Spawner._needs_trust_prompt(project_dir)
        total_sessions = len(plan)
        is_wayland = detect_display_server() == "wayland"

        # Scaffold channel infrastructure for duo mode if missing
        if mode == "duo" and not Spawner._has_channel_infra(project_dir):
            Spawner.scaffold_channels(project_dir, count)

        total_time = Spawner.estimate_time(mode, count, cfg)
        print("Spawning %d %s session(s). Estimated time: %.0f seconds."
              % (total_sessions, mode, total_time))
        print("Do not interact with your computer until spawn completes.")

        # Status tooltip (best-effort -- tkinter may not be available)
        tooltip = SpawnTooltip()
        try:
            tooltip.start("Spawning %d %s session(s)..." % (total_sessions, mode))
        except Exception:
            tooltip = None

        completed = 0
        current_window = None
        cancelled = False
        failed_windows = set()

        def tip(text):
            if tooltip:
                tooltip.update(text)

        def wait(seconds):
            """Sleep in small increments, checking for cancel."""
            nonlocal cancelled
            end = time.time() + seconds
            while time.time() < end:
                if tooltip and tooltip.cancelled.is_set():
                    cancelled = True
                    return
                time.sleep(min(0.2, end - time.time()))

        try:
            for session in plan:
                if cancelled:
                    break

                model = session["model"]
                idx = session["index"]
                window = session["window"]
                model_cap = model.capitalize()

                if window in failed_windows:
                    continue

                # Progress
                bar_done = "=" * completed
                bar_cur = ">" if completed < total_sessions else ""
                bar_rem = " " * (total_sessions - completed - 1)
                print("\r[%s%s%s] Session %d/%d: %s %d..."
                      % (bar_done, bar_cur, bar_rem,
                         completed + 1, total_sessions, model_cap, idx),
                      end="", flush=True)

                # Step 1: Open tab/window
                try:
                    if session["first"]:
                        tip("Opening %s window..." % model_cap)
                        driver.open_window(window, project_dir)
                        current_window = window
                    else:
                        tip("Opening %s tab %d..." % (model_cap, idx))
                        driver.open_tab(window, project_dir)
                except Exception as e:
                    print("\n  [!] Tab open failed: %s" % e, file=sys.stderr)
                    failed_windows.add(window)
                    print("  [!] Skipping remaining %s sessions" % window,
                          file=sys.stderr)
                    continue

                # Step 2: Sleep tab_init_delay
                wait(tab_delay)
                if cancelled:
                    break

                # Step 3: Activate window
                try:
                    driver.activate(window)
                except Exception:
                    pass  # best-effort

                # Step 4: Sleep 0.5s
                wait(0.5)
                if cancelled:
                    break

                if is_wayland:
                    completed += 1
                    continue  # Skip all keystroke steps

                # Step 5: Type claude --model <model>
                tip("%s %d: launching claude..." % (model_cap, idx))
                key_sender.type_line("claude --model %s" % model)

                # Step 6: Sleep startup_delay
                tip("%s %d: waiting for Claude to start..." % (model_cap, idx))
                wait(startup_delay)
                if cancelled:
                    break

                # Step 6b: Dismiss trust prompt if needed
                if needs_trust:
                    tip("%s %d: dismissing trust prompt..." % (model_cap, idx))
                    key_sender.type_line("")  # Enter to accept trust prompt
                    wait(trust_prompt_delay)
                    if cancelled:
                        break

                # Step 7: Type /rename
                tip("%s %d: configuring session..." % (model_cap, idx))
                key_sender.type_line("/rename %s %d" % (model_cap, idx))

                # Step 8: Sleep command_delay
                wait(cmd_delay)
                if cancelled:
                    break

                # Step 9: Type /<model> <i>
                key_sender.type_line("/%s %d" % (model, idx))

                # Step 10: Sleep command_delay
                wait(cmd_delay)

                completed += 1

        except KeyboardInterrupt:
            cancelled = True

        if cancelled and tooltip:
            time.sleep(1)  # show "Cancelling..." briefly
        if tooltip:
            tooltip.close()

        if cancelled:
            print("\n\nCancelled. %d/%d sessions fully configured."
                  % (completed, total_sessions))
            return completed

        print("\n\nDone. %d session(s) launched." % completed)

        if is_wayland:
            Spawner.print_wayland_commands(mode, count)

        return completed


# -- Driver/Sender Factory ----------------------------------------------------

def get_driver(terminal_name):
    """Return the appropriate TerminalDriver for the terminal name."""
    drivers = {
        "wt": WTDriver,
        "gnome-terminal": GnomeTermDriver,
        "konsole": KonsoleDriver,
        "xfce4-terminal": XfceTermDriver,
        "terminal.app": MacTermDriver,
        "iterm2": ITermDriver,
    }
    cls = drivers.get(terminal_name, FallbackDriver)
    return cls()


def get_key_sender(method):
    """Return the appropriate KeySender for the method name."""
    if method == "win32":
        return Win32KeySender()
    if method in ("x11_xtest", "xdotool"):
        return X11KeySender()
    if method == "applescript":
        return AppleScriptKeySender()
    return None


# -- GUI ----------------------------------------------------------------------

def run_gui():
    """Show tkinter launch dialog, then spawn."""
    import tkinter as tk
    from tkinter import ttk

    result = {}

    def on_launch():
        result["mode"] = mode_var.get().lower()
        result["count"] = int(count_var.get())
        result["delay"] = int(delay_var.get())
        root.destroy()

    root = tk.Tk()
    root.title("Claude Spawn Launcher")
    root.resizable(False, False)

    frame = ttk.Frame(root, padding=20)
    frame.grid()

    ttk.Label(frame, text="Mode:").grid(row=0, column=0, sticky="w", pady=5)
    mode_var = tk.StringVar(value="Opus")
    ttk.Combobox(
        frame, textvariable=mode_var, values=["Opus", "Sonnet", "Duo"],
        state="readonly", width=15,
    ).grid(row=0, column=1, pady=5)

    ttk.Label(frame, text="Sessions:").grid(row=1, column=0, sticky="w", pady=5)
    count_var = tk.StringVar(value="3")
    ttk.Spinbox(
        frame, from_=1, to=20, textvariable=count_var, width=15,
    ).grid(row=1, column=1, pady=5)

    cfg_preload = Config().load()
    ttk.Label(frame, text="Startup delay (s):").grid(row=2, column=0, sticky="w", pady=5)
    delay_var = tk.StringVar(value=str(cfg_preload.get("startup_delay", 5)))
    ttk.Spinbox(
        frame, from_=1, to=60, textvariable=delay_var, width=15,
    ).grid(row=2, column=1, pady=5)

    ttk.Button(frame, text="Launch", command=on_launch).grid(
        row=3, column=0, columnspan=2, pady=15,
    )

    root.mainloop()

    if not result:
        return  # Window closed without launching

    cfg = Config()
    if not cfg.exists():
        run_setup()
    cfg.load()
    cfg.set("startup_delay", result["delay"]).save()

    driver = get_driver(cfg.get("terminal"))
    key_sender = get_key_sender(cfg.get("key_sender"))

    if key_sender is None and detect_display_server() != "wayland":
        print("No keystroke sender available. Run: python spawn.py --check")
        return

    Spawner.spawn(result["mode"], result["count"], cfg.data, driver, key_sender)


def run_setup_gui():
    """Show tkinter setup dialog."""
    import tkinter as tk
    from tkinter import ttk

    os_name = detect_os()
    display = detect_display_server()
    terminal = detect_terminal()
    key_sender = detect_key_sender()

    def on_save():
        selected = term_var.get()
        run_setup(terminal_override=selected if selected != "(auto)" else None)
        root.destroy()

    root = tk.Tk()
    root.title("Spawn Setup")
    root.resizable(False, False)

    frame = ttk.Frame(root, padding=20)
    frame.grid()

    ttk.Label(frame, text="OS: %s" % os_name).grid(row=0, column=0, sticky="w")
    ttk.Label(frame, text="Display: %s" % display).grid(row=1, column=0, sticky="w")
    ttk.Label(frame, text="Key sender: %s" % key_sender.get("method", "none")).grid(
        row=2, column=0, sticky="w"
    )

    ttk.Label(frame, text="\nSelect terminal:").grid(row=3, column=0, sticky="w")
    mac_app_candidates = {
        "iterm2": ["/Applications/iTerm.app"],
        "terminal.app": [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app",
        ],
    }
    priority = TERMINAL_PRIORITY.get(os_name, [])
    available = ["(auto)"] + [
        t for t in priority
        if (os_name == "darwin" and _find_mac_app(mac_app_candidates.get(t, [])))
        or shutil.which(t)
    ]
    term_var = tk.StringVar(value=available[0])
    for i, term in enumerate(available):
        ttk.Radiobutton(
            frame, text=term, variable=term_var, value=term,
        ).grid(row=4 + i, column=0, sticky="w")

    ttk.Button(frame, text="Save", command=on_save).grid(
        row=4 + len(available), column=0, pady=15,
    )

    root.mainloop()


# -- CLI ----------------------------------------------------------------------

def build_parser():
    """Build argparse parser for spawn CLI."""
    parser = argparse.ArgumentParser(
        description="Launch multiple Claude Code sessions in terminal tabs.",
        prog="spawn.py",
    )
    parser.add_argument(
        "mode", nargs="?", choices=MODES, default=None,
        help="Session mode: opus, sonnet, or duo",
    )
    parser.add_argument(
        "count", nargs="?", type=int, default=None,
        help="Number of sessions (1-20 recommended)",
    )
    parser.add_argument("--check", action="store_true", help="Run dependency audit")
    parser.add_argument("--json", action="store_true", help="JSON output (with --check)")
    parser.add_argument("--setup", action="store_true", help="Auto-detect and write config")
    parser.add_argument("--interactive", action="store_true", help="Interactive setup GUI")
    parser.add_argument("--terminal", type=str, help="Override terminal choice (with --setup)")
    parser.add_argument("--config", action="store_true", help="Print current config")
    parser.add_argument("--dry-run", action="store_true", help="Simulate spawn sequence")
    return parser


def main():
    """Main entry point for spawn CLI."""
    parser = build_parser()
    args = parser.parse_args()

    # --check
    if args.check:
        result = run_check()
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print("OS: %s" % result["os"])
            print("Display: %s" % result["display_server"])
            print("Python: %s" % result["python_version"])
            print("Terminal: %s" % (result["terminal"]["name"] or "none"))
            print("Key sender: %s" % result["key_sender"].get("method", "none"))
            print("tkinter: %s" % ("yes" if result["tkinter"] else "no"))
            print("Ready: %s" % ("yes" if result["ready"] else "NO"))
            if result["missing"]:
                print("\nMissing:")
                for dep in result["missing"]:
                    print("  - %s: %s" % (dep.get("name", "unknown"), dep.get("install_cmd", "")))
            if result.get("warnings"):
                print("\nWarnings:")
                for w in result["warnings"]:
                    print("  - %s" % w)
        return 0

    # --config
    if args.config:
        cfg = Config()
        if not cfg.exists():
            print("No config found. Run: python spawn.py --setup")
            return 1
        cfg.load()
        print(json.dumps(cfg.data, indent=2))
        return 0

    # --setup
    if args.setup:
        if args.interactive:
            try:
                run_setup_gui()
            except ImportError:
                print("tkinter unavailable. Run: python spawn.py --setup")
                return 1
        else:
            run_setup(terminal_override=args.terminal)
        return 0

    # --dry-run
    if args.dry_run:
        if not args.mode or not args.count:
            parser.error("--dry-run requires <mode> and <count>")
        cfg = Config().load()
        Spawner.dry_run(args.mode, args.count, cfg.data)
        return 0

    # No args = GUI mode
    if args.mode is None:
        if not _can_use_tkinter():
            print("GUI unavailable (no display or running in subprocess).")
            print("Usage: python spawn.py <mode> <count>")
            print("       python spawn.py --setup")
            print("       python spawn.py --check")
            return 1
        try:
            run_gui()
        except ImportError:
            print("tkinter unavailable. Usage: python spawn.py <mode> <count>")
            print("Install: sudo apt install python3-tk")
            return 1
        return 0

    # Headless mode: <mode> <count>
    if args.count is None:
        parser.error("count is required with mode")
    if args.count < 1:
        parser.error("count must be >= 1")

    # Confirm large counts (skip if not a TTY — e.g. running from CC)
    if args.count > 20 and sys.stdin.isatty():
        cfg_data = Config().load().data
        est = Spawner.estimate_time(args.mode, args.count, cfg_data)
        answer = input(
            "About to spawn %d sessions (%.0fs estimated). Continue? [y/N] "
            % (args.count, est)
        )
        if answer.lower() != "y":
            print("Aborted.")
            return 0

    # Load config (auto-setup if missing)
    cfg = Config()
    if not cfg.exists():
        print("No config found. Running auto-setup...")
        run_setup()
    cfg.load()

    terminal_name = cfg.get("terminal")
    if not terminal_name:
        print("No terminal detected. Run: python spawn.py --check")
        if sys.platform == "darwin":
            print("Expected Terminal.app at /System/Applications/Utilities/ "
                  "or /Applications/Utilities/")
        return 1

    driver = get_driver(terminal_name)
    key_sender = get_key_sender(cfg.get("key_sender"))

    if key_sender is None and detect_display_server() != "wayland":
        print("No keystroke sender available. Run: python spawn.py --check")
        return 1

    Spawner.spawn(args.mode, args.count, cfg.data, driver, key_sender)
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
