"""Explicit isolated comparison; never run against the installed app."""
import os
import sys
from pathlib import Path

if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
    raise SystemExit("Disposable GitHub-hosted runner only")
p = Path(sys.argv[1])
s = p.read_text()
old = """    [NSApp activate];
    [window makeKeyAndOrderFront:nil];
    // Activation is cooperative/asynchronous on recent macOS. Explicit opening
    // should still reveal the panel at normal level, without a focus-poll timer.
    [window orderFrontRegardless];"""
new = """    [window makeKeyAndOrderFront:nil];
    [NSApp activate];"""
if s.count(old) != 1:
    raise SystemExit("Expected exact baseline presentation sequence once")
p.write_text(s.replace(old, new))
