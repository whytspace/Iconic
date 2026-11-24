"""Paths, logging and the icon manifest scan shared by the scripts in scripts/."""

import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache")
WAGO_CACHE = os.path.join(CACHE, "wago")
ICON_CACHE = os.path.join(CACHE, "icons")
BRANCHES = ("wow", "wowf")

# Both clients' icon pickers offer exactly the Interface\Icons files named like this (checked against in-game exports).
PICKER_NAME = re.compile(r"(inv|ability|spell)_", re.IGNORECASE)


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def manifest_icons(rows):
    """(file ID, file name without .blp) of every Interface\\Icons file in ManifestInterfaceData rows."""
    for row in rows:
        if row["FilePath"].lower().replace("/", "\\").startswith("interface\\icons"):
            yield int(row["ID"]), re.sub(r"\.blp$", "", row["FileName"], flags=re.IGNORECASE)


def cached_icon_names(branches=BRANCHES):
    """File ID -> file name of every Interface\\Icons file in the cached manifests, the first branch's name winning."""
    names = {}
    for branch in branches:
        path = os.path.join(WAGO_CACHE, f"{branch}-ManifestInterfaceData.csv")
        if not os.path.exists(path):
            sys.exit(f"missing {path}; run scripts/build_data.py first")
        with open(path, encoding="utf-8", newline="") as handle:
            for file_id, name in manifest_icons(csv.DictReader(handle)):
                names.setdefault(file_id, name)
    return names
