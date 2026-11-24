"""Paths, logging and the icon manifest scan shared by the scripts in scripts/."""

import csv
import functools
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache")
WAGO_CACHE = os.path.join(CACHE, "wago")
ICON_CACHE = os.path.join(CACHE, "icons")
BRANCHES = ("wow", "wowf")

# The Interface\Icons files both clients' icon pickers offer by name (checked against in-game exports).
PICKER_NAME = re.compile(r"(inv|ability|spell)_", re.IGNORECASE)


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def manifest_icons(rows):
    """(file ID, file name without .blp) of every Interface\\Icons file in ManifestInterfaceData rows."""
    for row in rows:
        if row["FilePath"].lower().replace("/", "\\").startswith("interface\\icons"):
            yield int(row["ID"]), re.sub(r"\.blp$", "", row["FileName"], flags=re.IGNORECASE)


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


# Item class:subclass of housing decor, whose icons are 3D renders the pickers leave out.
HOUSING_DECOR = (20, 0)


def unnamed_icon_ids(tables, named):
    """File IDs of item and spell icons that have no file name in `named` (the pickers list them by ID only),
    leaving out icons only housing decor uses. `tables` maps a table name to its rows."""
    appearance_icon = {_int(r["ID"]): _int(r["DefaultIconFileDataID"]) for r in tables["ItemAppearance"]}
    item_appearance = {}
    for row in sorted(tables["ItemModifiedAppearance"], key=lambda r: _int(r["OrderIndex"]), reverse=True):
        item_appearance[_int(row["ItemID"])] = _int(row["ItemAppearanceID"])
    used = {_int(r["SpellIconFileDataID"]) for r in tables["SpellMisc"]}
    for row in tables["Item"]:
        if (_int(row["ClassID"]), _int(row["SubclassID"])) != HOUSING_DECOR:
            used.add(_int(row["IconFileDataID"]))
            used.add(appearance_icon.get(item_appearance.get(_int(row["ID"])), 0))
    return {i for i in used if i and i not in named}


@functools.lru_cache
def cached_unnamed_icon_ids(branches=BRANCHES):
    """unnamed_icon_ids over the cached wago tables of every branch."""
    named = cached_icon_names(branches)
    ids = set()
    for branch in branches:
        tables = {}
        for table in ("Item", "ItemAppearance", "ItemModifiedAppearance", "SpellMisc"):
            path = os.path.join(WAGO_CACHE, f"{branch}-{table}.csv")
            if not os.path.exists(path):
                sys.exit(f"missing {path}; run scripts/build_data.py first")
            with open(path, encoding="utf-8", newline="") as handle:
                tables[table] = list(csv.DictReader(handle))
        ids |= unnamed_icon_ids(tables, named)
    return ids


def cached_icon_names(branches=BRANCHES, missing_ok=False):
    """File ID -> file name of every Interface\\Icons file in the cached manifests, the first branch's name winning.
    With `missing_ok`, a branch not downloaded yet is skipped."""
    names = {}
    for branch in branches:
        path = os.path.join(WAGO_CACHE, f"{branch}-ManifestInterfaceData.csv")
        if not os.path.exists(path):
            if missing_ok:
                continue
            sys.exit(f"missing {path}; run scripts/build_data.py first")
        with open(path, encoding="utf-8", newline="") as handle:
            for file_id, name in manifest_icons(csv.DictReader(handle)):
                names.setdefault(file_id, name)
    return names
