local ADDON_NAME, ns = ...

local L = ns.L
local Catalog, Color, Search, Tooltips, View = ns.Catalog, ns.Color, ns.Search, ns.Tooltips, ns.View

-- Blizzard's submenu arrow, a bit smaller than the text.
local SYNONYM_ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:8|t"

-- How a tooltip names where a search word matched (Search.Explain).
local MATCH_PLACES = {
  description = "description",
  category = "Blizzard category",
}

-- Tooltip for an icon row, anchored to `owner` (defaults to the hovered button's row).
function View:ShowTooltip(owner, row)
  local index = self.data.index
  row = row or owner.row
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local names, pending = Catalog.Names(index, row)
  if pending then
    Tooltips.AfterNames("tooltip", function()
      if GameTooltip:IsOwned(owner) then
        self:ShowTooltip(owner, row)
      end
    end)
  end
  -- While searching, the words a search word finds are colored and a line says what found the icon.
  local query, _, searching = self:Query()
  local opts = self:SearchOptions()
  local function shown(name)
    return searching and Search.Highlight(name, query, opts) or name
  end
  GameTooltip:SetText(names[1] and shown(names[1]) or index.file[row] or tostring(index.key[row]), 1, 1, 1)
  -- Below the best name only the names a search word finds, or all with the setting; the rest are counted.
  local all = Tooltips.ModeActive(ns.db.settings.tooltipNames)
  local hidden = 0
  for i = 2, #names do
    local name = searching and shown(names[i]) or names[i]
    if all or name ~= names[i] then
      GameTooltip:AddLine(name, 0.8, 0.8, 0.8)
    else
      hidden = hidden + 1
    end
  end
  if hidden > 0 then
    GameTooltip:AddLine(hidden == 1 and L["+1 more name"] or L["+%d more names"]:format(hidden), 0.5, 0.5, 0.5)
  end
  -- Picture tags in the client's language, the ones a search word finds colored.
  local tags = {}
  for tag in (index.tags[row] or ""):gmatch("%S+") do
    tags[#tags + 1] = self.data.tagNames and self.data.tagNames[tag] or tag
  end
  local tagText = table.concat(tags, ", ")
  if tagText ~= "" then
    GameTooltip:AddLine(
      L["Tags: %s"]:format(searching and Search.Highlight(tagText, query, opts) or tagText),
      0.6,
      0.6,
      0.6,
      true
    )
  end
  if searching then
    local parts = {}
    for _, found in ipairs(Search.Explain(index, row, query, opts)) do
      if found.word then
        -- Direct hits in a shown name or tag are colored there; only the rest need saying.
        local seen = not found.via
          and (
            found.where == "name" or (found.where == "tag" and Search.Highlight(tagText, found.word, opts) ~= tagText)
          )
        if not seen then
          local word = found.word
          for _, step in ipairs(found.via or {}) do
            word = ("%s %s %s"):format(word, SYNONYM_ARROW, step)
          end
          -- Places the tooltip doesn't show get named; a direct hit in the tag field not among the tags is the file name.
          local place = (found.where == "description" or found.where == "category") and MATCH_PLACES[found.where]
            or (not found.via and found.where == "tag" and "file name")
          parts[#parts + 1] = place and ("%s (%s)"):format(word, L[place]) or word
        end
      else
        local preset = Color.Preset(found.color)
        parts[#parts + 1] = ("%s %d%%"):format(preset and L[preset.label] or found.color, found.share)
      end
    end
    if #parts > 0 then
      GameTooltip:AddLine(L["Found by: %s"]:format(table.concat(parts, ", ")), 1, 0.82, 0, true)
    end
  end
  if index.id[row] and Tooltips.ModeActive(ns.db.settings.tooltipPicker) then
    GameTooltip:AddLine(L["Icon ID: %d"]:format(index.id[row]), 0.5, 0.8, 1)
  end
  GameTooltip:Show()
  Tooltips.WatchModifiers(owner, function()
    self:ShowTooltip(owner, row)
  end)
end
