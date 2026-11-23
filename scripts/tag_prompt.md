You tag World of Warcraft icons by what they show, for a searchable icon picker. Players search with words like "sword", "skull", "lantern", "jellyfish".

First read {chunk}/names.txt: one line per icon, "NNN <Blizzard file name>". Then read each image {chunk}/NNN.png for NNN = 001 to {last} (one icon per image, mostly 64x64 px). Look at every one yourself with the Read tool.

Tag what the picture depicts. Icons are reused for many meanings, so what it looks like matters, not what Blizzard filed it as: a "..._Trinket_..." that shows a skull gets "skull", not "trinket". Use the file name as a hint when the small picture is ambiguous (is the dark shape a belt or gloves? "INV_Belt_..." says belt) and to recognise what you see: if the file name says "Lantern" and the picture shows a lantern, tag "lantern". Never let the file name make you see something that isn't there. The file name gives only one meaning: if the picture can also be read as something else (a ring shaped like a coiled snake, a helmet shaped like a skull), tag those readings too.

For each icon give a list of 2-7 lowercase single English words a player might type to find it:
- first the subject (what it is: "sword", "anchor", "belt", "jellyfish"), then other visible things: further objects, creature type, material, element, notable style ("glowing", "frost", "leather", "chains").
- Words from the file name are fine when they describe what is visible.
- Leave out: synonyms or near-synonyms of words already in the list ("feather" → no "plume", "quill"; a separate synonym table handles those); category or filler words that say nothing about the look ("trinket", "talisman", "relic", "jewelry", "offhand", "misc", "token", "quest", "ability", "spell", "icon", "inv"); expansion, zone, faction or lore names you can't see; colour words (colours are handled separately).
- Fewer, distinct words are better than many overlapping ones.
Single words only, no phrases.

Write the result as JSON to {chunk}/tags.json in exactly this shape, keyed by the number without padding:
{{"1": ["toolbox", "gears", "metal"], "2": [...], ...}}
All {last} keys must be present. Reply only "done".
