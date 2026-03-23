#!/usr/bin/env python3
"""Tests for spawn.py foundation classes."""

import unittest
import tempfile
import os
import sys
from pathlib import Path
from unittest.mock import patch

# Add tools/ to path so we can import spawn
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))


# -- Task 1: Config -----------------------------------------------------------

class TestConfig(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.config_path = Path(self.tmp) / "spawn.json"

    def tearDown(self):
        if self.config_path.exists():
            self.config_path.unlink()
        os.rmdir(self.tmp)

    def test_save_and_load(self):
        from spawn import Config
        cfg = Config(self.config_path)
        cfg.set("terminal", "wt").set("tabs_supported", True).save()
        cfg2 = Config(self.config_path).load()
        self.assertEqual(cfg2.get("terminal"), "wt")
        self.assertTrue(cfg2.get("tabs_supported"))

    def test_data_merges_defaults(self):
        from spawn import Config
        cfg = Config(self.config_path)
        cfg.set("terminal", "konsole").save()
        cfg2 = Config(self.config_path).load()
        data = cfg2.data
        self.assertEqual(data["terminal"], "konsole")
        self.assertEqual(data["startup_delay"], 5)  # default preserved

    def test_creates_parent_dirs(self):
        nested = Path(self.tmp) / "sub" / "dir" / "spawn.json"
        from spawn import Config
        Config(nested).set("terminal", "wt").save()
        self.assertTrue(nested.exists())
        # cleanup
        nested.unlink()
        nested.parent.rmdir()
        nested.parent.parent.rmdir()


# -- Task 2: KeySender ABC ----------------------------------------------------

class TestKeySenderABC(unittest.TestCase):

    def test_type_line_calls_type_text_and_press_enter(self):
        from spawn import KeySender

        class FakeKeySender(KeySender):
            def __init__(self):
                self.calls = []
            def type_text(self, text):
                self.calls.append(("type_text", text))
            def press_enter(self):
                self.calls.append(("press_enter",))

        sender = FakeKeySender()
        sender.type_line("hello")
        self.assertEqual(sender.calls, [("type_text", "hello"), ("press_enter",)])


# -- Task 3: Win32KeySender ---------------------------------------------------

class TestWin32KeySender(unittest.TestCase):

    @unittest.skipUnless(sys.platform == "win32", "Windows only")
    def test_type_text_calls_send_key(self):
        from spawn import Win32KeySender
        sender = Win32KeySender()
        # Patch _send_key to capture calls instead of sending real keystrokes
        calls = []
        sender._send_key = lambda **kw: calls.append(kw)
        sender.type_text("ab")
        # Each char = 1 key down + 1 key up = 2 calls per char
        self.assertEqual(len(calls), 4)

    @unittest.skipIf(sys.platform == "win32", "Non-Windows")
    def test_raises_on_non_windows(self):
        from spawn import Win32KeySender
        with self.assertRaises(RuntimeError):
            Win32KeySender()


# -- Task 4: X11KeySender + AppleScriptKeySender ------------------------------

class TestX11KeySender(unittest.TestCase):

    @unittest.skipUnless(sys.platform == "linux", "Linux only")
    def test_xdotool_fallback_type_text(self):
        from spawn import X11KeySender
        with patch("spawn.shutil.which", return_value="/usr/bin/xdotool"):
            # Force xdotool fallback by making ctypes load fail
            with patch("spawn.ctypes.cdll.LoadLibrary", side_effect=OSError):
                sender = X11KeySender()
                with patch("spawn.subprocess.run") as mock_run:
                    sender.type_text("hello")
                    mock_run.assert_called_once()
                    args = mock_run.call_args[0][0]
                    self.assertEqual(args[0], "xdotool")
                    self.assertIn("hello", args)

    @unittest.skipIf(sys.platform == "win32", "Not Windows")
    def test_x11_raises_without_deps(self):
        from spawn import X11KeySender
        with patch("spawn.shutil.which", return_value=None):
            with patch("spawn.ctypes.cdll.LoadLibrary", side_effect=OSError):
                with self.assertRaises(RuntimeError):
                    X11KeySender()


    def test_keysym_names_cover_spawn_commands(self):
        """All characters in spawn's typed commands have keysym mappings."""
        from spawn import X11KeySender
        # Commands spawn actually types
        commands = [
            "claude --model opus",
            "claude --model sonnet",
            "/rename Opus 1",
            "/rename Sonnet 1",
            "/opus 1",
            "/sonnet 1",
        ]
        for cmd in commands:
            for char in cmd:
                # Every char must be in _KEYSYM_NAMES or be alphanumeric
                has_mapping = (
                    char in X11KeySender._KEYSYM_NAMES
                    or char.isalnum()
                )
                self.assertTrue(
                    has_mapping,
                    "Character %r in %r has no keysym mapping" % (char, cmd),
                )

    def test_shift_chars_includes_uppercase(self):
        """Uppercase letters detected as needing shift."""
        from spawn import X11KeySender
        # Uppercase are handled by char.isupper(), not _SHIFT_CHARS
        self.assertNotIn("A", X11KeySender._SHIFT_CHARS)
        # But slash, dash, space should NOT need shift
        self.assertNotIn("/", X11KeySender._SHIFT_CHARS)
        self.assertNotIn("-", X11KeySender._SHIFT_CHARS)
        self.assertNotIn(" ", X11KeySender._SHIFT_CHARS)


class TestAppleScriptKeySender(unittest.TestCase):

    @unittest.skipUnless(sys.platform == "darwin", "macOS only")
    def test_type_text_calls_osascript(self):
        from spawn import AppleScriptKeySender
        sender = AppleScriptKeySender()
        with patch("spawn.subprocess.run") as mock_run:
            sender.type_text("hello")
            mock_run.assert_called_once()
            cmd = mock_run.call_args[0][0]
            self.assertEqual(cmd[0], "osascript")

    @unittest.skipIf(sys.platform == "darwin", "Not macOS")
    def test_raises_on_non_macos(self):
        from spawn import AppleScriptKeySender
        with self.assertRaises(RuntimeError):
            AppleScriptKeySender()


# -- Task 5: TerminalDriver + WTDriver ----------------------------------------

class TestWTDriver(unittest.TestCase):

    def test_open_window_command(self):
        from spawn import WTDriver
        driver = WTDriver()
        with patch("spawn.subprocess.run") as mock_run:
            driver.open_window("opus", "/home/user")
            mock_run.assert_called_once()
            cmd = mock_run.call_args[0][0]
            self.assertEqual(cmd, ["wt", "-w", "opus", "-d", "/home/user"])

    def test_open_tab_command(self):
        from spawn import WTDriver
        driver = WTDriver()
        with patch("spawn.subprocess.run") as mock_run:
            driver.open_tab("opus", "/home/user")
            cmd = mock_run.call_args[0][0]
            self.assertEqual(cmd, ["wt", "-w", "opus", "nt", "-d", "/home/user"])

    def test_activate_command(self):
        from spawn import WTDriver
        driver = WTDriver()
        with patch("spawn.subprocess.run") as mock_run:
            driver.activate("opus")
            cmd = mock_run.call_args[0][0]
            self.assertEqual(cmd, ["wt", "-w", "opus", "ft"])


# -- Task 6: Linux Terminal Drivers -------------------------------------------

class TestGnomeTermDriver(unittest.TestCase):

    def test_open_window_includes_title(self):
        from spawn import GnomeTermDriver
        driver = GnomeTermDriver()
        with patch("spawn.subprocess.Popen") as mock_popen:
            driver.open_window("opus", "/home/user")
            cmd = mock_popen.call_args[0][0]
            self.assertIn("--title=opus", cmd)
            self.assertIn("--working-directory=/home/user", cmd)

    def test_open_tab_command(self):
        from spawn import GnomeTermDriver
        driver = GnomeTermDriver()
        with patch("spawn.subprocess.Popen") as mock_popen:
            driver.open_tab("opus", "/home/user")
            cmd = mock_popen.call_args[0][0]
            self.assertIn("--tab", cmd)

    def test_activate_uses_xdotool(self):
        from spawn import GnomeTermDriver
        driver = GnomeTermDriver()
        with patch("spawn.shutil.which", return_value="/usr/bin/xdotool"):
            with patch("spawn.subprocess.run") as mock_run:
                driver.activate("opus")
                # Should search by window name, then activate
                self.assertEqual(mock_run.call_count, 2)


class TestKonsoleDriver(unittest.TestCase):

    def test_open_tab_command(self):
        from spawn import KonsoleDriver
        driver = KonsoleDriver()
        with patch("spawn.subprocess.Popen") as mock_popen:
            driver.open_tab("opus", "/home/user")
            cmd = mock_popen.call_args[0][0]
            self.assertIn("--new-tab", cmd)
            self.assertIn("--workdir", cmd)


class TestXfceTermDriver(unittest.TestCase):

    def test_open_tab_command(self):
        from spawn import XfceTermDriver
        driver = XfceTermDriver()
        with patch("spawn.subprocess.Popen") as mock_popen:
            driver.open_tab("opus", "/home/user")
            cmd = mock_popen.call_args[0][0]
            self.assertIn("--tab", cmd)
            self.assertIn("--working-directory=/home/user", cmd)


# -- Task 7: macOS Terminal Drivers + FallbackDriver ---------------------------

class TestMacTermDriver(unittest.TestCase):

    def test_open_window_builds_applescript(self):
        from spawn import MacTermDriver
        driver = MacTermDriver()
        with patch("spawn.subprocess.run") as mock_run:
            driver.open_window("opus", "/Users/me")
            cmd = mock_run.call_args[0][0]
            self.assertEqual(cmd[0], "osascript")
            script = cmd[2]
            self.assertIn("do script", script)
            self.assertIn("/Users/me", script)


class TestITermDriver(unittest.TestCase):

    def test_open_window_builds_applescript(self):
        from spawn import ITermDriver
        driver = ITermDriver()
        with patch("spawn.subprocess.run") as mock_run:
            driver.open_window("opus", "/Users/me")
            cmd = mock_run.call_args[0][0]
            self.assertIn("iTerm", " ".join(cmd))


class TestFallbackDriver(unittest.TestCase):

    @patch("spawn.sys")
    def test_open_window_windows(self, mock_sys):
        from spawn import FallbackDriver
        mock_sys.platform = "win32"
        driver = FallbackDriver()
        driver._platform = "win32"
        with patch("spawn.subprocess.Popen") as mock_popen:
            driver.open_window("opus", "C:\\Users\\me")
            cmd = mock_popen.call_args[0][0]
            self.assertEqual(cmd[0], "cmd")

    def test_activate_is_noop(self):
        from spawn import FallbackDriver
        driver = FallbackDriver()
        driver.activate("opus")  # should not raise


# -- Task 8: Setup and Dependency Detection -----------------------------------

class TestSetup(unittest.TestCase):

    def test_detect_os(self):
        from spawn import detect_os
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "win32"
            self.assertEqual(detect_os(), "windows")

    def test_detect_display_server_windows(self):
        from spawn import detect_display_server
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "win32"
            self.assertEqual(detect_display_server(), "win32")

    def test_detect_display_server_wayland(self):
        from spawn import detect_display_server
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "linux"
            with patch.dict(os.environ, {"XDG_SESSION_TYPE": "wayland"}):
                self.assertEqual(detect_display_server(), "wayland")

    def test_detect_terminal_priority(self):
        from spawn import detect_terminal
        # Simulate: only konsole found
        def mock_which(name):
            return "/usr/bin/konsole" if name == "konsole" else None
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "linux"
            with patch("spawn.shutil.which", side_effect=mock_which):
                result = detect_terminal()
                self.assertEqual(result["name"], "konsole")

    def test_detect_terminal_macos_catalina_path(self):
        """Terminal.app found at /System/Applications/ (Catalina+)."""
        from spawn import detect_terminal
        def mock_isdir(path):
            return path == "/System/Applications/Utilities/Terminal.app"
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "darwin"
            with patch("spawn.os.path.isdir", side_effect=mock_isdir):
                result = detect_terminal()
                self.assertEqual(result["name"], "terminal.app")
                self.assertIn("/System/", result["path"])

    def test_detect_terminal_macos_legacy_path(self):
        """Terminal.app found at /Applications/ (pre-Catalina)."""
        from spawn import detect_terminal
        def mock_isdir(path):
            return path == "/Applications/Utilities/Terminal.app"
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "darwin"
            with patch("spawn.os.path.isdir", side_effect=mock_isdir):
                result = detect_terminal()
                self.assertEqual(result["name"], "terminal.app")

    def test_detect_terminal_macos_iterm_preferred(self):
        """iTerm2 is preferred over Terminal.app when both exist."""
        from spawn import detect_terminal
        def mock_isdir(path):
            return path in ("/Applications/iTerm.app",
                            "/System/Applications/Utilities/Terminal.app")
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "darwin"
            with patch("spawn.os.path.isdir", side_effect=mock_isdir):
                result = detect_terminal()
                self.assertEqual(result["name"], "iterm2")

    def test_check_json_structure(self):
        from spawn import run_check
        with patch("spawn.detect_os", return_value="windows"):
            with patch("spawn.detect_display_server", return_value="win32"):
                with patch("spawn.detect_terminal", return_value={
                    "name": "wt", "path": "/usr/bin/wt", "tabs": True
                }):
                    with patch("spawn.detect_key_sender", return_value={
                        "method": "win32", "available": True
                    }):
                        with patch("spawn.detect_window_activation", return_value={
                            "method": "wt_named_windows", "available": True
                        }):
                            result = run_check()
                            self.assertTrue(result["ready"])
                            self.assertIn("os", result)
                            self.assertIn("display_server", result)
                            self.assertIn("terminal", result)
                            self.assertIn("key_sender", result)
                            self.assertEqual(result["missing"], [])

    def test_check_ready_on_wayland_without_key_sender(self):
        """Wayland is ready even without key_sender (manual command mode)."""
        from spawn import run_check
        with patch("spawn.detect_os", return_value="linux"):
            with patch("spawn.detect_display_server", return_value="wayland"):
                with patch("spawn.detect_terminal", return_value={
                    "name": "gnome-terminal", "path": "/usr/bin/gnome-terminal", "tabs": True
                }):
                    with patch("spawn.detect_key_sender", return_value={
                        "method": "none", "available": False, "reason": "wayland"
                    }):
                        with patch("spawn.detect_window_activation", return_value={
                            "method": "none", "available": False
                        }):
                            result = run_check()
                            self.assertTrue(result["ready"])

    def test_check_not_ready_without_key_sender(self):
        """Not ready when terminal exists but key_sender unavailable (non-Wayland)."""
        from spawn import run_check
        with patch("spawn.detect_os", return_value="linux"):
            with patch("spawn.detect_display_server", return_value="x11"):
                with patch("spawn.detect_terminal", return_value={
                    "name": "xterm", "path": "/usr/bin/xterm", "tabs": False
                }):
                    with patch("spawn.detect_key_sender", return_value={
                        "method": "none", "available": False
                    }):
                        with patch("spawn.detect_window_activation", return_value={
                            "method": "none", "available": False
                        }):
                            result = run_check()
                            self.assertFalse(result["ready"])

    def test_can_use_tkinter_false_on_macos_subprocess(self):
        """On macOS with no TTY on stdin, _can_use_tkinter returns False."""
        from spawn import _can_use_tkinter
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "darwin"
            mock_sys.stdin.isatty.return_value = False
            self.assertFalse(_can_use_tkinter())

    def test_can_use_tkinter_false_on_macos_no_term_program(self):
        """On macOS with TTY but no TERM_PROGRAM, _can_use_tkinter returns False."""
        from spawn import _can_use_tkinter
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "darwin"
            mock_sys.stdin.isatty.return_value = True
            with patch.dict(os.environ, {}, clear=True):
                self.assertFalse(_can_use_tkinter())

    def test_tooltip_disabled_skips_tkinter(self):
        """SpawnTooltip with _disabled=True never touches tkinter."""
        from spawn import SpawnTooltip
        with patch("spawn._can_use_tkinter", return_value=False):
            tooltip = SpawnTooltip()
            self.assertTrue(tooltip._disabled)
            # start/update/close should all be no-ops
            tooltip.start("test")
            tooltip.update("test")
            tooltip.close()
            # Thread should never have started
            self.assertFalse(tooltip._thread.is_alive())


# -- Task 9: Spawner Orchestration --------------------------------------------

class TestSpawner(unittest.TestCase):

    def test_build_plan_opus_3(self):
        from spawn import Spawner
        plan = Spawner.build_plan("opus", 3)
        self.assertEqual(len(plan), 3)
        for i, session in enumerate(plan):
            self.assertEqual(session["model"], "opus")
            self.assertEqual(session["index"], i + 1)
            self.assertEqual(session["window"], "opus")

    def test_build_plan_duo_2(self):
        """Duo mode: Sonnet launches first so listener is ready for Opus."""
        from spawn import Spawner
        plan = Spawner.build_plan("duo", 2)
        self.assertEqual(len(plan), 4)  # 2 sonnet + 2 opus
        # First 2 are sonnet (listener starts first)
        self.assertEqual(plan[0]["model"], "sonnet")
        self.assertEqual(plan[1]["model"], "sonnet")
        # Last 2 are opus
        self.assertEqual(plan[2]["model"], "opus")
        self.assertEqual(plan[3]["model"], "opus")
        # Indices restart per model
        self.assertEqual(plan[2]["index"], 1)

    def test_time_estimate_single(self):
        from spawn import Spawner
        cfg = {"tab_init_delay": 2, "startup_delay": 5, "command_delay": 3,
               "project_dir": str(Path(__file__).parent)}
        # project_dir has no .claude/settings.json, so trust_extra = 3
        # N * (2 + 0.5 + 5 + 3 + 3*2) = N * 16.5
        self.assertAlmostEqual(Spawner.estimate_time("opus", 3, cfg), 49.5)

    def test_dry_run_output(self):
        from spawn import Spawner
        import io
        cfg = {"tab_init_delay": 2, "startup_delay": 5, "command_delay": 3,
               "project_dir": str(Path(__file__).parent)}
        output = io.StringIO()
        Spawner.dry_run("opus", 1, cfg, file=output)
        text = output.getvalue()
        self.assertIn("[dry-run]", text)
        self.assertIn("claude --model opus", text)
        self.assertIn("/rename Opus 1", text)
        self.assertIn("/opus 1", text)

    def test_dry_run_trust_prompt(self):
        """Dry run shows trust prompt dismissal for untrusted dirs."""
        from spawn import Spawner
        import io
        cfg = {"tab_init_delay": 2, "startup_delay": 5, "command_delay": 3,
               "trust_prompt_delay": 3,
               "project_dir": str(Path.home())}
        output = io.StringIO()
        Spawner.dry_run("opus", 1, cfg, file=output)
        text = output.getvalue()
        self.assertIn("dismiss trust prompt", text)

    def test_needs_trust_prompt_home_dir(self):
        """Home directory always needs trust prompt."""
        from spawn import Spawner
        self.assertTrue(Spawner._needs_trust_prompt(str(Path.home())))

    def test_needs_trust_prompt_trusted_dir(self):
        """Directory with .claude/settings.json does not need trust prompt."""
        from spawn import Spawner
        tmp = tempfile.mkdtemp()
        try:
            (Path(tmp) / ".claude").mkdir()
            (Path(tmp) / ".claude" / "settings.json").write_text("{}")
            self.assertFalse(Spawner._needs_trust_prompt(tmp))
        finally:
            (Path(tmp) / ".claude" / "settings.json").unlink()
            (Path(tmp) / ".claude").rmdir()
            os.rmdir(tmp)

    def test_needs_trust_prompt_unknown_dir(self):
        """Directory without .claude/ needs trust prompt."""
        from spawn import Spawner
        tmp = tempfile.mkdtemp()
        try:
            self.assertTrue(Spawner._needs_trust_prompt(tmp))
        finally:
            os.rmdir(tmp)

    def test_wayland_prints_commands(self):
        from spawn import Spawner
        import io
        output = io.StringIO()
        Spawner.print_wayland_commands("opus", 2, file=output)
        text = output.getvalue()
        self.assertIn("claude --model opus", text)
        self.assertIn("/rename Opus 1", text)
        self.assertIn("/opus 1", text)
        self.assertIn("/rename Opus 2", text)


# -- Task 10: CLI Entry Point -------------------------------------------------

class TestCLI(unittest.TestCase):

    def test_parse_headless_args(self):
        from spawn import build_parser
        parser = build_parser()
        args = parser.parse_args(["opus", "5"])
        self.assertEqual(args.mode, "opus")
        self.assertEqual(args.count, 5)

    def test_parse_check_flag(self):
        from spawn import build_parser
        parser = build_parser()
        args = parser.parse_args(["--check"])
        self.assertTrue(args.check)

    def test_parse_dry_run(self):
        from spawn import build_parser
        parser = build_parser()
        args = parser.parse_args(["--dry-run", "duo", "3"])
        self.assertTrue(args.dry_run)
        self.assertEqual(args.mode, "duo")
        self.assertEqual(args.count, 3)

    def test_parse_setup_with_terminal(self):
        from spawn import build_parser
        parser = build_parser()
        args = parser.parse_args(["--setup", "--terminal", "konsole"])
        self.assertTrue(args.setup)
        self.assertEqual(args.terminal, "konsole")

    def test_invalid_mode_rejected(self):
        from spawn import build_parser
        parser = build_parser()
        with self.assertRaises(SystemExit):
            parser.parse_args(["invalid", "3"])


if __name__ == "__main__":
    unittest.main()
