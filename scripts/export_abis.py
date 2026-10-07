#!/usr/bin/env python3
"""Export or check compiler-produced ABIs using only Foundry and Python's stdlib."""

import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if an exported ABI is missing or stale")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    contracts = ("LaunchToken", "MossExperimentRegistry")
    stale = False
    for contract in contracts:
        result = subprocess.run(
            ["forge", "inspect", f"src/{contract}.sol:{contract}", "abi", "--json"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
        content = json.dumps(json.loads(result.stdout), indent=2) + "\n"
        destination = root / "docs" / "abi" / f"{contract}.json"
        if args.check:
            if not destination.exists() or destination.read_text(encoding="utf-8") != content:
                print(f"Stale or missing ABI: {destination.relative_to(root)}", file=sys.stderr)
                stale = True
            else:
                print(f"ABI matches: {destination.relative_to(root)}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(content, encoding="utf-8")
            print(f"Exported {destination.relative_to(root)}")
    return int(stale)


if __name__ == "__main__":
    sys.exit(main())
