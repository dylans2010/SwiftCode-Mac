#!/usr/bin/env python3
"""Unit tests for the pure validation logic of SDKSandboxedTerminal.

No Swift toolchain exists in this environment, so the pure, side-effect-free
pieces of `SDKSandboxedTerminal.swift` are ported here faithfully and tested:

  1. Command-form classification: bare allow-listed name
     (`^[A-Za-z0-9._-]{1,64}$`), absolute path (starts with "/"), or reject
     (shell snippets, relative paths, whitespace, empty).
  2. Directory containment (`isPath(_:insideDirectory:)`): standardized
     prefix match with a trailing slash, so "/usr/bin2/x" never matches
     "/usr/bin".
  3. Working-directory confinement: standardized resolution must land equal
     to or inside the scope root (`..` escapes rejected).
  4. Bounded pipe capture: keep at most `limit` bytes, count ALL bytes read,
     flag truncation honestly.
  5. Timeout clamping: non-positive/non-finite -> default 30 s; clamp to
     [1, 55] s.
  6. Sanitized environment: fixed key set, nothing inherited.
  7. argv sanity caps: count, per-element bytes, NUL rejection.

Coupling guard: the tests first read `SDKSandboxedTerminal.swift` and
assert the ported constants (regex, limits, approved directories) are
identical to the Swift source. If the Swift policy changes, this test fails
until the port is updated — the port can never silently drift.

Only the pure logic is ported. Process spawning, the broker, the timeout
race, and SIGKILL escalation are NOT portable and are verified by
xcodebuild + a live run on Dylan's Mac (see agent_notes.md).

Run: python3 SwiftCode/SDK/Host/ServiceAdapters/Terminal/sandbox_validation_test.py
"""

import os
import re
import sys
import unittest

SWIFT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "SDKSandboxedTerminal.swift")


def read_swift() -> str:
    with open(SWIFT_FILE, "r", encoding="utf-8") as f:
        return f.read()


def extract_string_constant(src: str, name: str) -> str:
    m = re.search(r'static let ' + re.escape(name) + r'[^=]*=\s*"([^"]+)"', src)
    assert m, f"Swift constant {name} not found"
    return m.group(1)


def extract_int_constant(src: str, name: str) -> int:
    m = re.search(r'static let ' + re.escape(name) + r'[^=]*=\s*([0-9_]+(?:\s*\*\s*[0-9_]+)?)', src)
    assert m, f"Swift constant {name} not found"
    expr = m.group(1).replace("_", "")
    value = 1
    for part in expr.split("*"):
        value *= int(part.strip())
    return value


def extract_double_constant(src: str, name: str) -> float:
    m = re.search(r'static let ' + re.escape(name) + r'[^=]*=\s*([0-9.]+)', src)
    assert m, f"Swift constant {name} not found"
    return float(m.group(1))


def extract_string_array(src: str, name: str):
    m = re.search(r'static let ' + re.escape(name) + r'[^=]*=\s*\[(.*?)\]',
                  src, re.DOTALL)
    assert m, f"Swift constant {name} not found"
    return re.findall(r'"([^"]+)"', m.group(1))


# --- Faithful ports of the Swift logic -------------------------------------

def is_bare_name(command: str, pattern: str) -> bool:
    # Swift: command.range(of: pattern, options: .regularExpression) != nil
    return re.search(pattern, command) is not None


def classify_command(command: str, pattern: str) -> str:
    # Returns "bare" | "absolute" | "reject", mirroring resolveExecutable's
    # dispatch (allow-list membership itself is host data, tested below).
    if command.startswith("/"):
        return "absolute"
    if is_bare_name(command, pattern):
        return "bare"
    return "reject"


def path_inside_directory(path: str, directory: str) -> bool:
    # Swift isPath(_:insideDirectory:): standardized paths, trailing-slash
    # prefix so "/usr/bin2/x" never matches "/usr/bin".
    dir_path = os.path.normpath(directory)
    prefix = dir_path if dir_path.endswith("/") else dir_path + "/"
    norm = os.path.normpath(path)
    return norm == dir_path or norm.startswith(prefix)


def resolve_working_directory(requested: str | None, scope_root: str):
    # Mirrors resolveWorkingDirectory: relative anchors at scope root,
    # standardize, then require equal-to-or-inside scope.
    scope = os.path.normpath(scope_root)
    if requested is None:
        candidate = scope
    else:
        if not requested:
            raise ValueError("empty")
        candidate = requested if requested.startswith("/") \
            else os.path.join(scope, requested)
    resolved = os.path.normpath(candidate)
    if not path_inside_directory(resolved, scope):
        raise PermissionError("outside scope")
    return resolved


def capture_bounded(chunks: list[bytes], limit: int):
    # Mirrors captureBounded: keep <= limit bytes, count everything.
    kept = bytearray()
    total = 0
    for chunk in chunks:
        total += len(chunk)
        if len(kept) < limit:
            kept += chunk[:limit - len(kept)]
    return bytes(kept), total, total > limit


def clamp_timeout(requested: float | None, default: float,
                  minimum: float, maximum: float) -> float:
    # Mirrors the request/timeout handling in run(...).
    import math
    t = requested if (requested is not None and math.isfinite(requested)
                     and requested > 0) else default
    return min(max(t, minimum), maximum)


def sanitized_environment(home: str) -> dict:
    # Mirrors sanitizedEnvironment: fixed dict, nothing inherited.
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
        "HOME": home,
        "TMPDIR": "/tmp/",
    }


def validate_args(args: list, max_count: int, max_bytes: int) -> list:
    if len(args) > max_count:
        raise ValueError("too many")
    for arg in args:
        if not isinstance(arg, str):
            raise ValueError("non-string")
        if "\0" in arg:
            raise ValueError("nul")
        if len(arg.encode("utf-8")) > max_bytes:
            raise ValueError("too big")
    return args


class CouplingTest(unittest.TestCase):
    """The port must match the Swift source exactly."""

    def test_constants_match_swift(self):
        src = read_swift()
        self.assertEqual("^[A-Za-z0-9._-]{1,64}$",
                         extract_string_constant(src, "bareNamePattern"))
        self.assertEqual(256 * 1024, extract_int_constant(src, "outputByteLimit"))
        self.assertEqual(30.0, extract_double_constant(src, "defaultTimeoutSeconds"))
        self.assertEqual(1.0, extract_double_constant(src, "minimumTimeoutSeconds"))
        self.assertEqual(55.0, extract_double_constant(src, "maximumTimeoutSeconds"))
        self.assertEqual(4, extract_int_constant(src, "maxConcurrentRunsPerExtension"))
        self.assertEqual(256, extract_int_constant(src, "maxArgumentCount"))
        self.assertEqual(8 * 1024, extract_int_constant(src, "maxArgumentBytes"))
        self.assertEqual(
            ["/usr/bin", "/bin", "/usr/local/bin", "/opt/homebrew/bin",
             "/usr/sbin", "/sbin"],
            extract_string_array(src, "approvedExecutableDirectories"))
        # No shell anywhere in the launch path.
        self.assertNotIn('"/bin/sh"', src)
        self.assertNotIn('"/bin/bash"', src)
        self.assertNotIn('"/bin/zsh"', src)
        # Timeout escalation is real SIGKILL, not theater.
        self.assertIn("SIGKILL", src)
        self.assertRegex(src, r'\bkill\(.*SIGKILL\)')
        self.assertIn("process.terminate()", src)
        # Broker authorization happens on every call, first.
        self.assertIn("SDKCapabilityBroker.authorize(.terminalSandbox, for: caller)", src)
        # Environment is fixed, not inherited.
        self.assertNotIn("ProcessInfo.processInfo.environment", src)

    def test_no_terminal_view_wrapping(self):
        src = read_swift()
        # Strip // comments: the file documents WHY it does not use the
        # terminal views; only actual code references count.
        code = re.sub(r'//.*', '', src)
        self.assertNotIn("TerminalView", code)
        self.assertNotIn("TerminalManager", code)


class CommandClassificationTest(unittest.TestCase):
    PATTERN = "^[A-Za-z0-9._-]{1,64}$"

    def test_bare_names(self):
        for good in ["git", "python3", "xcode-build_2.0", "a", "x" * 64]:
            self.assertEqual("bare", classify_command(good, self.PATTERN), good)

    def test_absolute_paths(self):
        for good in ["/usr/bin/git", "/opt/homebrew/bin/node", "/"]:
            self.assertEqual("absolute", classify_command(good, self.PATTERN), good)

    def test_rejects_shell_and_shapes(self):
        for bad in ["", "git; rm -rf /", "ls | grep x", "echo $(whoami)",
                    "echo `whoami`", "a && b", "git status", " bin/git",
                    "bin/git", "../bin/git", "~/bin/git", "git\nstatus",
                    "x" * 65, "git!"]:
            self.assertEqual("reject", classify_command(bad, self.PATTERN), bad)


class ContainmentTest(unittest.TestCase):
    def test_prefix_semantics(self):
        self.assertTrue(path_inside_directory("/usr/bin/git", "/usr/bin"))
        self.assertTrue(path_inside_directory("/usr/bin", "/usr/bin"))
        self.assertFalse(path_inside_directory("/usr/bin2/git", "/usr/bin"))
        self.assertFalse(path_inside_directory("/usr/bingit", "/usr/bin"))
        self.assertFalse(path_inside_directory("/etc/passwd", "/usr/bin"))

    def test_working_directory_confinement(self):
        scope = "/Users/dylan/Projects/MyApp"
        # Default and equal-to-root are fine.
        self.assertEqual(os.path.normpath(scope),
                         resolve_working_directory(None, scope))
        # Relative anchors at scope root.
        self.assertEqual(os.path.normpath(scope + "/sub/dir"),
                         resolve_working_directory("sub/dir", scope))
        # ".." that stays inside is fine; ".." escaping is rejected.
        self.assertEqual(os.path.normpath(scope + "/sub"),
                         resolve_working_directory("sub/../sub", scope))
        with self.assertRaises(PermissionError):
            resolve_working_directory("../Other", scope)
        with self.assertRaises(PermissionError):
            resolve_working_directory("/etc", scope)
        with self.assertRaises(PermissionError):
            resolve_working_directory("/Users/dylan/Projects/MyApp2", scope)
        with self.assertRaises(ValueError):
            resolve_working_directory("", scope)


class CaptureTest(unittest.TestCase):
    def test_no_truncation(self):
        data, total, truncated = capture_bounded([b"hel", b"lo"], 1024)
        self.assertEqual(b"hello", data)
        self.assertEqual(5, total)
        self.assertFalse(truncated)

    def test_truncation_counts_everything(self):
        data, total, truncated = capture_bounded(
            [b"a" * 100, b"b" * 300, b"c" * 100], 256)
        self.assertEqual(256, len(data))
        self.assertEqual(b"a" * 100 + b"b" * 156, data)
        self.assertEqual(500, total)
        self.assertTrue(truncated)

    def test_exactly_at_limit_is_not_truncated(self):
        data, total, truncated = capture_bounded([b"z" * 256], 256)
        self.assertFalse(truncated)
        self.assertEqual(256, total)


class TimeoutTest(unittest.TestCase):
    def test_clamping(self):
        self.assertEqual(30.0, clamp_timeout(None, 30, 1, 55))
        self.assertEqual(30.0, clamp_timeout(0, 30, 1, 55))
        self.assertEqual(30.0, clamp_timeout(-5, 30, 1, 55))
        self.assertEqual(30.0, clamp_timeout(float("nan"), 30, 1, 55))
        self.assertEqual(30.0, clamp_timeout(float("inf"), 30, 1, 55))
        self.assertEqual(1.0, clamp_timeout(0.2, 30, 1, 55))
        self.assertEqual(55.0, clamp_timeout(600, 30, 1, 55))
        self.assertEqual(10.0, clamp_timeout(10, 30, 1, 55))


class EnvironmentTest(unittest.TestCase):
    def test_fixed_keys_nothing_inherited(self):
        env = sanitized_environment("/scope/root")
        self.assertEqual({"PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"},
                         set(env.keys()))
        self.assertEqual("/scope/root", env["HOME"])
        # A hostile ambient variable can never leak in: the function takes
        # no ambient input at all.
        import inspect
        self.assertEqual(["home"], list(inspect.signature(sanitized_environment).parameters))


class ArgsTest(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(["a", "b"], validate_args(["a", "b"], 256, 8192))

    def test_caps(self):
        with self.assertRaises(ValueError):
            validate_args(["x"] * 257, 256, 8192)
        with self.assertRaises(ValueError):
            validate_args(["x" * 8193], 256, 8192)
        with self.assertRaises(ValueError):
            validate_args(["a\0b"], 256, 8192)
        with self.assertRaises(ValueError):
            validate_args([42], 256, 8192)


if __name__ == "__main__":
    unittest.main(verbosity=2)
