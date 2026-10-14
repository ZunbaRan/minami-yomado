#!/usr/bin/env python3
"""Three isolated hypotheses, never a production revision or acceptance result."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

BASE = "6f65a4069181b3f023b7004772f31df8109608f3"
RECIPES = {
    "experiment-normal-bundle": (
        "Info.plist", "\t<key>LSUIElement</key>\n\t<true/>",
        "\t<key>LSUIElement</key>\n\t<false/>",
        "Declare the existing regular application as a normal LaunchServices app."),
    "experiment-sync-intent": (
        "app/PanelPresentation.m", "    if (!window) return;\n    dispatch_async",
        "    if (!window) return;\n    if (NSThread.isMainThread) [NSApp activate];\n    dispatch_async",
        "Request activation synchronously during main-thread user intent; retain the later existing presentation."),
    "experiment-activate-all": (
        "app/PanelPresentation.m", "    [NSApp activate];",
        "    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateAllWindows];",
        "Replace only the existing presenter activation with the public activate-all-windows request."),
}

def transform(source, variant):
    _, old, new, _ = RECIPES[variant]
    if source.count(old) != 1:
        raise ValueError("Expected baseline sequence exactly once")
    return source.replace(old, new)

def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise SystemExit("Disposable GitHub-hosted runner only")
    root, variant = Path(sys.argv[1]), sys.argv[2]
    if variant not in RECIPES:
        raise SystemExit("Unknown diagnostic variant")
    actual = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if actual != BASE:
        raise SystemExit("Unexpected production baseline")
    subprocess.run(["git", "-C", str(root), "diff", "--exit-code"], check=True)
    filename, _, _, purpose = RECIPES[variant]
    target = root / filename
    before = target.read_text()
    after = transform(before, variant)
    target.write_text(after)
    changed = subprocess.check_output(["git", "-C", str(root), "diff", "--name-only"], text=True).splitlines()
    if changed != [filename]:
        raise SystemExit("Unexpected modified file set")
    print(json.dumps({"variant": variant, "baselineRevision": BASE, "purpose": purpose,
        "changedFile": filename, "beforeSHA256": hashlib.sha256(before.encode()).hexdigest(),
        "afterSHA256": hashlib.sha256(after.encode()).hexdigest(),
        "classification": "diagnostic only; not an unchanged production commit"}, indent=2))

if __name__ == "__main__":
    main()
