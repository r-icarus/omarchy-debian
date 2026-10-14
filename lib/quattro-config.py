#!/usr/bin/env python3
"""Add Debian dock defaults only when absent; retain all existing user settings."""
import json
import pathlib
import sys

current = pathlib.Path(sys.argv[1]).read_text()
config = json.loads(current)
defaults = json.loads(pathlib.Path(sys.argv[2]).read_text())
if not isinstance(config, dict):
    raise SystemExit("shell.json must contain an object")
if "dock" in config:
    sys.stdout.write(current)
else:
    config["dock"] = defaults["dock"]
    print(json.dumps(config, indent=2, ensure_ascii=False))
