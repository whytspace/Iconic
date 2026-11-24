#!/usr/bin/env python3
"""List words that often share an icon with the given words: candidates for Data/Synonyms.lua.

Words are compared stemmed, as search does (build_data.tokens), so "healing" and "heal" are one word.

Usage: python3 scripts/synonym_candidates.py target heal shield [--data Iconic_Data/Retail.lua] [--top 15]
"""

import argparse
import collections
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import STOPWORDS, tokens  # noqa: E402
from common import ROOT  # noqa: E402

LUA_ESCAPE = re.compile(r"\\(\d{1,3}|.)")


def lua_value(line):
    """The string of one generated column entry ("...", or nil,)."""
    value = line.strip().rstrip(",")
    if not value.startswith('"'):
        return ""
    escapes = {"n": "\n", "r": "\r"}
    return LUA_ESCAPE.sub(lambda m: chr(int(m[1])) if m[1].isdigit() else escapes.get(m[1], m[1]), value[1:-1])


def read_columns(path, names):
    """Column name -> values of the given IconicData.icons columns (one Lua table per column, see build_data.write)."""
    columns, current = {}, None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if current is None:
                match = re.fullmatch(r" {4}(\w+) = \{\n", line)
                if match and match[1] in names:
                    current = columns[match[1]] = []
            elif line == "    },\n":
                current = None
            else:
                current.append(lua_value(line))
    missing = set(names) - set(columns)
    if missing:
        sys.exit(f"{path} has no {', '.join(sorted(missing))} column")
    return columns


def icon_tokens(path):
    """Per icon, the stemmed words of its search text (names, file name, description) and picture tags."""
    columns = read_columns(path, ("text", "tags"))
    for text, tags in zip(columns["text"], columns["tags"]):
        words = set(text.replace("|", " ").split()) | set(tokens(tags))
        yield {w for w in words if len(w) >= 3 and w not in STOPWORDS and not w.isdigit()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("words", nargs="+")
    parser.add_argument("--data", default=os.path.join(ROOT, "Iconic_Data", "Retail.lua"))
    parser.add_argument("--top", type=int, default=15)
    args = parser.parse_args()

    icons = list(icon_tokens(args.data))
    df = collections.Counter(w for words in icons for w in words)
    total = len(icons)
    for query in args.words:
        word = " ".join(tokens(query))
        if not df[word]:
            print(f"{query}: on no icon")
            continue
        co = collections.Counter()
        for words in icons:
            if word in words:
                co.update(words - {word})
        scored = [
            (math.log(n * total / (df[word] * df[other])) * math.log1p(n), other, n)
            for other, n in co.items()
            if n >= 3
        ]
        scored.sort(reverse=True)
        print(f"{query} ({df[word]} icons): " + ", ".join(f"{o}({n})" for _, o, n in scored[: args.top]))


if __name__ == "__main__":
    main()
