#!/usr/bin/env python3
"""List words that often share an icon with the given words: candidates for Data/Synonyms.lua.

Usage: python3 scripts/synonym_candidates.py target naked heal [--data Iconic_Data/Retail.lua] [--top 15]
"""

import argparse
import collections
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STOP = set(
    """a an and are as at be but by can for from has have in into is it its of on or per than that the their them then
    they this to up upon when while will with you your also each all any not over after before""".split()
)


def icon_tokens(path):
    text = open(path, encoding="utf-8").read()
    body = text.split("icons = [", 1)[1]
    for line in body.splitlines()[1:]:
        fields = line.split("\t")
        if len(fields) < 3:
            continue
        words = " ".join([fields[1].replace("_", " "), fields[2], fields[3] if len(fields) > 3 else ""])
        words = re.sub(r"[^a-z0-9]+", " ", words.lower().replace("'", ""))
        yield {w for w in words.split() if len(w) >= 3 and w not in STOP and not w.isdigit()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("words", nargs="+")
    parser.add_argument("--data", default=os.path.join(ROOT, "Iconic_Data", "Retail.lua"))
    parser.add_argument("--top", type=int, default=15)
    args = parser.parse_args()

    icons = list(icon_tokens(args.data))
    df = collections.Counter(w for tokens in icons for w in tokens)
    total = len(icons)
    for word in args.words:
        co = collections.Counter()
        for tokens in icons:
            if word in tokens:
                co.update(tokens - {word})
        scored = [
            (math.log(n * total / (df[word] * df[other])) * math.log1p(n), other, n)
            for other, n in co.items()
            if n >= 3
        ]
        scored.sort(reverse=True)
        print(f"{word} ({df[word]} icons): " + ", ".join(f"{o}({n})" for _, o, n in scored[: args.top]))


if __name__ == "__main__":
    main()
