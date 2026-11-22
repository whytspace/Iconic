# Iconic

A searchable icon picker for World of Warcraft: WoW Forever and retail.

Iconic replaces the icon grid wherever the game lets you choose an icon: macros, equipment sets, bank tabs, guild bank tabs and transmog outfits.

- **Search** by spell, item, mount, pet, achievement and currency names, spell descriptions and icon file names. "target" finds Hunter's Mark, synonyms find related words, and typos still show close matches.
- **Colours**: "green" finds icons that look green, ranked by how green they are; "red green" needs both, "green gem" combines colour and name.
- **Filter** by source, class, item category, profession and colour, or show only your own spells and items.
- **Group** the grid by the same categories.
- **Recently used** icons come first.
- **Icon IDs** in tooltips, always or while holding Shift, Ctrl or Alt (Options → AddOns → Iconic).
- `/iconic` opens a standalone browser to look up icons and copy their IDs.

## For add-on authors

`Iconic.OpenPicker(onChoose, opts)` opens Iconic as a picker for your add-on. `Iconic.RegisterPicker(frame, adapter)` puts Iconic into your own icon picker. See `UI/API.lua`.

## Data

Icon names and categories come from the game's data tables via [wago.tools](https://wago.tools).
