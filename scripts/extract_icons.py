#!/usr/bin/env python3
"""Extract icon BLP files from a local World of Warcraft install into .cache/icons/<file id>.blp.

Reads the install's CASC storage directly (formats: https://wowdev.wiki/TACT, https://wowdev.wiki/CASC).
Standard library only.

Usage: python3 scripts/extract_icons.py [--wow-dir DIR] [--product wow --product wowf ...] [--limit N]
"""

import argparse
import csv
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BRANCHES, ICON_CACHE as OUT, cached_icon_names, cached_unnamed_icon_ids, log  # noqa: E402

DEFAULT_WOW = os.environ.get("WOW_DIR", "/Applications/Games/World of Warcraft")

LOCALE_ENUS = 0x2
FLAG_LOW_VIOLENCE = 0x80
FLAG_NO_NAME_HASH = 0x10000000


class Unsupported(Exception):
    """A file uses an encoding this reader skips (LZ4, encryption)."""


def build_key(wow, product):
    with open(os.path.join(wow, ".build.info"), encoding="utf-8") as handle:
        rows = list(csv.reader(handle, delimiter="|"))
    header = [h.split("!")[0] for h in rows[0]]
    for row in rows[1:]:
        entry = dict(zip(header, row))
        if entry.get("Product") == product and entry.get("Active") == "1":
            return entry["Build Key"]
    sys.exit(f"no active {product} build in .build.info")


def read_config(wow, key):
    path = os.path.join(wow, "Data", "config", key[0:2], key[2:4], key)
    config = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if "=" in line and not line.startswith("#"):
                name, value = line.split("=", 1)
                config[name.strip()] = value.split()
    return config


def blte_decode(data):
    if data[:4] != b"BLTE":
        raise ValueError("not BLTE data")
    header_size = struct.unpack(">I", data[4:8])[0]
    if header_size == 0:
        blocks = [data[8:]]
    else:
        count = int.from_bytes(data[9:12], "big")
        sizes = [struct.unpack(">I", data[12 + 24 * i : 16 + 24 * i])[0] for i in range(count)]
        blocks, pos = [], header_size
        for size in sizes:
            if pos + size > len(data):
                raise ValueError("truncated BLTE data")
            blocks.append(data[pos : pos + size])
            pos += size
    out = bytearray()
    for block in blocks:
        mode = block[:1]
        if mode == b"N":
            out += block[1:]
        elif mode == b"Z":
            out += zlib.decompress(block[1:])
        else:
            raise Unsupported(f"BLTE block mode {mode!r}")
    return bytes(out)


class Storage:
    """Local CASC archives: EKey -> data via the Data/data/*.idx journals."""

    def __init__(self, wow):
        self.data_dir = os.path.join(wow, "Data", "data")
        latest = {}
        for name in os.listdir(self.data_dir):
            if name.endswith(".idx") and len(name) == 14:
                bucket, version = int(name[0:2], 16), int(name[2:10], 16)
                if version > latest.get(bucket, (-1, ""))[0]:
                    latest[bucket] = (version, name)
        self.entries = {}
        self.key_len = None
        for _, name in latest.values():
            self._read_idx(os.path.join(self.data_dir, name))
        self.handles = {}

    def _read_idx(self, path):
        with open(path, "rb") as handle:
            data = handle.read()
        size_len, offset_len, key_len, offset_bits = data[12], data[13], data[14], data[15]
        if self.key_len not in (None, key_len):
            sys.exit(f"{path}: key length {key_len} differs from the other index files ({self.key_len})")
        self.key_len = key_len
        entries_size = struct.unpack("<I", data[0x20:0x24])[0]
        entry_len = size_len + offset_len + key_len
        mask = (1 << offset_bits) - 1
        for pos in range(0x28, 0x28 + entries_size - entry_len + 1, entry_len):
            key = data[pos : pos + key_len]
            raw = int.from_bytes(data[pos + key_len : pos + key_len + offset_len], "big")
            size = int.from_bytes(data[pos + key_len + offset_len : pos + entry_len], "little")
            self.entries.setdefault(key, (raw >> offset_bits, raw & mask, size))

    def has(self, ekey):
        return ekey[: self.key_len] in self.entries

    def read(self, ekey):
        archive, offset, size = self.entries[ekey[: self.key_len]]
        handle = self.handles.get(archive)
        if handle is None:
            handle = self.handles[archive] = open(os.path.join(self.data_dir, f"data.{archive:03d}"), "rb")
        handle.seek(offset)
        data = handle.read(size)
        if len(data) < size:
            raise ValueError("truncated archive entry")
        # Each entry starts with a 30-byte header (reversed EKey, size, flags, checksums), sometimes zeroed.
        return blte_decode(data[30:])


def encoding_lookup(data, wanted):
    """CKey -> first EKey for the wanted CKeys, from a decoded encoding file."""
    if data[:2] != b"EN":
        raise ValueError("not an encoding file")
    ckey_size, ekey_size = data[3], data[4]
    page_kb = struct.unpack(">H", data[5:7])[0]
    page_count = struct.unpack(">I", data[9:13])[0]
    espec_size = struct.unpack(">I", data[18:22])[0]
    pages_start = 22 + espec_size + page_count * (ckey_size + 16)
    page_size = page_kb * 1024
    found = {}
    for page in range(page_count):
        pos = pages_start + page * page_size
        end = pos + page_size
        while pos + 6 + ckey_size <= end:
            key_count = data[pos]
            if key_count == 0:
                break
            ckey = data[pos + 6 : pos + 6 + ckey_size]
            if ckey in wanted:
                found[ckey] = data[pos + 6 + ckey_size : pos + 6 + ckey_size + ekey_size]
            pos += 6 + ckey_size + key_count * ekey_size
    return found


def root_lookup(data, wanted_ids):
    """File ID -> CKey for the wanted IDs, preferring enUS, non-low-violence blocks."""
    if data[:4] != b"TSFM":
        raise ValueError(f"unsupported root magic {data[:4]!r}")
    first, second = struct.unpack("<II", data[4:12])
    if first < 100 and second in (1, 2):
        header_size, version = first, second
        total, named = struct.unpack("<II", data[12:20])
        pos = header_size
    else:
        version, (total, named), pos = 1, (first, second), 12
    allow_unnamed = total != named
    found, rank = {}, {}
    while pos < len(data):
        if version == 2:
            count, locale, unk1, unk2 = struct.unpack("<IIII", data[pos : pos + 16])
            flags = unk1 | unk2 | (data[pos + 16] << 17)
            pos += 17
        else:
            count, flags, locale = struct.unpack("<III", data[pos : pos + 12])
            pos += 12
        deltas = struct.unpack(f"<{count}i", data[pos : pos + 4 * count])
        pos += 4 * count
        keys_at = pos
        pos += 16 * count
        if not (allow_unnamed and flags & FLAG_NO_NAME_HASH):
            pos += 8 * count
        score = (locale & LOCALE_ENUS != 0) * 2 + (flags & FLAG_LOW_VIOLENCE == 0)
        file_id = -1
        for i, delta in enumerate(deltas):
            file_id += 1 + delta
            if file_id in wanted_ids and score > rank.get(file_id, -1):
                rank[file_id] = score
                found[file_id] = data[keys_at + 16 * i : keys_at + 16 * i + 16]
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wow-dir", default=DEFAULT_WOW)
    parser.add_argument(
        "--product",
        action="append",
        help="product in .build.info, repeatable: wow (retail), wowf (Forever), wow_classic_era, wow_anniversary, wow_classic; default all",
    )
    parser.add_argument("--limit", type=int, help="extract only this many icons per product (for testing)")
    parser.add_argument("--out", default=OUT, help="output folder (default .cache/icons)")
    args = parser.parse_args()

    storage = Storage(args.wow_dir)
    log(f"{len(storage.entries)} local storage entries")
    os.makedirs(args.out, exist_ok=True)
    wanted = set(cached_icon_names()) | cached_unnamed_icon_ids()
    for product in args.product or BRANCHES:
        # Products share the archives; each has its own root, so a later one adds only icons not yet written.
        extract(storage, args.wow_dir, product, wanted, args)


def extract(storage, wow_dir, product, wanted, args):
    config = read_config(wow_dir, build_key(wow_dir, product))
    encoding = storage.read(bytes.fromhex(config["encoding"][1]))
    root_ckey = bytes.fromhex(config["root"][0])
    root = storage.read(encoding_lookup(encoding, {root_ckey})[root_ckey])

    todo = {i for i in wanted if not os.path.exists(os.path.join(args.out, f"{i}.blp"))}
    ckeys = root_lookup(root, todo)
    ekeys = encoding_lookup(encoding, set(ckeys.values()))

    written = skipped = broken = missing = 0
    for file_id in sorted(ckeys)[: args.limit]:
        ekey = ekeys.get(ckeys[file_id])
        if ekey is None or not storage.has(ekey):
            missing += 1
            continue
        try:
            body = storage.read(ekey)
        except Unsupported:
            skipped += 1
            continue
        except (ValueError, zlib.error, struct.error, IndexError) as error:
            log(f"  skip {file_id}: {error}")
            broken += 1
            continue
        with open(os.path.join(args.out, f"{file_id}.blp"), "wb") as out:
            out.write(body)
        written += 1
    log(
        f"{product} ({config.get('build-name', ['?'])[0]}): {len(todo)} icons to extract, wrote {written}, "
        f"{missing} not stored locally, {skipped} in unsupported encodings, {broken} unreadable"
    )


if __name__ == "__main__":
    main()
