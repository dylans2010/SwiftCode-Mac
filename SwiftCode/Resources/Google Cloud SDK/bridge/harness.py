"""
Resolution of the Antigravity `localharness` binary.

The SDK wheel ships the harness as `localharness.gz`. Unpacking it next to the
gzip would write into the signed, possibly read-only application bundle, so the
binary is unpacked once into the user's Application Support directory instead
and `ANTIGRAVITY_HARNESS_PATH` is pointed at that copy.
"""

from __future__ import annotations

import gzip
import hashlib
import logging
import os
import shutil
import tempfile
from typing import Optional

logger = logging.getLogger("AntigravityHarness")


def _default_support_dir() -> str:
    override = os.environ.get("SWIFTCODE_SDK_SUPPORT_DIR")
    if override:
        return override
    return os.path.join(
        os.path.expanduser("~"),
        "Library",
        "Application Support",
        "SwiftCode",
        "GoogleCloudSDK",
    )


def _fingerprint(path: str) -> str:
    st = os.stat(path)
    digest = hashlib.sha256(f"{st.st_size}:{int(st.st_mtime)}".encode("utf-8")).hexdigest()
    return digest[:16]


def ensure_harness(site_packages: str) -> Optional[str]:
    """Returns a usable harness path, unpacking it outside the bundle if needed.

    Respects an explicit, existing `ANTIGRAVITY_HARNESS_PATH`. Returns None when
    no harness can be located; the SDK then falls back to its own discovery and
    reports a descriptive error when the session starts.
    """
    explicit = os.environ.get("ANTIGRAVITY_HARNESS_PATH")
    if explicit and os.path.isfile(explicit) and os.path.getsize(explicit) > 0:
        return explicit

    bin_dir = os.path.join(site_packages, "google", "antigravity", "bin")
    bundled = os.path.join(bin_dir, "localharness")
    if os.path.isfile(bundled) and os.path.getsize(bundled) > 0 and os.access(bundled, os.X_OK):
        os.environ["ANTIGRAVITY_HARNESS_PATH"] = bundled
        return bundled

    gz_path = os.path.join(bin_dir, "localharness.gz")
    if not os.path.isfile(gz_path):
        logger.warning("No localharness binary or archive found in %s", bin_dir)
        return None

    target_dir = os.path.join(_default_support_dir(), "bin", _fingerprint(gz_path))
    target = os.path.join(target_dir, "localharness")
    if os.path.isfile(target) and os.path.getsize(target) > 0 and os.access(target, os.X_OK):
        os.environ["ANTIGRAVITY_HARNESS_PATH"] = target
        return target

    try:
        os.makedirs(target_dir, exist_ok=True)
        # Unpack to a temp file in the same directory, then atomically rename so a
        # concurrently starting bridge never sees a partially written binary.
        fd, tmp_path = tempfile.mkstemp(prefix=".localharness-", dir=target_dir)
        try:
            with os.fdopen(fd, "wb") as f_out, gzip.open(gz_path, "rb") as f_in:
                shutil.copyfileobj(f_in, f_out)
            os.chmod(tmp_path, 0o755)
            os.replace(tmp_path, target)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as exc:  # pragma: no cover - depends on the host filesystem
        logger.error("Failed to unpack localharness to %s: %s", target, exc)
        return None

    os.environ["ANTIGRAVITY_HARNESS_PATH"] = target
    logger.info("Unpacked localharness to %s", target)
    return target
