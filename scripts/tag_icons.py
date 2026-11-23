#!/usr/bin/env python3
"""Tag icons by what they show, for search. Claude Code subagents do the looking; this script prepares their work and collects it.

Usage:
  python3 scripts/tag_icons.py prepare [--chunks N]  # export untagged icons as chunks of 100 (needs Pillow: run with devc)
  python3 scripts/tag_icons.py prompt c012           # the instructions for the agent tagging chunk c012
  python3 scripts/tag_icons.py status                # tagged, untagged and pending chunks
  python3 scripts/tag_icons.py merge                 # check finished chunks and merge them into scripts/icon_tags.json

Chunks live in .cache/tags/chunks/cNNN/: NNN.png per icon, ids.json (file IDs in order), names.txt (file names), and
tags.json once an agent has written it.
"""

import argparse
import csv
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAGO_CACHE = os.path.join(ROOT, ".cache", "wago")
ICONS = os.path.join(ROOT, ".cache", "icons")
CHUNKS = os.path.join(ROOT, ".cache", "tags", "chunks")
TAGS = os.path.join(ROOT, "scripts", "icon_tags.json")
PROMPT = os.path.join(ROOT, "scripts", "tag_prompt.md")
CHUNK_SIZE = 100

# Both clients' icon pickers offer exactly the Interface\Icons files named like this (checked against in-game exports).
PICKER_NAME = re.compile(r"(inv|ability|spell)_", re.IGNORECASE)
WORD = re.compile(r"[a-z]+")


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def icon_names():
    """File ID → file name (without .blp) of every Interface\\Icons file in the cached retail and WoW Forever manifests."""
    names = {}
    for branch in ("wow", "wowf"):
        path = os.path.join(WAGO_CACHE, f"{branch}-ManifestInterfaceData.csv")
        if not os.path.exists(path):
            sys.exit(f"missing {path}; run scripts/build_data.py first")
        with open(path, encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                if row["FilePath"].lower().replace("/", "\\").startswith("interface\\icons"):
                    names.setdefault(int(row["ID"]), re.sub(r"\.blp$", "", row["FileName"], flags=re.IGNORECASE))
    return names


def wanted(names):
    return {i for i, name in names.items() if PICKER_NAME.match(name)}


def load_tags():
    if not os.path.exists(TAGS):
        return {}
    with open(TAGS, encoding="utf-8") as handle:
        return {int(k): clean_entry(v)[0] for k, v in json.load(handle).items()}


def save_tags(tags):
    lines = [f"{json.dumps(str(i))}: {json.dumps(tags[i])}" for i in sorted(tags)]
    with open(TAGS, "w", encoding="utf-8") as handle:
        handle.write("{\n" + ",\n".join(lines) + "\n}\n")


def chunks():
    """(name, path, ids) of every chunk folder, in order."""
    if not os.path.isdir(CHUNKS):
        return []
    out = []
    for name in sorted(os.listdir(CHUNKS)):
        path = os.path.join(CHUNKS, name)
        ids_path = os.path.join(path, "ids.json")
        if re.fullmatch(r"c\d+", name) and os.path.exists(ids_path):
            with open(ids_path, encoding="utf-8") as handle:
                out.append((name, path, json.load(handle)))
    return out


def words(values):
    """Lowercase single words; agents sometimes write two-word names like "magnifying glass"."""
    out = []
    for value in values:
        for word in WORD.findall(str(value).lower()):
            if word not in out:
                out.append(word)
    return out


def clean_entry(entry):
    """(tags, problem) of one icon's entry: a list of words, or an older {main, minor} entry read main first."""
    if isinstance(entry, dict) and isinstance(entry.get("main"), list) and isinstance(entry.get("minor"), list):
        entry = entry["main"] + entry["minor"]
    if not isinstance(entry, list):
        return None, "not a list of words"
    tags = words(entry)
    return (tags, None) if tags else (None, "no words")


def read_chunk(path, ids):
    """(tags by file ID, problems) of a finished chunk; None when its agent hasn't written tags.json yet."""
    tags_path = os.path.join(path, "tags.json")
    if not os.path.exists(tags_path):
        return None
    try:
        with open(tags_path, encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as error:
        return {}, [f"tags.json: {error}"]
    good, problems = {}, []
    for n, file_id in enumerate(ids, 1):
        entry = data.get(str(n))
        tags, problem = (None, "missing") if entry is None else clean_entry(entry)
        if problem:
            problems.append(f"{n:03d}: {problem}")
        else:
            good[file_id] = tags
    return good, problems


def prepare(args):
    from PIL import Image

    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    from build_colors import open_icon

    names = icon_names()
    tags = load_tags()
    want = wanted(names)
    pending = set()
    for name, path, ids in chunks():
        result = read_chunk(path, ids)
        if result is None:
            pending.update(ids)
        elif any(tags.get(i) != t for i, t in result[0].items() if i in want):
            sys.exit(f"{name} is done but not merged; run merge first, or prepare hands out its icons again")
    todo = sorted(i for i in wanted(names) - set(tags) - pending if os.path.exists(os.path.join(ICONS, f"{i}.blp")))
    missing = len(wanted(names) - set(tags) - pending) - len(todo)
    if missing:
        log(f"{missing} untagged icons have no image in .cache/icons; run scripts/extract_icons.py")
    existing = [int(name[1:]) for name, _, _ in chunks()]
    first = max(existing) + 1 if existing else 0
    queue = iter(todo)
    written = unreadable = 0
    for k in range(args.chunks):
        path = os.path.join(CHUNKS, f"c{first + k:03d}")
        os.makedirs(path, exist_ok=True)
        ids = []
        for file_id in queue:
            try:
                icon = open_icon(os.path.join(ICONS, f"{file_id}.blp"))
            except Exception:
                # Some cached files are empty or encrypted placeholders; they stay untagged.
                unreadable += 1
                continue
            ids.append(file_id)
            image = Image.new("RGB", icon.size, (30, 30, 30))
            image.paste(icon, (0, 0), icon)
            image.save(os.path.join(path, f"{len(ids):03d}.png"))
            if len(ids) == CHUNK_SIZE:
                break
        if not ids:
            os.rmdir(path)
            break
        with open(os.path.join(path, "ids.json"), "w", encoding="utf-8") as handle:
            json.dump(ids, handle)
        with open(os.path.join(path, "names.txt"), "w", encoding="utf-8") as handle:
            handle.writelines(f"{n:03d} {names[i]}\n" for n, i in enumerate(ids, 1))
        print(os.path.basename(path))
        written += 1
    if unreadable:
        log(f"skipped {unreadable} icons whose image can't be read")
    log(f"{written} chunks written; {len(list(queue))} untagged icons left for later chunks")


def prompt(args):
    for name, path, ids in chunks():
        if name == args.chunk:
            with open(PROMPT, encoding="utf-8") as handle:
                print(handle.read().format(chunk=path, last=len(ids)), end="")
            return
    sys.exit(f"no chunk {args.chunk} in {CHUNKS}")


def status(_args):
    names = icon_names()
    tags = load_tags()
    want = wanted(names)
    print(f"tagged {len(want & set(tags))} of {len(want)} picker icons")
    for name, path, ids in chunks():
        result = read_chunk(path, ids)
        if result is None:
            print(f"{name}: waiting for its agent")
        elif result[1]:
            print(f"{name}: {len(result[1])} problems")
        elif any(tags.get(i) != t for i, t in result[0].items() if i in want):
            print(f"{name}: done, not merged")


def merge(_args):
    want = wanted(icon_names())
    tags = load_tags()
    merged = 0
    for name, path, ids in chunks():
        result = read_chunk(path, ids)
        if result is None:
            continue
        good, problems = result
        for problem in problems:
            log(f"{name} {problem}")
        good = {i: t for i, t in good.items() if i in want and tags.get(i) != t}
        tags.update(good)
        merged += len(good)
    dropped = [i for i in tags if i not in want]
    for i in dropped:
        del tags[i]
    if dropped:
        log(f"dropped {len(dropped)} icons the pickers don't offer")
    save_tags(tags)
    log(f"merged {merged} icons from finished chunks; {len(tags)} icons in {os.path.relpath(TAGS, ROOT)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare", help="export untagged icons as chunks")
    p.add_argument("--chunks", type=int, default=10, help="how many chunks of 100 to write (default 10)")
    p.set_defaults(run=prepare)
    p = sub.add_parser("prompt", help="print the agent instructions for a chunk")
    p.add_argument("chunk", help="chunk name, e.g. c012")
    p.set_defaults(run=prompt)
    sub.add_parser("status", help="show progress").set_defaults(run=status)
    sub.add_parser("merge", help="merge finished chunks into scripts/icon_tags.json").set_defaults(run=merge)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
