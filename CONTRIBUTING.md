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

`scripts/build_data.py` downloads DB2 tables from [wago.tools](https://wago.tools/db2) and writes `Iconic_Data/Forever.lua` and `Iconic_Data/Retail.lua`. Rerun it after a game patch and commit the result:

```sh
devc python3 scripts/build_data.py            # both versions, cached downloads
devc python3 scripts/build_data.py --refresh  # fetch fresh tables
devc python3 scripts/build_data.py forever
```

Downloads are cached in `.cache/wago/`. `spec/data_spec.lua` runs the shipped files through the real search.

`build_data.py` tokenizes names the same way `Search.lua` does (normalize, stopwords, stemming). Change both together; the data spec catches drift.

## Icon colours

Colour scores need the icon images. `scripts/extract_icons.py` reads them straight from a local WoW install's CASC storage (standard library only) into `.cache/icons/`, from the retail and the WoW Forever product. The dev container mounts the install read-only at `/wow`:

- Default source: `/Applications/Games/World of Warcraft`. Elsewhere, set `WOW_DIR` to the install folder before `devc up`.
- Docker Desktop must share that folder: Settings → Resources → File sharing.
- Without a WoW install at that path the container does not start.

```sh
devc python3 -I scripts/extract_icons.py
```

`scripts/build_colors.py` then downloads any icon still missing from wago.tools (slow, about 1–2 per second), scores every icon into `scripts/icon_colors.tsv`, and `build_data.py` merges that into the data files:

```sh
devc python3 -I scripts/build_colors.py --sheets
devc python3 scripts/build_data.py
```

Pixels are converted to OKLab and softly assigned to the nearest of the named colours in `COLORS`; pixels near the centre and saturated pixels weigh more. Each icon keeps the colours with a share of at least `MIN_SHARE` percent. `--sheets` writes `.cache/colors/<colour>.png` with the top icons per colour, for checking the result by eye.

In search, colour words (`COLOR_WORDS` in `Search.lua`) are conditions on these shares, not text: every colour must reach `COLOR_MIN`, and results rank by the weakest one.

## Synonyms

Each line of `Data/Synonyms.lua` is one group of words that find each other's icons. To find candidates, list the words that often share an icon with a given word:

```sh
devc python3 scripts/synonym_candidates.py target heal shield
```

Add a group only when a player would plausibly search one word to find the other.

## Picker adapters

`UI/Pickers.lua` replaces the icon grid of every frame built on Blizzard's `IconSelectorPopupFrameTemplate`. A new Blizzard picker is one entry in `Pickers.BLIZZARD`. Other add-ons call `Iconic.RegisterPicker(frame, adapter)`, documented in `UI/API.lua`.

## Assets

`Assets/swatch.tga`, the shaded sphere behind colour swatches, is generated: `devc python3 -I scripts/build_swatch.py`.

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

## Changelog

Update `CHANGELOG.md` for player-facing changes. One flat list; start each entry with **[New]**, **[Change]**, or **[Fix]**, ordered New, Change, Fix. Phrase **[Fix]** entries as the misbehavior that stopped ("…no longer…").

## Project rules

- Support WoW Forever and current retail. Guard APIs that only one client has.
- Use `WowScrollBox`, `MinimalScrollBar` and `MenuUtil`. Avoid legacy UI systems.
- Pure logic needs unit tests. Verify UI changes in-game with `/reload`.

## Releases

Start from a clean `main` branch:

```sh
scripts/release.sh patch
```

The script bumps both TOC versions and the changelog, runs the checks, commits and tags. It does not push. Pushing a `v*` tag builds the zip (with `Iconic_Data` as its own folder) and publishes the GitHub release. CurseForge also needs `## X-Curse-Project-ID` in `Iconic.toc` and the `CF_API_TOKEN` repository secret.
