#!/usr/bin/env python3
"""Idempotently patch khalti_checkout_flutter's in-app webview AppBar.

The SDK hardcodes a light AppBar background (0xFFE8F0F7) while the title and
refresh-icon colors follow the app theme, so in dark mode the "Pay with
Khalti" header is unreadable. This pins explicit dark colors on both.

Same transformation build_apk.sh used to apply via sed; now repo-side so
BOTH build paths get it:
  - Android: ~/workspace/flutter-build/build_apk.sh calls this script
  - iOS:     codemagic.yaml runs it after `flutter pub get`

Idempotent: safe to run on every build. No-op when already applied, when
the SDK is absent from the pub cache, or when a future SDK version changes
the patched lines (prints a warning in that case).
"""

import glob
import os
import sys

# (pristine_snippet, patched_snippet)
REPLACEMENTS = [
    (
        "title: const Text(s_payWithKhalti),",
        "title: const Text(s_payWithKhalti, "
        "style: TextStyle(color: Color(0xFF1A1A1A))),",
    ),
    (
        "icon: const Icon(Icons.refresh),",
        "icon: const Icon(Icons.refresh, color: Color(0xFF1A1A1A)),",
    ),
]

TARGET_REL = os.path.join(
    "lib", "src", "widget", "khalti_webview.dart"
)


def patch_file(path: str) -> str:
    """Returns 'applied', 'noop', or 'unmatched'."""
    with open(path, encoding="utf-8") as f:
        src = f.read()
    original = src
    matched_any = False
    for old, new in REPLACEMENTS:
        if new in src:
            matched_any = True
            continue  # already applied
        if old in src:
            matched_any = True
            src = src.replace(old, new)
    if not matched_any:
        return "unmatched"
    if src != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        return "applied"
    return "noop"


def main() -> int:
    pattern = os.path.join(
        os.path.expanduser("~"),
        ".pub-cache",
        "hosted",
        "pub.dev",
        "khalti_checkout_flutter-*",
        TARGET_REL,
    )
    files = sorted(glob.glob(pattern))
    if not files:
        print("khalti-patch: khalti_checkout_flutter not in pub-cache "
              "(skipped, exit 0)")
        return 0
    for path in files:
        result = patch_file(path)
        if result == "applied":
            print(f"khalti-patch: applied to {path}")
        elif result == "noop":
            print(f"khalti-patch: already applied, no-op ({path})")
        else:
            print(f"khalti-patch: WARNING: patched lines not found in "
                  f"{path} — SDK may have changed; header theme NOT fixed",
                  file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
