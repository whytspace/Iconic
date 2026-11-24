# Changelog

## Unreleased

- **[Change]** Picture tags use the singular only ("gem" instead of both "gem" and "gems").

## v3 - 2026-11-24

- **[Change]** Texts use American spelling ("color", "gray").
- **[Fix]** Searching "grey" no longer misses icons named "gray", and the other way round.

## v2 - 2026-11-24

- **[New]** Suggested icons that fit what you're editing. ([#13](https://github.com/whytspace/Iconic/issues/13))
- **[New]** Over 30,000 icons analyzed by what they show, so searches like "werewolf" or "rose" find them. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[New]** German support: icons are found by their German names and by what they show. ([#5](https://github.com/whytspace/Iconic/issues/5))
- **[New]** Color weights: mix colors, such as red with a little green. ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[New]** More color words, such as "dark green", "crimson" or "navy". ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[New]** Tooltips show why an icon matched your search. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[New]** The icon picker shows how many icons match. ([#4](https://github.com/whytspace/Iconic/issues/4))
- **[New]** Support for Baganator's bank tab icon picker. ([#7](https://github.com/whytspace/Iconic/issues/7))
- **[New]** Icon tooltips list the icon's tags and only the names your search finds; hold Shift for all names.
- **[New]** A gear button in the icon picker opens Iconic's settings.
- **[Change]** Better results for searches with colors: words and color count together. ([#15](https://github.com/whytspace/Iconic/issues/15))
- **[Change]** Reduced memory usage by roughly 20%. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Change]** Removed search by achievement titles and the Achievements filter. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Change]** The `/iconic` window works like other game windows: the one you clicked last is on top.
- **[Fix]** Lua errors when pressing Shift, Ctrl or Alt over a tooltip. ([#17](https://github.com/whytspace/Iconic/issues/17))
- **[Fix]** Searches no longer find unrelated icons, such as "box" finding chestplates. ([#16](https://github.com/whytspace/Iconic/issues/16))

## v1 - 2026-11-22

- **[New]** Color chips: combine up to three colors, from the color picker or a color word. They replace the color filter.
- **[Change]** Grouping by color puts more icons under their actual color instead of gray, black or brown.
- **[Change]** Color search finds light grays and muted colors more reliably.
- **[Change]** Faster loading: the first icon picker opens at once.
- **[Fix]** Clicking the icon under "Currently Selected" scrolls to it.

## v0 - 2026-11-22

- **[New]** Searchable icon picker for macros, equipment sets, bank tabs, guild bank tabs and transmog outfits.
- **[New]** Search by spell, item, mount, pet, achievement and currency names and spell descriptions, with close matches for typos.
- **[New]** Search and group icons by color.
- **[New]** Filter and group icons by source, class, item category and profession, or show only your own spells and items.
- **[New]** Filters show how many icons they match, and typing suggests matching filters.
- **[New]** Recently used icons appear first.
- **[New]** Collapsible sections.
- **[New]** Icon IDs in tooltips.
- **[New]** `/iconic` opens a standalone icon browser.
