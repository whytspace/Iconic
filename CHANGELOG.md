# Changelog

## Unreleased

- **[New]** Suggested icons appear first, fitting what you're editing: your class, spec or talent tree icons and the set's items for equipment sets, the spells and items in a macro, the items in a bank or guild bank tab, the appearances of a transmog outfit, and icons matching the name. ([#13](https://github.com/whytspace/Iconic/issues/13))
- **[New]** Options → AddOns → Iconic can turn off suggested and recently used icons. ([#13](https://github.com/whytspace/Iconic/issues/13))
- **[New]** The icon picker shows how many icons match out of all, such as "312 of 33,097 icons". ([#4](https://github.com/whytspace/Iconic/issues/4))
- **[New]** German: in a German game client, the interface is in German and icons are found by their German and English names. ([#5](https://github.com/whytspace/Iconic/issues/5))
- **[New]** Colour chips have a weight: a slider under the colour picker sets how much each colour counts, such as red with a little green. Lighter chips look smaller. ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[New]** More colour words suggest a chip, such as "dark green", "lime", "crimson" or "navy", each with its own shade. ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[New]** The colour picker opens beside the Iconic window. ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[New]** A gear button in the `/iconic` window opens Iconic's settings.
- **[New]** Baganator's bank tab icon picker gets Iconic too. ([#7](https://github.com/whytspace/Iconic/issues/7))
- **[New]** Icons are found by what their picture shows, such as "werewolf", "rose" or "net", even when no name says so. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[New]** While searching, icon tooltips colour the words that matched and say what found the icon, such as "shield (picture), purple 34%". ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Change]** Clicking the icon under "Currently Selected" again scrolls to its next place in the picker, such as from recently used to all icons, then back to the first.
- **[Change]** Colour chips find every shade of their colour and rank the closest first, whether picked or from a colour word; icons with a smaller part in that colour are found too. ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[Change]** Searches with colour chips rank icons by how well the words match and by colour, not colour alone, and item category names such as "Shield" are searched too. ([#15](https://github.com/whytspace/Iconic/issues/15))
- **[Change]** The search suggestions are wider, so long ones such as item categories are no longer cut off.
- **[Change]** Adding a colour opens the colour picker at white with full lightness; the chip appears with the first colour you pick.
- **[Change]** Closing the colour picker keeps the colour; remove a chip with its X or a right-click. ([#10](https://github.com/whytspace/Iconic/issues/10))
- **[Change]** The `/iconic` window shows the Iconic logo in its top-left corner. ([#14](https://github.com/whytspace/Iconic/issues/14))
- **[Change]** Icons scroll right up to the toolbar and down to the window edge. ([#14](https://github.com/whytspace/Iconic/issues/14))
- **[Change]** Words joined in icon file names are searched one by one, such as "mists" in SoothingMists. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Change]** Icon tooltips get spell and item names from the game, so the icon data takes about 5 MB less; a name the game hasn't loaded yet appears a moment later. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Change]** The icon data leaves out the about 3,000 icons no picker offers, so Iconic loads with about a fifth less memory. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Change]** Achievement titles no longer find icons and the Achievements filter is gone: titles like "School's Out Forever" rarely say what their icon shows. ([#16](https://github.com/whytspace/Iconic/issues/16))
- **[Fix]** The `/iconic` window no longer stays above every other window; the one you clicked last is on top.
- **[Fix]** The `/iconic` window's background no longer shows past its border, and both sides of its icon grid match. ([#14](https://github.com/whytspace/Iconic/issues/14))
- **[Fix]** Pressing Shift, Ctrl or Alt over a unit or other tooltip no longer causes Lua errors. ([#17](https://github.com/whytspace/Iconic/issues/17))
- **[Fix]** Synonyms no longer widen searches to unrelated icons, such as "box" finding chestplates or "helmet" finding capes. ([#16](https://github.com/whytspace/Iconic/issues/16))

## 1.0.0 - 2026-11-22

- **[New]** Colour chips next to the search box: up to three colours an icon must contain, from the colour picker or from a colour word's suggestion, such as "Colour: Red" for "crimson". Icons rank by how close they are; click a chip to change it; its X or a right-click removes it.
- **[Change]** Colour words in the search box suggest a colour chip instead of searching by colour themselves.
- **[Change]** The colour filter is gone; colour chips replace it.
- **[Change]** Grouping by colour puts each icon under its strongest vivid colour, so fewer icons end up under grey, black or brown. It pauses while colour chips are set.
- **[Change]** Colour search and grouping use each icon's dominant colours, so light greys and muted colours are found more reliably.
- **[Change]** Icon data loads faster, and colour grouping and filter counts respond faster.
- **[Change]** The first icon picker of a session opens at once and shows "Loading icons…" until its icons appear.
- **[Fix]** Clicking the icon under "Currently Selected" no longer does nothing: it scrolls to the icon, first clearing the search, colour chips and filters or opening its section if they hide it. The text below says which.

## 0.1.0 - 2026-11-22

- **[New]** Searchable icon picker for macros, equipment sets, bank tabs, guild bank tabs and transmog outfits.
- **[New]** Search by spell, item, mount, pet, achievement and currency names, spell descriptions, synonyms and icon file names, with close matches for typos.
- **[New]** Search by colour: "green" finds icons that look green, ranked by how green they are.
- **[New]** Filter and group icons by colour.
- **[New]** Filter entries show how many icons they match with the current search and other filters; entries with none are greyed out.
- **[New]** Typing in the search box suggests matching filters, such as "Class: Hunter" for "hunt".
- **[New]** Filter and group icons by source, class, item category and profession, or show only your own spells and items.
- **[New]** Recently used icons appear first.
- **[New]** Collapse sections by clicking their header.
- **[New]** Collapse or expand all sections with the toolbar buttons, or by Shift-clicking a section header.
- **[New]** Icon IDs in tooltips: always, never, or while holding Shift, Ctrl or Alt.
- **[New]** `/iconic` opens a standalone icon browser.
- **[New]** About page in Options → AddOns → Iconic.
