#!/usr/bin/env python3
"""Build Iconic_Data/<Flavor>.lua from wago.tools DB2 CSV exports.

Usage: python3 scripts/build_data.py [forever|retail ...] [--refresh]

Also writes Iconic_Data/<Flavor>_<locale>.lua for each of LOCALES: translated names, labels and search text.
"""

import argparse
import csv
import io
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache", "wago")
OUT_DIR = os.path.join(ROOT, "Iconic_Data")

FLAVORS = {
    "forever": {"branch": "wowf", "file": "Forever.lua"},
    "retail": {"branch": "wow", "file": "Retail.lua"},
}

# Translations shipped next to the English data; each needs its lines in Iconic_Data/Iconic_Data.toc.
LOCALES = ["deDE"]

MAX_NAMES = 16
MAX_DESC_TOKENS = 48

SKILL_CATEGORY_CLASS = 7
SKILL_CATEGORY_PROFESSION = 11
SECONDARY_PROFESSIONS = {129, 185, 356, 794}  # First Aid, Cooking, Fishing, Archaeology

# Name tiers, best first; also the order names appear in the data.
TIER_PLAYER_SPELL, TIER_MOUNT, TIER_PET, TIER_ITEM, TIER_CURRENCY, TIER_SPELL = range(6)

JUNK_NAME = re.compile(
    r"\[|\(old\)|\b(dnt|dnd|test|testing|unused|deprecated|nyi|qa|ph|placeholder|debug)\b|^zz|^old |^monster - ",
    re.IGNORECASE,
)
JUNK_SUFFIX = re.compile(r" - \d+$")
DESC_CODES = re.compile(r"\$\{[^}]*\}|\$[<@?]?[a-zA-Z0-9.:;/=*<>-]*|\|c[0-9a-fA-F]{8}|\|r|\|n|\|T[^|]*\|t")

# Must match STOPWORDS in Search.lua: the query side drops the same words.
STOPWORDS = set(
    """a an and are as at be but by can for from has have in into is it its of on or per than that the their them
    then they this to up upon when while will with you your yours also each all any not over after before""".split()
)
# Dropped from descriptions only, because nearly every spell says them.
DESC_STOPWORDS = STOPWORDS | set(
    """sec secs second seconds min mins minute minutes yard yards yds lasts last amount increased increases
    increase reduced reduces reduce causes cause deals deal dealt rank ranks""".split()
)
# Dropped from translated descriptions only.
LOCALE_DESC_STOPWORDS = {
    "deDE": set(
        """der die das den dem des ein eine einen einem einer eines und oder mit von zu zum zur auf aus bei fur
        nach uber unter vor im in ist sind wird werden wurde um an als auch sich ihr ihre ihren ihrem ihres sein
        seine seinen seinem seines es er sie wenn dass nicht noch sek sekunden min minuten meter erhoht verringert
        verursacht schaden""".split()
    ),
}

# Must match FILE_NOISE in Search.lua.
FILE_NOISE = {"inv", "misc", "ability", "spell", "icon", "achievement"}
CAMEL = re.compile(r"(?<=[a-z])(?=[A-Z])")
# Both clients' icon pickers offer exactly the Interface\Icons files named like this (checked against in-game exports).
PICKER_NAME = re.compile(r"(inv|ability|spell)_", re.IGNORECASE)
TAGS = os.path.join(ROOT, "scripts", "icon_tags.json")

PLAYABLE_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID",
    "DEMONHUNTER", "EVOKER",
}

CLASS_FILE_TOKENS = {
    "warrior": "WARRIOR", "paladin": "PALADIN", "hunter": "HUNTER", "rogue": "ROGUE", "priest": "PRIEST",
    "deathknight": "DEATHKNIGHT", "shaman": "SHAMAN", "mage": "MAGE", "warlock": "WARLOCK", "monk": "MONK",
    "druid": "DRUID", "demonhunter": "DEMONHUNTER", "evoker": "EVOKER",
}

# File-name prefixes for icons no item uses: (prefix, "ClassID:SubclassID").
FILE_ITEM_CATEGORIES = [
    ("inv_sword", "2:7"), ("inv_axe", "2:0"), ("inv_mace", "2:4"), ("inv_hammer", "2:4"), ("inv_staff", "2:10"),
    ("inv_spear", "2:6"), ("inv_polearm", "2:6"), ("inv_weapon_bow", "2:2"), ("inv_weapon_crossbow", "2:18"),
    ("inv_weapon_rifle", "2:3"), ("inv_weapon_shortblade", "2:15"), ("inv_dagger", "2:15"), ("inv_wand", "2:19"),
    ("inv_knife", "2:15"), ("inv_shield", "4:6"), ("inv_potion", "0:1"), ("inv_drink", "0:5"), ("inv_misc_food", "0:5"),
    ("inv_ore", "7:7"), ("inv_misc_herb", "7:9"), ("inv_fabric", "7:5"), ("inv_misc_gem", "3:0"), ("inv_jewelry_ring", "4:0"),
    ("inv_jewelry_necklace", "4:0"), ("inv_misc_bag", "1:0"), ("inv_scroll", "0:4"),
]


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def fetch(table, branch, refresh, locale=None):
    os.makedirs(CACHE, exist_ok=True)
    suffix = f"-{locale}" if locale else ""
    path = os.path.join(CACHE, f"{branch}-{table}{suffix}.csv")
    version_path = path + ".version"
    if refresh or not os.path.exists(path):
        url = f"https://wago.tools/db2/{table}/csv?branch={branch}" + (f"&locale={locale}" if locale else "")
        log(f"download {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "Iconic-data-build"})
        with urllib.request.urlopen(req) as resp, open(path + ".part", "wb") as out:
            disposition = resp.headers.get("Content-Disposition", "")
            out.write(resp.read())
        os.replace(path + ".part", path)
        match = re.search(r"\.(\d+\.\d+\.\d+\.\d+)\.csv", disposition)
        with open(version_path, "w") as v:
            v.write(match.group(1) if match else "unknown")
    with open(version_path) as v:
        version = v.read().strip()
    with open(path, encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    return rows, version


def num(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def clean_name(name):
    name = (name or "").replace("\t", " ").replace("\n", " ").replace("\r", " ").replace("|", "/").strip()
    if not name or JUNK_NAME.search(name) or JUNK_SUFFIX.search(name) or name == name.lower():
        return None
    return name


# Accented Latin letters to base letters. Must match FOLD in Search.lua.
FOLD = {"ẞ": "ss", "ß": "ss", "æ": "ae", "Æ": "ae", "þ": "th", "Þ": "th"}
for _base, _letters in (
    ("a", "ÀÁÂÃÄÅàáâãäå"), ("c", "Çç"), ("e", "ÈÉÊËèéêë"), ("i", "ÌÍÎÏìíîï"), ("d", "Ðð"), ("n", "Ññ"),
    ("o", "ÒÓÔÕÖØòóôõöø"), ("u", "ÙÚÛÜùúûü"), ("y", "Ýýÿ"),
):
    for _letter in _letters:
        FOLD[_letter] = _base
FOLD_RE = re.compile("|".join(map(re.escape, FOLD)))


def normalize(text):
    text = FOLD_RE.sub(lambda m: FOLD[m.group(0)], text).lower().replace("'", "").replace("’", "")
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


def stem(token):
    """Mirror of Search.Stem in Search.lua."""
    n = len(token)
    if n <= 3 or token.isdigit():
        return token
    if n > 5 and token.endswith("ing"):
        return token[:-3]
    if n > 4 and token.endswith("ies"):
        return token[:-3] + "y"
    if n > 4 and token.endswith("ed"):
        return token[:-2]
    if n > 4 and token[-3:] in ("hes", "xes", "ses"):
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def tokens(text):
    """Mirror of Search.Tokens in Search.lua."""
    return [stem(t) for t in normalize(text).split() if t not in STOPWORDS]


def desc_tokens(text, stopwords=DESC_STOPWORDS):
    text = DESC_CODES.sub(" ", text or "")
    for token in normalize(text).split():
        if len(token) >= 3 and not token.isdigit() and token not in stopwords:
            yield token


def file_tokens(file):
    """Mirror of Search.FileText in Search.lua: camel-case words split, digits and noise words dropped."""
    return [t for t in tokens(re.sub(r"\d+", " ", CAMEL.sub(" ", file))) if t not in FILE_NOISE]


def search_text(names, file, desc):
    """Field layout read by Search.lua: name buckets (1st, 2nd, 3rd-4th, rest), file name, description. Catalog.Parse
    adds the picture tags (the "tags" column) to the file name field."""
    buckets = [names[0:1], names[1:2], names[2:4], names[4:]]
    seen = set()
    fields = []
    for bucket in buckets:
        field = []
        for token in tokens(" ".join(bucket)):
            if token not in seen:
                seen.add(token)
                field.append(token)
        fields.append(" ".join(field))
    file_field = []
    for token in file_tokens(file):
        if token not in file_field:
            file_field.append(token)
    fields.append(" ".join(file_field))
    desc_seen = set()
    fields.append(" ".join(t for t in tokens(" ".join(desc)) if not (t in desc_seen or desc_seen.add(t))))
    return "|".join(fields)


class Icon:
    __slots__ = ("file", "words", "tags", "names", "seen", "desc", "src", "cls", "cats", "profs", "spells", "stopwords")

    def __init__(self, file, stopwords=DESC_STOPWORDS):
        self.file = file.lower()
        self.words = file
        self.tags = ()
        self.stopwords = stopwords
        self.names = []
        self.seen = set()
        self.desc = []
        self.src = set()
        self.cls = 0
        self.cats = set()
        self.profs = set()
        self.spells = set()

    def add_name(self, tier, name, ref=None):
        """`ref` is how the game looks the name up (Catalog.NameOf): s/i/c and an ID; the name itself when it can't."""
        name = clean_name(name)
        if name and name.lower() not in self.seen:
            self.seen.add(name.lower())
            self.names.append((tier, len(self.names), name, ref or name))

    def add_desc(self, text):
        known = set(self.desc)
        for token in desc_tokens(text, self.stopwords):
            if len(self.desc) >= MAX_DESC_TOKENS:
                return
            if token not in known:
                known.add(token)
                self.desc.append(token)


def build(flavor, refresh, locale=None):
    branch = FLAVORS[flavor]["branch"]
    stopwords = DESC_STOPWORDS | LOCALE_DESC_STOPWORDS.get(locale, set())
    tables = {}
    versions = set()
    for name in [
        "ManifestInterfaceData", "SpellName", "Spell", "SpellMisc", "SkillLineAbility", "SkillLine",
        "SkillRaceClassInfo", "ChrClasses", "Item", "ItemSparse", "ItemModifiedAppearance", "ItemAppearance",
        "ItemClass", "ItemSubClass", "Mount", "BattlePetSpecies", "CurrencyTypes",
    ]:
        tables[name], version = fetch(name, branch, refresh, locale)
        versions.add(version)
    build_version = max(versions)

    icons = {}
    for row in tables["ManifestInterfaceData"]:
        path = row["FilePath"].lower().replace("/", "\\")
        if path.startswith("interface\\icons") and PICKER_NAME.match(row["FileName"]):
            icons[num(row["ID"])] = Icon(re.sub(r"\.blp$", "", row["FileName"], flags=re.IGNORECASE), stopwords)
    for file_id, tags in load_tags().items():
        if file_id in icons:
            icons[file_id].tags = tags
    log(f"{flavor}{' ' + locale if locale else ''}: {len(icons)} icons")

    def icon(file_id):
        return icons.get(num(file_id))

    classes = {}
    class_by_token = {}
    for row in tables["ChrClasses"]:
        class_id = num(row["ID"])
        # Only playable classes; the table also holds internal ones such as "Adventurer".
        if 0 < class_id <= 32 and row["Filename"].upper() in PLAYABLE_CLASSES:
            classes[class_id] = row["Name_lang"]
            class_by_token[row["Filename"].upper()] = class_id

    playable_mask = sum(1 << (class_id - 1) for class_id in classes)

    spell_names = {num(r["ID"]): r["Name_lang"] for r in tables["SpellName"]}
    spell_desc = {num(r["ID"]): r["Description_lang"] for r in tables["Spell"]}
    spell_icon = {}
    for row in tables["SpellMisc"]:
        spell_id, file_id = num(row["SpellID"]), num(row["SpellIconFileDataID"])
        if file_id and (spell_id not in spell_icon or num(row["DifficultyID"]) == 0):
            spell_icon[spell_id] = file_id

    skill_lines = {num(r["ID"]): r for r in tables["SkillLine"]}
    skill_class_mask = {}
    for row in tables["SkillRaceClassInfo"]:
        mask = num(row["ClassMask"])
        if mask > 0:
            skill_id = num(row["SkillID"])
            skill_class_mask[skill_id] = skill_class_mask.get(skill_id, 0) | mask

    def profession_of(skill_id):
        line = skill_lines.get(skill_id)
        while line and num(line["ParentSkillLineID"]):
            parent = skill_lines.get(num(line["ParentSkillLineID"]))
            if not parent:
                break
            line = parent
        if not line:
            return None
        line_id = num(line["ID"])
        is_profession = num(line["CategoryID"]) == SKILL_CATEGORY_PROFESSION or line_id in SECONDARY_PROFESSIONS
        if is_profession and clean_name(line["DisplayName_lang"]):
            return line_id
        return None

    professions = {}
    for row in tables["SkillLineAbility"]:
        spell_id, skill_id = num(row["Spell"]), num(row["SkillLine"])
        target = icon(spell_icon.get(spell_id))
        line = skill_lines.get(skill_id)
        if not target or not line:
            continue
        category = num(line["CategoryID"])
        prof = profession_of(skill_id)
        if category == SKILL_CATEGORY_CLASS:
            mask = (num(row["ClassMask"]) or skill_class_mask.get(skill_id, 0)) & playable_mask
            if mask > 0 and bin(mask).count("1") <= 3:
                target.cls |= mask
                target.spells.add(spell_id)
        elif prof:
            line = skill_lines[prof]
            # Name, then the profession's icon for the filter menu.
            professions[prof] = f"{line['DisplayName_lang']}\t{num(line['SpellIconFileID']) or ''}".rstrip("\t")
            target.profs.add(prof)
        else:
            continue
        target.src.add("S")
        target.add_name(TIER_PLAYER_SPELL, spell_names.get(spell_id), f"s{spell_id}")
        target.add_desc(spell_desc.get(spell_id))

    for row in tables["Mount"]:
        target = icon(spell_icon.get(num(row["SourceSpellID"])))
        if target:
            target.src.add("M")
            target.add_name(TIER_MOUNT, row["Name_lang"], f"s{num(row['SourceSpellID'])}")

    for row in tables["BattlePetSpecies"]:
        summon = num(row["SummonSpellID"])
        target = icon(row["IconFileDataID"]) or icon(spell_icon.get(summon))
        if target:
            target.src.add("P")
            target.add_name(TIER_PET, spell_names.get(summon), f"s{summon}")

    item_names = {num(r["ID"]): r["Display_lang"] for r in tables["ItemSparse"]}
    appearance_icon = {num(r["ID"]): num(r["DefaultIconFileDataID"]) for r in tables["ItemAppearance"]}
    item_appearance = {}
    for row in sorted(tables["ItemModifiedAppearance"], key=lambda r: num(r["OrderIndex"]), reverse=True):
        item_appearance[num(row["ItemID"])] = num(row["ItemAppearanceID"])
    for row in tables["Item"]:
        item_id = num(row["ID"])
        target = icon(row["IconFileDataID"]) or icon(appearance_icon.get(item_appearance.get(item_id)))
        name = item_names.get(item_id)
        if target and clean_name(name):
            target.src.add("I")
            target.cats.add(f"{num(row['ClassID'])}:{num(row['SubclassID'])}")
            target.add_name(TIER_ITEM, name, f"i{item_id}")

    for row in tables["CurrencyTypes"]:
        target = icon(row["InventoryIconFileID"])
        if target and clean_name(row["Name_lang"]):
            target.src.add("C")
            target.add_name(TIER_CURRENCY, row["Name_lang"], f"c{num(row['ID'])}")

    for spell_id, file_id in spell_icon.items():
        target = icon(file_id)
        if target:
            target.src.add("S")
            target.add_name(TIER_SPELL, spell_names.get(spell_id), f"s{spell_id}")

    for target in icons.values():
        parts = target.file.split("_")
        if not target.cls:
            for part in parts:
                class_id = class_by_token.get(CLASS_FILE_TOKENS.get(part, ""))
                if class_id:
                    target.cls |= 1 << (class_id - 1)
        if not target.cats:
            for prefix, category in FILE_ITEM_CATEGORIES:
                if target.file.startswith(prefix):
                    target.cats.add(category)
                    break

    item_classes = {}
    for row in tables["ItemClass"]:
        if row["ClassName_lang"]:
            item_classes[str(num(row["ClassID"]))] = row["ClassName_lang"]
    used_cats = set().union(*(t.cats for t in icons.values()))
    for row in tables["ItemSubClass"]:
        key = f"{num(row['ClassID'])}:{num(row['SubClassID'])}"
        name = row["DisplayName_lang"] or row["VerboseName_lang"]
        if key in used_cats and name:
            item_classes[key] = name

    return build_version, branch, icons, classes, item_classes, professions


def long_string(body):
    level = 1
    while ("]" + "=" * level + "]") in body:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{body}]{eq}]"


def lookup_body(mapping):
    def sort_key(key):
        return [int(p) for p in str(key).split(":")]

    return "".join(f"{key}\t{mapping[key]}\n" for key in sorted(mapping, key=sort_key))


# Must match Catalog.SOURCES in Catalog.lua.
SOURCE_BITS = {"S": 1, "I": 2, "M": 4, "P": 8, "C": 32}  # 16 was achievements


def load_colors():
    """Column names and file ID -> values from .cache/icon_colors.csv, written by build_colors.py."""
    path = os.path.join(ROOT, ".cache", "icon_colors.csv")
    if not os.path.exists(path):
        sys.exit(f"missing {path}; run scripts/build_colors.py first")
    with open(path, encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        columns = next(reader)[1:]
        return columns, {int(row[0]): row[1:] for row in reader}


def lua_string(text):
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    return '"' + text.replace("\0", "\\000") + '"'


def lua_numbers(values):
    return "{" + ",".join(str(v) for v in values) + "}" if values else "nil"


def category_number(key):
    class_id, subclass_id = (int(p) for p in key.split(":"))
    if not 0 <= subclass_id < 256:
        sys.exit(f"item subclass {key} does not fit class * 256 + subclass")
    return class_id * 256 + subclass_id


def load_tags():
    """File ID → words for what the icon shows, from scripts/tag_icons.py."""
    if not os.path.exists(TAGS):
        return {}
    with open(TAGS, encoding="utf-8") as handle:
        return {int(k): v for k, v in json.load(handle).items()}


def write(flavor, build_version, branch, icons, classes, item_classes, professions):
    color_columns, colors = load_colors()
    # Color names are derived in the game from l, a, b (Search.ColorName); only the numbers ship.
    keep = [k for k, name in enumerate(color_columns) if not name.startswith("name")]
    color_columns = [color_columns[k] for k in keep]
    colors = {file_id: [values[k] if k < len(values) else "" for k in keep] for file_id, values in colors.items()}
    ids = sorted(icons)
    columns = {name: [] for name in ("id", "refs", "text", "tags", "src", "cls", "cats", "profs", "spells")}
    # Dominant colors: l, a, b (OKLab * 100) and w (weight, 0 for no color).
    shares = {name: [] for name in color_columns}
    for file_id in ids:
        t = icons[file_id]
        ranked = sorted(t.names)[:MAX_NAMES]
        names = [n for _, _, n, _ in ranked]
        display = "|".join(ref for _, _, _, ref in ranked)
        columns["id"].append(str(file_id))
        columns["refs"].append(lua_string(display) if display else "nil")
        # Padded as Search.PadText does, so the game reads it as is.
        columns["text"].append(lua_string(" " + search_text(names, t.words, t.desc).replace("|", " | ") + " "))
        columns["tags"].append(lua_string(" ".join(t.tags)) if t.tags else "nil")
        columns["src"].append(str(sum(SOURCE_BITS[s] for s in t.src)))
        columns["cls"].append(str(t.cls or 0))
        columns["cats"].append(lua_numbers(sorted(category_number(c) for c in t.cats)))
        columns["profs"].append(lua_numbers(sorted(t.profs)))
        columns["spells"].append(lua_numbers(sorted(t.spells)))
        values = colors.get(file_id, [])
        for k, (name, column) in enumerate(shares.items()):
            value = values[k] if k < len(values) else ""
            column.append(value or "0")

    def column(out, name, values, indent):
        out.write(f"{indent}{name} = {{\n")
        for value in values:
            out.write(f"{value},\n")
        out.write(f"{indent}}},\n")

    path = os.path.join(OUT_DIR, FLAVORS[flavor]["file"])
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write(f"-- Generated by scripts/build_data.py from wago.tools ({branch} {build_version}). Do not edit.\n")
        out.write("IconicData = {\n")
        out.write(f'  flavor = "{flavor}",\n')
        out.write(f'  build = "{build_version}",\n')
        out.write(f"  classes = {long_string(lookup_body(classes))},\n")
        out.write(f"  itemClasses = {long_string(lookup_body(item_classes))},\n")
        out.write(f"  professions = {long_string(lookup_body(professions))},\n")
        # One column per field, one row per icon, read by Catalog.Parse without parsing.
        out.write("  icons = {\n")
        for name, values in columns.items():
            column(out, name, values, "    ")
        out.write("    colors = {\n")
        for name, values in shares.items():
            column(out, name, values, "      ")
        out.write("    },\n  },\n}\n")
    log(f"{flavor}: wrote {path} ({os.path.getsize(path) // 1024} KB)")


def text_delta(translated, english):
    """Per field, the translated text's tokens that the English field lacks; Catalog.ApplyLocale adds them back in."""
    fields = []
    for a, b in zip(translated.split("|"), english.split("|")):
        known = set(b.split())
        fields.append(" ".join(t for t in a.split() if t not in known))
    return "|".join(fields)


def load_translated_words(locale):
    """Translated search token -> English words, from scripts/search_words_<locale>.json (English word -> words):
    every picture tag and synonym word. The game stems the English words itself, keeping them readable."""
    path = os.path.join(ROOT, "scripts", f"search_words_{locale}.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        translations = json.load(handle)
    words = {}
    for english, translated in translations.items():
        en = normalize(english)
        for token in tokens(" ".join(translated)):
            targets = words.setdefault(token, [])
            if token not in tokens(en) and en not in targets:
                targets.append(en)
    return {token: targets for token, targets in words.items() if targets}


def load_tag_names(locale):
    """English picture tag -> its first translation, shown in tooltips."""
    path = os.path.join(ROOT, "scripts", f"search_words_{locale}.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        translations = json.load(handle)
    tags = {tag for words in load_tags().values() for tag in words}
    return {tag: translations[tag][0] for tag in sorted(tags) if translations.get(tag) and translations[tag][0] != tag}


def write_locale(flavor, locale, english, translated):
    """Translated names, labels, search words the English text lacks, and translated search words."""
    _, _, en_icons, _, _, _ = english
    build_version, branch, icons, classes, item_classes, professions = translated
    ids, names_col, text_col = [], [], []
    for file_id in sorted(en_icons):
        t, en = icons.get(file_id), en_icons[file_id]
        if not t or not (t.names or t.desc):
            continue
        ranked, en_ranked = sorted(t.names)[:MAX_NAMES], sorted(en.names)[:MAX_NAMES]
        names = [n for _, _, n, _ in ranked]
        en_names = [n for _, _, n, _ in en_ranked]
        text = text_delta(search_text(names, t.words, t.desc), search_text(en_names, en.words, en.desc))
        # Only names kept as text differ by language; references are looked up in the player's language.
        display = "|".join(ref for _, _, _, ref in ranked)
        en_display = "|".join(ref for _, _, _, ref in en_ranked)
        if not text.replace("|", "").strip() and display == en_display:
            continue
        ids.append(str(file_id))
        names_col.append(lua_string(display) if display and display != en_display else "nil")
        text_col.append(lua_string(text))

    path = os.path.join(OUT_DIR, f"{os.path.splitext(FLAVORS[flavor]['file'])[0]}_{locale}.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write(f"-- Generated by scripts/build_data.py from wago.tools ({branch} {build_version} {locale}). Do not edit.\n")
        out.write("IconicDataLocale = {\n")
        out.write(f'  locale = "{locale}",\n')
        out.write(f"  classes = {long_string(lookup_body(classes))},\n")
        out.write(f"  itemClasses = {long_string(lookup_body(item_classes))},\n")
        out.write(f"  professions = {long_string(lookup_body(professions))},\n")
        translated_words = "".join(f"{w}\t{' '.join(en)}\n" for w, en in sorted(load_translated_words(locale).items()))
        out.write(f"  translatedWords = {long_string(translated_words)},\n")
        tag_names = "".join(f"{tag}\t{name}\n" for tag, name in load_tag_names(locale).items())
        out.write(f"  tagNames = {long_string(tag_names)},\n")
        out.write("  icons = {\n")
        columns = [("id", ids), ("refs", names_col), ("text", text_col)]
        # Display names are references looked up in the game's language, so a translation rarely has its own.
        if all(v == "nil" for v in names_col):
            columns.remove(("refs", names_col))
        for name, values in columns:
            out.write(f"    {name} = {{\n")
            for value in values:
                out.write(f"{value},\n")
            out.write("    },\n")
        out.write("  },\n}\n")
    log(f"{flavor} {locale}: wrote {path} ({os.path.getsize(path) // 1024} KB, {len(ids)} icons)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("flavors", nargs="*", help="forever, retail (default: both)")
    parser.add_argument("--refresh", action="store_true", help="re-download the CSVs")
    args = parser.parse_args()
    unknown = set(args.flavors) - set(FLAVORS)
    if unknown:
        parser.error(f"unknown flavor: {', '.join(sorted(unknown))}")
    for flavor in args.flavors or sorted(FLAVORS):
        english = build(flavor, args.refresh)
        write(flavor, *english)
        for locale in LOCALES:
            write_locale(flavor, locale, english, build(flavor, args.refresh, locale))


if __name__ == "__main__":
    main()
