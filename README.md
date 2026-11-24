<p align="center">
  <img src="Assets/logo.png" alt="Iconic" width="160">
</p>

# Iconic

**A searchable icon picker for World of Warcraft: WoW Forever and retail.**

Imagine you've just put together a new equipment set or written the perfect macro. But now it needs an icon. After scrolling through WoW's 33,000 icons looking for the right one, you just give up.

Why is it so hard to find the icon you have in mind? Why can't you just search for "golden shield" or "arrow", or even for your favourite spell or item?

This is where **Iconic** comes in. It adds a search box, filters and categories to the icon picker, so you find exactly the icon you want.

> ⚠️ **Early version:** please report bugs on [GitHub](https://github.com/whytspace/Iconic/issues).

*My new "Avenger Tank" outfit is finally ready. Now it needs an icon… something purple.*<br>
*A shield, maybe?*<br>
*With a hint of gold. Just a hint.*

![Finding an icon for a new equipment set with Iconic](https://raw.githubusercontent.com/whytspace/Iconic/main/docs/images/demo.webp)

**A few seconds, and there it is.**

Iconic replaces the icon grid wherever the game lets you choose an icon:

- Macros
- Equipment sets
- Bank tabs
- Guild bank tabs
- Transmog outfits
- Other add-ons that use it

![Iconic in the macro window](https://raw.githubusercontent.com/whytspace/Iconic/main/docs/images/picker.png)

## Finding icons

- **What icons show:** we analysed over 30,000 icons, so you can search by what they show, such as "werewolf" or "rose". Spell, item, mount, pet and currency names work too, and typos still find close matches.
- **Colours:** search by one or more colours. Icons are sorted by how closely they match. Looking for an icon that's red and green? Iconic has you covered.
- **Filters:** source, class, item category and profession, or only your own spells and items.
- **Grouping:** group the icons by source, class, item category, profession or colour.
- **Suggestions:** icons that fit where you opened the picker, such as the items in a bank tab, the spells in a macro or your spec icons.
- **Recently used:** the icons you picked last.
- **Icon IDs** in tooltips, always or while holding Shift, Ctrl or Alt (Options → AddOns → Iconic).
- **German:** in a German game client, the interface is in German and icons are found by their German and English names.
- `/iconic` opens a standalone browser to look up icons and copy their IDs.

![Colour search](https://raw.githubusercontent.com/whytspace/Iconic/main/docs/images/colours.png)

## Install

- **CurseForge:** install [Iconic – Icon Search](https://www.curseforge.com/wow/addons/iconic-icon-search) with the CurseForge app.
- **Manually:** download `Iconic-vN.zip` from the [latest release](https://github.com/whytspace/Iconic/releases/latest) and unpack both folders, `Iconic` and `Iconic_Data`, into `World of Warcraft/_retail_/Interface/AddOns` (`_forever_` for WoW Forever).

## Getting started

1. Open the macro window (`/macro`) and create or edit a macro. Iconic replaces the icon grid.
2. Type in the search box, or pick filters from the toolbar.
3. Type `/iconic` to browse icons without changing anything, and `/iconic settings` for the options.

## For add-on authors

`Iconic.OpenPicker(onChoose, opts)` opens Iconic as a picker for your add-on. `Iconic.RegisterPicker(frame, adapter)` puts Iconic into your own icon picker. See `UI/API.lua`.

## License

Released under the [GNU GPLv3](LICENSE). Forks must stay open and credit "Iconic by whytspace".
