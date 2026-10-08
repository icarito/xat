#!/usr/bin/env python3
"""Check that downloaded Android templates contain xat's native module markers."""

import sys
import zipfile

LIBRARY = "lib/arm64-v8a/libgodot_android.so"
MARKERS = (
    b"XmppConnection",
    b"SQLiteBinding",
    b"SQLiteQuery",
    b"add_inline_image",
)


def check(path: str) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            try:
                engine = archive.read(LIBRARY)
            except KeyError as exc:
                raise ValueError(f"missing {LIBRARY}; template has no ARM64 Android engine") from exc
    except (OSError, zipfile.BadZipFile) as exc:
        raise ValueError(f"cannot read Android template {path}: {exc}") from exc

    missing = [marker.decode() for marker in MARKERS if marker not in engine]
    if missing:
        raise ValueError(
            f"{path}: native module markers missing from {LIBRARY}: {', '.join(missing)}; "
            "publish templates built with modules/xmpp and the source-preserving emoji patch"
        )
    print(f"ANDROID_TEMPLATE_MARKERS_OK: {path}")


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <template.apk> [<template.apk> ...]", file=sys.stderr)
        return 2
    try:
        for path in sys.argv[1:]:
            check(path)
    except ValueError as exc:
        print(f"ANDROID_TEMPLATE_PREFLIGHT_FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
