#!/usr/bin/env python3
"""Tests for spawn.py foundation classes."""

import unittest
import tempfile
import os
import sys
from pathlib import Path
from unittest.mock import patch


# -- Task 1: Config -----------------------------------------------------------

class TestConfig(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.config_path = Path(self.tmp) / "spawn.json"

    def tearDown(self):
        if self.config_path.exists():
            self.config_path.unlink()
        os.rmdir(self.tmp)

    def test_defaults(self):
        from spawn import Config
        cfg = Config(self.config_path)
        cfg.load()
        self.assertEqual(cfg.get("startup_delay"), 3)
        self.assertEqual(cfg.get("command_delay"), 3)
        self.assertEqual(cfg.get("tab_init_delay"), 2)
        self.assertEqual(cfg.get("project_dir"), "")

    def test_save_and_load(self):
        from spawn import Config
        cfg = Config(self.config_path)
        cfg.set("terminal", "wt").set("tabs_supported", True).save()
        cfg2 = Config(self.config_path).load()
        self.assertEqual(cfg2.get("terminal"), "wt")
        self.assertTrue(cfg2.get("tabs_supported"))

    def test_missing_file_returns_defaults(self):
        from spawn import Config
        cfg = Config(self.config_path).load()
        self.assertFalse(cfg.exists())
        self.assertEqual(cfg.get("startup_delay"), 3)

    def test_data_merges_defaults(self):
        from spawn import Config
        cfg = Config(self.config_path)
        cfg.set("terminal", "konsole").save()
        cfg2 = Config(self.config_path).load()
        data = cfg2.data
        self.assertEqual(data["terminal"], "konsole")
        self.assertEqual(data["startup_delay"], 3)  # default preserved

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

    def test_cannot_instantiate_abc(self):
        from spawn import KeySender
        with self.assertRaises(TypeError):
            KeySender()

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
    def test_instantiates_on_windows(self):
        from spawn import Win32KeySender
        sender = Win32KeySender()
        self.assertIsNotNone(sender)

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


# -- Task 5: TerminalDriver ABC + WTDriver ------------------------------------

class TestTerminalDriverABC(unittest.TestCase):

    def test_cannot_instantiate_abc(self):
        from spawn import TerminalDriver
        with self.assertRaises(TypeError):
            TerminalDriver()


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

    def test_detect_os_windows(self):
        from spawn import detect_os
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "win32"
            self.assertEqual(detect_os(), "windows")

    def test_detect_os_linux(self):
        from spawn import detect_os
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "linux"
            self.assertEqual(detect_os(), "linux")

    def test_detect_os_macos(self):
        from spawn import detect_os
        with patch("spawn.sys") as mock_sys:
            mock_sys.platform = "darwin"
            self.assertEqual(detect_os(), "darwin")

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
        from spawn import Spawner
        plan = Spawner.build_plan("duo", 2)
        self.assertEqual(len(plan), 4)  # 2 opus + 2 sonnet
        # First 2 are opus
        self.assertEqual(plan[0]["model"], "opus")
        self.assertEqual(plan[1]["model"], "opus")
        # Last 2 are sonnet
        self.assertEqual(plan[2]["model"], "sonnet")
        self.assertEqual(plan[3]["model"], "sonnet")
        # Indices restart per model
        self.assertEqual(plan[2]["index"], 1)

    def test_time_estimate_single(self):
        from spawn import Spawner
        cfg = {"tab_init_delay": 2, "startup_delay": 3, "command_delay": 3}
        # N * (2 + 0.5 + 3 + 3*2) = N * 11.5
        self.assertAlmostEqual(Spawner.estimate_time("opus", 3, cfg), 34.5)

    def test_time_estimate_duo(self):
        from spawn import Spawner
        cfg = {"tab_init_delay": 2, "startup_delay": 3, "command_delay": 3}
        # Duo 3 = 6 sessions * 11.5 = 69.0
        self.assertAlmostEqual(Spawner.estimate_time("duo", 3, cfg), 69.0)

    def test_dry_run_output(self):
        from spawn import Spawner
        import io
        cfg = {"tab_init_delay": 2, "startup_delay": 3, "command_delay": 3,
               "project_dir": "~/.claude/"}
        output = io.StringIO()
        Spawner.dry_run("opus", 1, cfg, file=output)
        text = output.getvalue()
        self.assertIn("[dry-run]", text)
        self.assertIn("claude --model opus", text)
        self.assertIn("/rename Opus 1", text)
        self.assertIn("/opus 1", text)
        self.assertIn("11.5s", text)

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

    def test_parse_check_json(self):
        from spawn import build_parser
        parser = build_parser()
        args = parser.parse_args(["--check", "--json"])
        self.assertTrue(args.check)
        self.assertTrue(args.json)

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
