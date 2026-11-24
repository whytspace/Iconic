# Contributing

## Setup

Use the dev container for all project tools:

```sh
devc up
devc luacheck .
devc stylua .
devc busted
```

Run the checks before committing.

To load edits in WoW, symlink both add-on folders into the AddOns folder of each client:

```sh
git config core.fileMode false
ln -s "$PWD" "/Applications/Games/World of Warcraft/_retail_/Interface/AddOns/Iconic"
ln -s "$PWD/Iconic_Data" "/Applications/Games/World of Warcraft/_retail_/Interface/AddOns/Iconic_Data"
```

Use the WoW Forever client's AddOns folder the same way. The Git setting prevents WoW's permission updates from appearing as executable-bit changes.

## Layout

- `Iconic.toc` — one add-on for WoW Forever and retail.
- `Search.lua`, `Catalog.lua`, `Data.lua` — search, filters, groups and data loading; pure Lua, unit-tested.
- `UI/` — frames, picker hooks, tooltips, settings, public API; checked in-game.
- `Data/Synonyms.lua` — hand-curated synonym groups.
- `Iconic_Data/` — a separate load-on-demand add-on with the generated icon data, one file per game version, picked by `[AllowLoadGameType]`.

## Icon data

`scripts/build_data.py` downloads DB2 tables from [wago.tools](https://wago.tools/db2) and writes `Iconic_Data/Forever.lua` and `Iconic_Data/Retail.lua`. It keeps only the icons Blizzard's picker offers (`PICKER_NAME`), since Iconic shows no others. Rerun it after a game patch and commit the result:

```sh
devc python3 scripts/build_data.py            # both versions, cached downloads
devc python3 scripts/build_data.py --refresh  # fetch fresh tables
devc python3 scripts/build_data.py forever
```

Downloads are cached in `.cache/wago/`. `spec/data_spec.lua` runs the shipped files through the real search.

Each data file holds one Lua table per field with one entry per icon (columns listed at `Catalog.NewIndex`), so the game builds them while loading the file and `Catalog.Parse` takes them over without parsing. Display names are stored in `refs` as references to what uses the icon, which the game looks up in the player's language (`s133` spell, `i6948` item, `c1792` currency, see `Catalog.NameOf`); search uses only the words in `text`, plus the picture tags from `tags`. File names are not stored: the game can't name a file ID, but `Catalog.ResolveId` turns an icon path into its ID with `GetFileIDFromPath`. Achievement titles are left out: they rarely say what their icon shows. Sources and classes are bit masks; categories (`class * 256 + subclass`), professions and spells are number lists; colours are four dominant-colour slots, each an `l`, `a`, `b`, `w` and `name` column.

`build_data.py` tokenizes names the same way `Search.lua` does (normalize, stopwords, stemming), and splits file names at camel-case words (`SoothingMists` → soothing mists) like `Search.FileText`. Change both together.

## Icon colours

Colour data needs the icon images. `scripts/extract_icons.py` reads them straight from a local WoW install's CASC storage (standard library only) into `.cache/icons/`, from the retail and the WoW Forever product. The dev container mounts the install read-only at `/wow`:

- Default source: `/Applications/Games/World of Warcraft`. Elsewhere, set `WOW_DIR` to the install folder before `devc up`.
- Docker Desktop must share that folder: Settings → Resources → File sharing.
- Without a WoW install at that path the container does not start.

```sh
devc python3 -I scripts/extract_icons.py
```

`scripts/build_colors.py` then finds every icon's dominant colours into `.cache/icon_colors.csv`, and `build_data.py` merges that into the data files. `build_data.py` stops when that file is missing:

```sh
devc python3 -I scripts/build_colors.py --sheets
devc python3 scripts/build_data.py
```

Pixels are converted to OKLab and clustered (weighted k-means) into up to `MAX_COLORS` dominant colours, each with its weight, the part of the icon it covers; pixels near the centre and saturated pixels weigh more. The data ships only their OKLab values and weights. `--sheets` writes `.cache/colors/<colour>.png` with the icons that have the most of each named colour, for checking the result by eye.

In search, a colour chip is one shade with a weight (`chipScore` in `Search.lua`):

- An icon matches a chip when at least `COLOR_MIN` of it lies in the chip's band: within `HUE_WIDTH` degrees of its hue, or, for a colourless chip (black, white, grey), within `LIGHT_WIDTH` of its lightness.
- Inside the band, colours count less the farther they lie from the chip's shade (`CLOSE_RADIUS`, down to `CLOSE_FLOOR`).
- Icons rank by the chips' values averaged by their weights (the slider under the colour picker).
- Colour words are presets: one shade each (`Search.COLOR_PRESETS`, with extra words in `hints` and `ns.LocaleColorHints`). Two-word names such as "dark green" are suggested when both words are typed.

Grouping by colour names each dominant colour after the nearest reference shade (`COLOR_REFS` in `Search.lua`, mirrored in `build_colors.py` for the sheets), then puts each icon under its strongest vivid colour covering `GROUP_MIN_WEIGHT`, else such a brown, else its strongest colour (`colorGroup` in `Catalog.lua`).

## Icon tags

`scripts/icon_tags.json` holds words for what each icon shows ("rose", "thorns", "jellyfish"), one line per file ID, subject first. They may repeat words of the file name. `build_data.py` ships them readable in their own column for tooltips, and `Catalog.Parse` adds them to each icon's file-name search words at load, without repeats, so tags and file name count the same. Claude Code subagents write them by looking at the icons; `scripts/tag_icons.py` prepares their work and collects it. Commit the file: tagging all icons uses about 25M tokens.

Only icons Blizzard's picker offers get tags. In both clients that is exactly the `Interface\Icons` files named `inv_…`, `ability_…` or `spell_…`, in any case (`PICKER_NAME`).

After a patch, once `extract_icons.py` has the new images, tag only the icons that have no tags yet:

```sh
devc python3 -I scripts/tag_icons.py prepare --chunks 10   # chunks of 100 untagged icons in .cache/tags/chunks/
devc python3 scripts/tag_icons.py status
```

Then ask Claude Code to start one Sonnet subagent per chunk, about ten at a time, each with this instruction:

> Run `python3 /absolute/path/to/Iconic/scripts/tag_icons.py prompt c012` and follow the instructions it prints exactly.

Use the checkout's absolute path: subagents don't always start in the repository.

The prompt is `scripts/tag_prompt.md`. A chunk costs about 80k tokens and takes a minute or two. When the agents are done, merge their results and commit `scripts/icon_tags.json`:

```sh
devc python3 scripts/tag_icons.py merge
```

`merge` splits two-word names into single words and lists entries it rejects; rerun `prompt` for those chunks or fix them by hand. Before changing the prompt, tag a few chunks with both versions and compare them by eye. The prompt makes the agent tag what the picture shows, use the file name as a hint, and add other readings of the same picture. Without the file name, agents mistake small belts for gloves. Told to trust it, they call a withered rose a "talisman". Told to avoid its words, they call a net "scales".

## Translations

German (`deDE`) is the first translation; others follow the same steps:

- Interface texts: `Locales/<locale>.lua`, loaded from `Iconic.toc`. `spec/locale_spec.lua` fails while a text the code uses has no translation. Extra colour words go into `ns.LocaleColorHints`.
- Icon data: add the locale to `LOCALES` in `scripts/build_data.py` and its two files to `Iconic_Data/Iconic_Data.toc` with `[AllowLoadTextLocale <locale>]`, so only that client loads them.
- Search words: `scripts/search_words_<locale>.json` gives each picture tag and synonym word one or more single-word translations. Add the locale to the list in `spec/locale_spec.lua`, which fails while a tag or synonym has none, so new ones need translating before the checks pass.

Each `<Flavor>_<locale>.lua` holds translated labels, the search words the English text lacks, the translated search words, and each tag's first translation for tooltips; display names come from the game in its language. `Catalog.ApplyLocale` puts the translated words before the English ones, field by field, so both find an icon. A translated word counts as if its English words were typed, synonyms included (`Search.BuildSynonyms`). A partly typed one expands only while it starts a few translated words, and a complete one never reaches longer compounds (Schwert isn't Schwertlilie).

`Search.Normalize` and `normalize` in `build_data.py` fold accented letters (ä → a, ß → ss), so "jager" finds "Jäger". Stemming stays English-only and applies the same way to every language's words.

## Synonyms

Each line of `Data/Synonyms.lua` is one group of words that find each other's icons. To find candidates, list the words that often share an icon with a given word:

```sh
devc python3 scripts/synonym_candidates.py target heal shield
```

Add a group only when a player would plausibly search one word to find the other.

## Picker adapters

`UI/Pickers.lua` replaces the icon grid of every frame built on Blizzard's `IconSelectorPopupFrameTemplate`. A new Blizzard picker is one entry in `Pickers.BLIZZARD`. Other add-ons call `Iconic.RegisterPicker(frame, adapter)`, documented in `UI/API.lua`.

## Assets

`Assets/swatch.tga`, the shaded sphere behind colour swatches, and `Assets/colorwheel.tga`, the colour picker button, are generated: `devc python3 -I scripts/build_swatch.py`.

The add-on icon is `Assets/logo.svg`. WoW loads only uncompressed, power-of-two, 32-bit RGBA TGA files, referenced without the extension. The SVG uses filters, so render it to `Assets/logo.png` in a browser (e.g. headless Chrome) and convert that with ImageMagick:

```sh
magick Assets/logo.png -resize 256x256 -depth 8 -type TrueColorAlpha -compress none TGA:Assets/logo.tga
```

Only the TGA ships; `.pkgmeta` ignores the PNG and SVG.

## Screenshots

README images come from the screenshot tour, never hand-taken screenshots. `/iconic shot tour` stages each view (`VIEWS` in `UI/ScreenshotTour.lua`), captures it on a black and a white backdrop with all other UI hidden, and restores your search, filters and grouping. Keep the mouse off the windows while it runs. Then turn each pair into a transparent PNG in `docs/images/`:

```sh
scripts/process-shots.sh                 # after /iconic shot tour
scripts/process-shots.sh browser         # after /iconic shot tour browser
```

`/iconic shot` captures whatever browser or picker is open, for one-off images. A new tour view needs `VIEWS`, the `views` list in `process-shots.sh` (same order) and the README updated together.

The script runs on the host and reads the retail Screenshots folder; set `SHOTS_DIR` for WoW Forever. ImageMagick is required. `pngquant` and `oxipng` are optional.

### Demo animation

`docs/images/demo.webp` comes from `/iconic shot demo`. It opens the character window's equipment sets, starts a new set (never saved), and plays the animation's steps letter by letter (steps and display times in `UI/Demo.lua`). After every step it captures a black+white pair like `/iconic shot tour`, keeping the colour picker in the shot, and stores each frame's display time in `IconicDB.demoFrames`. That takes a few minutes; keep the mouse off the windows. `/iconic shot stop` ends it early. Then `/reload`, so the game writes the saved variables, and:

```sh
scripts/make-demo.sh
```

It mattes the newest screenshot pairs (`scripts/matte.sh`, shared with `process-shots.sh`), crops all frames to the recorded area, draws WoW's mouse pointer (`scripts/pointer.png`) at the spot each step recorded, gliding between spots, and joins them with `img2webp` (`brew install webp`). `QUALITY`, `MAX_WIDTH` and `POINTER_SIZE` adjust the result.

## Changelog

Update `CHANGELOG.md` for player-facing changes. One flat list; start each entry with **[New]**, **[Change]**, or **[Fix]**, ordered New, Change, Fix. Phrase **[Fix]** entries as the misbehavior that stopped ("…no longer…").

End an entry that comes from an issue with a full Markdown link, `([#2](https://github.com/whytspace/Iconic/issues/2))`. A bare `#2` links only on GitHub; the changelog also goes to CurseForge and ships in the zip.

## Project rules

- Support WoW Forever and current retail. Guard APIs that only one client has.
- Use `WowScrollBox`, `MinimalScrollBar` and `MenuUtil`. Avoid legacy UI systems.
- Pure logic needs unit tests. Verify UI changes in-game with `/reload`.

## When WoW updates

After a patch to WoW Forever or retail:

1. Update `## Interface` in `Iconic.toc` and `Iconic_Data/Iconic_Data.toc` (both the same). The number is the client version as `MMmmpp`: 12.1.5 → `120105`, 1.60.1 → `16001`. This prints it for each installed client (`wow` retail, `wowf` WoW Forever):

   ```sh
   awk -F'|' 'NR>1 { split($13, v, "."); printf "%s %d\n", $15, v[1]*10000 + v[2]*100 + v[3] }' "/Applications/Games/World of Warcraft/.build.info"
   ```

   An upcoming patch's number that isn't installed yet is listed on [wago.tools/builds](https://wago.tools/builds).
2. Let the launcher finish patching, then extract the icons: `devc python3 -I scripts/extract_icons.py`.
3. Rebuild the colours: `devc python3 -I scripts/build_colors.py --sheets`.
4. Rebuild the data with fresh tables: `devc python3 scripts/build_data.py --refresh`.
5. Run the checks, `/reload` in both clients and open an icon picker.
6. Commit and cut a release (see Releases).

## Releases

Start from a clean `main` branch:

```sh
scripts/release.sh
```

Versions are a plain counter (`v1`, `v2`, …), no semantic versioning. The script bumps both TOC versions and the changelog, runs the checks, commits and tags. It does not push. Pushing a `v*` tag builds the zip (with `Iconic_Data` as its own folder) and publishes the GitHub release. CurseForge also needs `## X-Curse-Project-ID` in `Iconic.toc` and the `CF_API_TOKEN` repository secret.
