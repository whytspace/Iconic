local ADDON_NAME, ns = ...

local L = ns.L
local Catalog, Search = ns.Catalog, ns.Search

-- Icons grow from MIN_ICON_SIZE to fill the row; HEADER_GAP separates a header band from its icons.
local MIN_ICON_SIZE, ICON_GAP, ROW_INSET = 34, 4, 8
local BAND_HEIGHT, HEADER_GAP, SECTION_GAP, TOOLBAR_HEIGHT = 26, 8, 8, 40
local HEADER_HEIGHT = BAND_HEIGHT + HEADER_GAP + 2
local SEARCH_DELAY = 0.2
-- While a colour is dragged in the picker, the grid follows at most this often.
local PICK_INTERVAL = 0.1
local MIN_QUERY = 2
local MAX_SUGGESTED_ROWS = 3
local FOOTER_HEIGHT = 16
local GRID_PAD_TOP, GRID_PAD_BOTTOM = 7, 6
local SUGGEST_WIDTH = 320

local View = {}
View.__index = View

-- Blizzard's submenu arrow, a bit smaller than the text.
local SYNONYM_ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:8|t"

-- How a tooltip names where a search word matched (Search.Explain).
local MATCH_PLACES = {
  name = "name",
  file = "file name",
  picture = "picture",
  description = "description",
  category = "item category",
}

-- Calls `fn` once the game has loaded spell or item names it was asked for (Catalog.NameOf); a later wait for the
-- same key replaces an earlier one.
-- The events that answer C_Item.RequestLoadItemDataByID and C_Spell.RequestLoadSpellData.
local NAME_EVENTS = { "ITEM_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT" }
local nameWaits = {}
local nameEvents = CreateFrame("Frame")
nameEvents:SetScript("OnEvent", function()
  for _, event in ipairs(NAME_EVENTS) do
    nameEvents:UnregisterEvent(event)
  end
  local waits = nameWaits
  nameWaits = {}
  for _, fn in pairs(waits) do
    fn()
  end
end)
function ns.AfterNames(key, fn)
  nameWaits[key] = fn
  for _, event in ipairs(NAME_EVENTS) do
    nameEvents:RegisterEvent(event)
  end
end

local function isSpellKnown(spellId)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    return C_SpellBook.IsSpellKnown(spellId)
  end
  return IsPlayerSpell and IsPlayerSpell(spellId)
end

-- Keys of icons the player can use right now: known class spells, bag and equipped items, extra icons.
local function computeUsable(data, extraTextures)
  local set, index = {}, data.index
  for row = 1, index.count do
    local spells = index.spells[row]
    if spells then
      for _, id in ipairs(spells) do
        if isSpellKnown(id) then
          set[index.key[row]] = true
          break
        end
      end
    end
  end
  local function add(texture)
    local id = Catalog.ResolveId(data, texture)
    if id or texture then
      set[id or texture] = true
    end
  end
  for _, texture in ipairs(extraTextures or {}) do
    add(texture)
  end
  if C_Container and C_Container.GetContainerNumSlots then
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.iconFileID then
          add(info.iconFileID)
        end
      end
    end
  end
  for slot = 1, 19 do
    local texture = GetInventoryItemTexture("player", slot)
    if texture then
      add(texture)
    end
  end
  return set
end

local function selectedSet(filters, dim)
  filters[dim] = filters[dim] or {}
  return filters[dim]
end

local function sortedKeys(map, numericOnly)
  local keys = {}
  for key in pairs(map) do
    if not numericOnly or type(key) == "number" then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return tostring(map[a]) < tostring(map[b])
  end)
  return keys
end

local MENU_ICON = 16
-- Shaded grey sphere (scripts/build_swatch.py), tinted per colour.
local SWATCH = "Interface\\AddOns\\Iconic\\Assets\\swatch"
-- Hue wheel on the same sphere (scripts/build_swatch.py), for the button that adds a colour chip.
local COLOR_WHEEL = "Interface\\AddOns\\Iconic\\Assets\\colorwheel"
local SWATCH_ROW_SIZE, SUGGESTION_ICON_SIZE = 12, 19

-- Class name in its class color, with the class icon.
local function classLabel(classId, name)
  local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classId)
  local file = info and info.classFile
  if not file then
    return name
  end
  local color = (C_ClassColor and C_ClassColor.GetClassColor(file)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file])
  local text = color and color:WrapTextInColorCode(name) or name
  return CreateAtlasMarkup(GetClassAtlas(file), MENU_ICON, MENU_ICON) .. " " .. text
end

local function iconLabel(icon, name)
  return icon and ("|T" .. icon .. ":" .. MENU_ICON .. ":" .. MENU_ICON .. "|t " .. name) or name
end

local MENU_ROW_HEIGHT, MENU_CHECK_WIDTH, MENU_COUNT_GAP, MENU_ARROW_WIDTH = 20, 22, 18, 22

local function greyed(text)
  return "|cff808080" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
end

-- Shows a right-aligned count in a menu entry (in front of the submenu arrow when there is one) and greys
-- the label when the count is zero. Runs on every menu refresh, so it reads the count live.
local function addCount(description, label, getCount, isSelected, hasSubmenu)
  description:AddInitializer(function(button)
    local count = getCount()
    button.fontString:SetText((count == 0 and not isSelected()) and greyed(label) or label)
    local text = button:AttachFontString()
    text:SetFontObject("GameFontDisableSmall")
    text:SetHeight(MENU_ROW_HEIGHT)
    text:SetJustifyH("RIGHT")
    text:SetPoint("RIGHT", hasSubmenu and -MENU_ARROW_WIDTH or -4, 0)
    text:SetText(count)
    local width = MENU_CHECK_WIDTH
      + button.fontString:GetUnboundedStringWidth()
      + MENU_COUNT_GAP
      + text:GetUnboundedStringWidth()
      + (hasSubmenu and MENU_ARROW_WIDTH or 4)
    return width, MENU_ROW_HEIGHT
  end)
end

-- Subclass keys ("2:7") of an item class, sorted by name.
local function subcategories(itemClasses, top)
  local prefix, keys = top .. ":", {}
  for key in pairs(itemClasses) do
    if type(key) == "string" and key:sub(1, #prefix) == prefix then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return itemClasses[a] < itemClasses[b]
  end)
  return keys
end

function View:SetupFilterMenu()
  local view = self
  local function toggle(dim, value)
    return function()
      local set = selectedSet(view.filters, dim)
      set[value] = not set[value] or nil
      view:Refresh()
      return MenuResponse.Refresh
    end
  end
  local function isSet(dim, value)
    return function()
      return view.filters[dim] and view.filters[dim][value] or false
    end
  end
  local function allSet(dim, values)
    return function()
      local set = view.filters[dim] or {}
      for _, value in ipairs(values) do
        if not set[value] then
          return false
        end
      end
      return true
    end
  end
  -- Selects every value, or clears them all when every one is already selected.
  local function toggleAll(dim, values)
    return function()
      local set, all = selectedSet(view.filters, dim), true
      for _, value in ipairs(values) do
        all = all and set[value] == true
      end
      for _, value in ipairs(values) do
        set[value] = (not all) or nil
      end
      view:Refresh()
      return MenuResponse.Refresh
    end
  end

  self.filter:SetupMenu(function(_, root)
    local data = view.data
    -- Totals decide which values exist at all; facet counts (under the other active filters and the search)
    -- are shown, and values with none are greyed out but stay visible.
    local totals = view.counts or {}
    local function total(dim, value)
      return totals[dim] and totals[dim][value] or 0
    end
    local function facet(dim, value)
      local facets = view:FacetCounts()
      return facets[dim] and facets[dim][value] or 0
    end
    local function present(dim, values)
      local list = {}
      for _, value in ipairs(values) do
        if total(dim, value) > 0 then
          list[#list + 1] = value
        end
      end
      return list
    end
    -- A checkbox entry with its right-aligned count; greyed at zero unless it is ticked.
    local function entry(parent, label, dim, value, isSelected, setSelected, hasSubmenu)
      local description = parent:CreateCheckbox(label, isSelected, setSelected)
      addCount(description, label, function()
        return facet(dim, value)
      end, isSelected, hasSubmenu)
      return description
    end

    root:CreateCheckbox(L["Only my spells & items"], function()
      return view.filters.usable or false
    end, function()
      view.filters.usable = not view.filters.usable or nil
      view:Refresh()
      return MenuResponse.Refresh
    end)
    root:CreateDivider()

    local sources = {}
    for _, source in ipairs(Catalog.SOURCES) do
      if total("source", source.key) > 0 then
        sources[#sources + 1] = source
      end
    end
    if #sources > 0 then
      local menu = root:CreateButton(L["Source"])
      for _, source in ipairs(sources) do
        entry(menu, L[source.label], "source", source.key, isSet("source", source.key), toggle("source", source.key))
      end
    end
    if not data then
      return
    end

    local classIds = present("class", sortedKeys(data.classes))
    if #classIds > 0 then
      local menu = root:CreateButton(L["Class"])
      for _, classId in ipairs(classIds) do
        local label = classLabel(classId, data.classes[classId])
        entry(menu, label, "class", classId, isSet("class", classId), toggle("class", classId))
      end
    end

    local tops = present("category", sortedKeys(data.itemClasses, true))
    if #tops > 0 then
      local menu = root:CreateButton(L["Item category"])
      for _, top in ipairs(tops) do
        local keys = present("category", subcategories(data.itemClasses, top))
        local name = data.itemClasses[top]
        if #keys <= 1 then
          -- A lone subcategory adds nothing; filter by it straight from the category entry.
          local key = keys[1] or top
          entry(menu, name, "category", key, isSet("category", key), toggle("category", key))
        else
          -- Checking the category selects all its subcategories; hovering opens them.
          local sub = entry(menu, name, "category", top, allSet("category", keys), toggleAll("category", keys), true)
          for _, key in ipairs(keys) do
            entry(sub, data.itemClasses[key], "category", key, isSet("category", key), toggle("category", key))
          end
        end
      end
    end

    local profs = present("profession", sortedKeys(data.professions))
    if #profs > 0 then
      local menu = root:CreateButton(L["Profession"])
      for _, prof in ipairs(profs) do
        local label = iconLabel(data.professionIcons and data.professionIcons[prof], data.professions[prof])
        entry(menu, label, "profession", prof, isSet("profession", prof), toggle("profession", prof))
      end
    end
  end)

  self.filter:SetIsDefaultCallback(function()
    return Catalog.ActiveFilterCount(view.filters) == 0
  end)
  self.filter:SetDefaultCallback(function()
    view.filters = {}
    view:Refresh()
  end)
end

-- Filter-style button whose fixed text names the current grouping.
function View:UpdateGroupText()
  local current = ns.db and ns.db.groupBy or "none"
  for _, entry in ipairs(Catalog.GROUPS) do
    if entry.key == current then
      self.group:SetText(L["Group by: %s"]:format(L[entry.label]))
    end
  end
end

function View:SetupGroupMenu()
  local view = self
  self.group:SetupMenu(function(_, root)
    for _, entry in ipairs(Catalog.GROUPS) do
      root:CreateRadio(L[entry.label], function()
        return (ns.db and ns.db.groupBy or "none") == entry.key
      end, function()
        if ns.db then
          ns.db.groupBy = entry.key
        end
        view:UpdateGroupText()
        view:Refresh()
      end, entry.key)
    end
  end)
  self:UpdateGroupText()
end

local BAND_ALPHA, BAND_HOVER_ALPHA = 0.12, 0.2
local TOGGLE_SIZE, TOGGLE_ALPHA = 9, 0.6

local function setBandAlpha(frame, alpha)
  frame.band:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, alpha), CreateColor(1, 1, 1, 0.02))
end

-- A drawn +/- sign: a horizontal bar, plus a vertical one shown via sign.down:SetShown(true).
local function createSign(parent, size)
  local sign = CreateFrame("Frame", nil, parent)
  sign:SetSize(size, size)
  sign.across = sign:CreateTexture(nil, "OVERLAY")
  sign.across:SetColorTexture(1, 1, 1, 1)
  sign.across:SetSize(size, 2)
  sign.across:SetPoint("CENTER")
  sign.down = sign:CreateTexture(nil, "OVERLAY")
  sign.down:SetColorTexture(1, 1, 1, 1)
  sign.down:SetSize(2, size)
  sign.down:SetPoint("CENTER")
  return sign
end

-- Section header: a band fading out to the right, with the title, icon count and a +/- to collapse it.
-- Shift-click collapses or expands every section.
function View:InitHeader(frame, elementData)
  if not frame.label then
    frame.band = frame:CreateTexture(nil, "BACKGROUND")
    frame.band:SetPoint("BOTTOMLEFT", 0, HEADER_GAP)
    frame.band:SetPoint("BOTTOMRIGHT", 0, HEADER_GAP)
    frame.band:SetHeight(BAND_HEIGHT)
    frame.band:SetColorTexture(1, 1, 1, 1)
    setBandAlpha(frame, BAND_ALPHA)
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    frame.label:SetPoint("LEFT", frame.band, "LEFT", ROW_INSET + 8, 0)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.count:SetPoint("BOTTOMLEFT", frame.label, "BOTTOMRIGHT", 8, 1)
    -- Drawn +/-: a horizontal bar, plus a vertical bar while collapsed.
    frame.toggle = createSign(frame, TOGGLE_SIZE)
    frame.toggle:SetPoint("RIGHT", frame.band, "RIGHT", -12, 0)
    frame.toggle:SetAlpha(TOGGLE_ALPHA)
    frame:SetScript("OnClick", function(header)
      self:ToggleSection(header.sectionKey, IsShiftKeyDown())
    end)
    frame:SetScript("OnEnter", function(header)
      setBandAlpha(header, BAND_HOVER_ALPHA)
      header.toggle:SetAlpha(1)
    end)
    frame:SetScript("OnLeave", function(header)
      setBandAlpha(header, BAND_ALPHA)
      header.toggle:SetAlpha(TOGGLE_ALPHA)
    end)
  end
  frame.sectionKey = elementData.key
  frame.label:SetText(elementData.header)
  frame.count:SetText(elementData.count or "")
  frame.toggle.down:SetShown(elementData.collapsed)
end

-- Grouping in effect: grouping by colour pauses while colour chips rank the icons.
function View:GroupBy()
  local groupBy = ns.db and ns.db.groupBy or "none"
  if groupBy == "color" and #self.chips > 0 then
    return "none"
  end
  return groupBy
end

-- Collapse state lives per group-by, keyed by section value.
function View:CollapsedSet()
  local groupBy = self:GroupBy()
  local all = ns.db and ns.db.collapsed or {}
  all[groupBy] = all[groupBy] or {}
  return all[groupBy]
end

-- Collapses or expands every visible section.
function View:SetAllCollapsed(collapse)
  local set = self:CollapsedSet()
  for _, sectionKey in ipairs(self.sectionKeys or {}) do
    set[sectionKey] = collapse or nil
  end
  self:Refresh(true)
end

-- Toggles one section, or with `all` sets every visible section to that section's new state.
function View:ToggleSection(key, all)
  local set = self:CollapsedSet()
  local collapse = not set[key]
  if all then
    self:SetAllCollapsed(collapse)
    return
  end
  set[key] = collapse or nil
  self:Refresh(true)
end

-- Small toolbar button with a drawn sign and a tooltip.
function View:CreateSignButton(parent, plus, tooltip, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(22, 22)
  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.bg:SetColorTexture(1, 1, 1, 0.06)
  button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local sign = createSign(button, TOGGLE_SIZE)
  sign:SetPoint("CENTER")
  sign.down:SetShown(plus)
  sign:SetAlpha(0.8)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(tooltip, 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

local MAX_CHIPS, CHIP_SIZE, CHIP_GAP, CHIP_MIN_SWATCH = 3, 22, 8, 8
local MIN_WEIGHT = 0.1
-- Size of the red X on colour chips and on the filter button (Blizzard's is 23).
local RESET_SIZE = 20

-- A colour chip: its colour { r, g, b } (0-1), OKLab target, weight (0.1-1) and the preset it came from, if any.
local function newChip(color, weight, preset)
  return { color = color, target = Search.PickTarget(color.r, color.g, color.b), weight = weight or 1, preset = preset }
end

local function chipLabel(chip)
  local preset = chip.preset and Search.Preset(chip.preset)
  if preset then
    return L[preset.label]
  end
  local c = chip.color
  return ("#%02X%02X%02X"):format(c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5)
end

local function createColorButton(parent, onClick, onEnter)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(CHIP_SIZE, CHIP_SIZE)
  button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  button.swatch = button:CreateTexture(nil, "ARTWORK")
  button.swatch:SetSize(20, 20)
  button.swatch:SetPoint("CENTER")
  -- Sub-pixel sizes, so a chip shrinks smoothly with its weight.
  button.swatch:SetSnapToPixelGrid(false)
  button.swatch:SetTexelSnappingBias(0)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    onEnter(owner)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

-- Colour chips and the button that adds one, in a bar left of the filter button. Each chip is a colour the icons
-- must contain: click changes it in Blizzard's colour picker, right-click removes it.
function View:CreateColorBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(CHIP_SIZE)
  self.chipButtons = {}
  for i = 1, MAX_CHIPS do
    local button = createColorButton(bar, function(_, mouseButton)
      if mouseButton == "RightButton" then
        self:RemoveChip(i)
      else
        self:OpenColorPicker(i)
      end
    end, function()
      local chip = self.chips[i]
      GameTooltip:SetText(chipLabel(chip), 1, 1, 1)
      if #self.chips > 1 then
        GameTooltip:AddLine(L["Weight: %d%%"]:format(chip.weight * 100 + 0.5), 0.9, 0.9, 0.9)
      end
      GameTooltip:AddLine(L["Click to change; the X or right-click removes it"], 0.7, 0.7, 0.7)
    end)
    button.swatch:SetTexture(SWATCH)
    -- The same red X as the filter button's reset, in the chip's corner.
    local remove = CreateFrame("Button", nil, button)
    -- Level with the filter's X: on the filter's top edge, 3 px in from the swatch's right edge.
    remove:SetSize(RESET_SIZE, RESET_SIZE)
    remove:SetPoint("CENTER", button, "CENTER", 7, self.filter:GetHeight() / 2)
    remove:SetFrameLevel(button:GetFrameLevel() + 2)
    remove:SetNormalAtlas("auctionhouse-ui-filter-redx")
    remove:SetHighlightAtlas("auctionhouse-ui-filter-redx", "ADD")
    remove:GetHighlightTexture():SetAlpha(0.4)
    remove:SetScript("OnClick", function()
      self:RemoveChip(i)
    end)
    self.chipButtons[i] = button
  end
  self.addColorButton = createColorButton(bar, function(_, mouseButton)
    if mouseButton ~= "RightButton" then
      self:OpenColorPicker()
    end
  end, function()
    GameTooltip:SetText(L["Search by colour"], 1, 1, 1)
  end)
  self.addColorButton.swatch:SetTexture(COLOR_WHEEL)
  return bar
end

-- Lays out the chips and the add button, right-aligned in the bar.
function View:UpdateChips()
  local buttons = {}
  for i, button in ipairs(self.chipButtons) do
    local chip = self.chips[i]
    button:SetShown(chip ~= nil)
    if chip then
      local weight = #self.chips > 1 and chip.weight or 1
      local c, size = chip.color, CHIP_MIN_SWATCH + (20 - CHIP_MIN_SWATCH) * weight
      button.swatch:SetVertexColor(c.r, c.g, c.b)
      -- Lighter chips look smaller.
      button.swatch:SetSize(size, size)
      buttons[#buttons + 1] = button
    end
  end
  self.addColorButton:SetShown(#self.chips < MAX_CHIPS)
  if #self.chips < MAX_CHIPS then
    buttons[#buttons + 1] = self.addColorButton
  end
  for i, button in ipairs(buttons) do
    button:ClearAllPoints()
    button:SetPoint("LEFT", (i - 1) * (CHIP_SIZE + CHIP_GAP), 0)
  end
  self.colorBar:SetWidth(#buttons * (CHIP_SIZE + CHIP_GAP) - CHIP_GAP)
end

-- Replaces all chips: a list of { key = preset key } or { color = { r, g, b }, weight, preset }.
function View:SetChips(chips)
  self.chips = {}
  for i, chip in ipairs(chips) do
    if chip.color then
      self.chips[i] = newChip(chip.color, chip.weight, chip.preset)
    else
      self.chips[i] = newChip(Search.HexColor(Search.Preset(chip.key).hex), chip.weight, chip.key)
    end
  end
  self:UpdateChips()
  self:QueuePickRefresh()
end

-- Sets chip `i` (or a new last chip) to a picked colour { r, g, b }, keeping its weight.
function View:SetChipColor(i, color, weight)
  local chips = self.chips
  i = math.min(i, #chips + 1, MAX_CHIPS)
  chips[i] = newChip(color, weight or (chips[i] and chips[i].weight))
  self:UpdateChips()
  self:QueuePickRefresh()
end

-- Sets the weight (MIN_WEIGHT-1) of chip `i`.
function View:SetChipWeight(i, weight)
  local chip = self.chips[i]
  if chip then
    self.chips[i] = newChip(chip.color, math.max(MIN_WEIGHT, math.min(1, weight)), chip.preset)
    self:UpdateChips()
    self:QueuePickRefresh()
  end
end

-- Adds a chip for a colour preset unless it is there already or the bar is full.
function View:AddPresetChip(key)
  for _, chip in ipairs(self.chips) do
    if chip.preset == key then
      return
    end
  end
  local preset = Search.Preset(key)
  if preset and #self.chips < MAX_CHIPS then
    self.chips[#self.chips + 1] = newChip(Search.HexColor(preset.hex), 1, key)
    self:UpdateChips()
  end
end

function View:RemoveChip(i)
  table.remove(self.chips, i)
  self:UpdateChips()
  self:QueuePickRefresh()
end

-- Refreshes soon after a colour change; unlike QueueRefresh, further changes don't push it back, so the grid
-- keeps up while the colour is dragged.
function View:QueuePickRefresh()
  if self.pickRefreshQueued then
    return
  end
  self.pickRefreshQueued = true
  C_Timer.After(PICK_INTERVAL, function()
    self.pickRefreshQueued = false
    self:Refresh()
  end)
end

-- Blizzard's colour picker is shared: while Iconic uses it, its Cancel button is hidden and Okay centred, it sits beside
-- Iconic's window, and a weight slider hangs below it. All is restored when it closes.
local picker, weightPanel

local WEIGHT_OVERLAP = 8

-- Below the picker, in the same dialog border, joined to it.
local function createWeightPanel(frame)
  local panel = CreateFrame("Frame", nil, frame)
  -- Overlaps the picker by its border, so one border line separates the two.
  panel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, WEIGHT_OVERLAP)
  panel:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, WEIGHT_OVERLAP)
  panel:SetHeight(96)
  panel.border = CreateFrame("Frame", nil, panel, "DialogBorderTemplate")
  panel.border:SetAllPoints()
  panel.label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.label:SetPoint("TOPLEFT", 18, -16)
  panel.label:SetText(L["Weight"])
  panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.hint:SetPoint("TOPLEFT", panel.label, "BOTTOMLEFT", 0, -4)
  panel.hint:SetPoint("RIGHT", -18, 0)
  panel.hint:SetJustifyH("LEFT")
  panel.hint:SetText(L["How much this colour counts in the colour search."])
  panel.slider = CreateFrame("Frame", nil, panel, "MinimalSliderWithSteppersTemplate")
  panel.slider:SetPoint("TOPLEFT", panel.hint, "BOTTOMLEFT", -2, -6)
  panel.slider:SetPoint("RIGHT", -64, 0)
  panel.slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    if panel.view then
      panel.view:SetPickerWeight(value / 100)
    end
  end, panel)
  return panel
end

local function preparePicker(anchor)
  local frame = ColorPickerFrame
  if not picker then
    picker = {}
    frame:HookScript("OnHide", function()
      if picker.okay then
        picker.cancel:Show()
        picker.okay:ClearAllPoints()
        for _, point in ipairs(picker.okayPoints) do
          picker.okay:SetPoint(unpack(point))
        end
      end
      if picker.points then
        frame:ClearAllPoints()
        for _, point in ipairs(picker.points) do
          frame:SetPoint(unpack(point))
        end
        frame:SetClampedToScreen(picker.clamped)
        picker.points = nil
      end
      if weightPanel then
        weightPanel:Hide()
        weightPanel.view = nil
      end
    end)
  end
  local cancel = frame.Footer and frame.Footer.CancelButton or _G.ColorPickerCancelButton
  local okay = frame.Footer and frame.Footer.OkayButton or _G.ColorPickerOkayButton
  if cancel and okay and cancel:IsShown() then
    picker.cancel, picker.okay, picker.okayPoints = cancel, okay, {}
    for i = 1, okay:GetNumPoints() do
      picker.okayPoints[i] = { okay:GetPoint(i) }
    end
    local _, _, _, _, y = cancel:GetPoint(1)
    cancel:Hide()
    okay:ClearAllPoints()
    okay:SetPoint("BOTTOM", cancel:GetParent(), "BOTTOM", 0, y or 0)
  end
  if not picker.points then
    picker.points, picker.clamped = {}, frame:IsClampedToScreen()
    for i = 1, frame:GetNumPoints() do
      picker.points[i] = { frame:GetPoint(i) }
    end
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -2, -1)
  frame:SetClampedToScreen(true)
end

-- Opens Blizzard's colour picker for chip `i`, or for a new chip; the grid follows the colour and weight while they
-- change, and closing the picker keeps them.
function View:OpenColorPicker(i)
  if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
  end
  if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
    return
  end
  local slot = i or #self.chips + 1
  -- Counted before the picker opens: it reports its start colour at once, which already adds a new chip.
  local chipCount = math.max(#self.chips, slot)
  local editing = i and self.chips[i]
  -- A new chip starts at white: no hue picked, full lightness.
  local start = editing and editing.color or { r = 1, g = 1, b = 1 }
  self.pickerSlot, self.pickerWeight = slot, editing and editing.weight or 1
  ColorPickerFrame:SetupColorPickerAndShow({
    r = start.r,
    g = start.g,
    b = start.b,
    hasOpacity = false,
    swatchFunc = function()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      -- Opening the picker reports the start colour: a new chip appears only once a colour is picked, and a preset
      -- chip keeps its name until the colour changes.
      local unchanged = math.abs(r - start.r) + math.abs(g - start.g) + math.abs(b - start.b) < 0.005
      if not unchanged then
        self:SetChipColor(slot, { r = r, g = g, b = b }, self.pickerWeight)
      end
    end,
  })
  preparePicker(self.frame:GetParent())
  weightPanel = weightPanel or createWeightPanel(ColorPickerFrame)
  weightPanel.view = nil
  weightPanel.slider:Init(self.pickerWeight * 100, MIN_WEIGHT * 100, 100, 18, {
    [MinimalSliderWithSteppersMixin.Label.Right] = function(value)
      return ("%d%%"):format(value + 0.5)
    end,
  })
  weightPanel.view = self
  -- A weight only matters next to another chip.
  weightPanel:SetShown(chipCount > 1)
end

-- The weight slider under the colour picker, once it exists (for /iconic shot demo).
function View:WeightSlider()
  return weightPanel and weightPanel.slider
end

-- The weight slider under the colour picker moved: applies to the chip being picked, or to the next one.
function View:SetPickerWeight(weight)
  self.pickerWeight = weight
  if self.chips[self.pickerSlot] then
    self:SetChipWeight(self.pickerSlot, weight)
  end
end

function View:CreateIconButton(parent)
  local view = self
  local button = CreateFrame("Button", nil, parent)
  button.iconicButton = true
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button.selected = button:CreateTexture(nil, "OVERLAY")
  button.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  button.selected:SetBlendMode("ADD")
  button.selected:SetAllPoints()
  button:SetScript("OnClick", function(clicked)
    view:Select(clicked.row)
  end)
  button:SetScript("OnEnter", function(hovered)
    view:ShowTooltip(hovered)
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

function View:InitRow(frame, elementData)
  frame.buttons = frame.buttons or {}
  local index = self.data.index
  for i, row in ipairs(elementData.rows) do
    local button = frame.buttons[i]
    if not button then
      button = self:CreateIconButton(frame)
      frame.buttons[i] = button
    end
    local size = self.iconSize
    button:SetSize(size, size)
    button:SetPoint("TOPLEFT", ROW_INSET + (i - 1) * (size + ICON_GAP), 0)
    button.row = row
    button.icon:SetTexture(index.texture[row])
    button.selected:SetShown(index.key[row] == self.selectedKey)
    button:Show()
  end
  for i = #elementData.rows + 1, #frame.buttons do
    frame.buttons[i]:Hide()
  end
end

-- Tooltip for an icon row, anchored to `owner` (defaults to the hovered button's row).
function View:ShowTooltip(owner, row)
  local index = self.data.index
  row = row or owner.row
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local names, pending = Catalog.Names(index, row)
  if pending then
    ns.AfterNames("tooltip", function()
      if GameTooltip:IsOwned(owner) then
        self:ShowTooltip(owner, row)
      end
    end)
  end
  -- While searching, the words a search word finds are coloured and a line says what found the icon.
  local query = self.search and self.search:GetText() or ""
  local searching = #Search.Normalize(query) >= MIN_QUERY or #self.chips > 0
  local opts = { synonyms = ns.synonyms, chips = self.chips }
  local function shown(name)
    return searching and Search.Highlight(name, query, opts) or name
  end
  GameTooltip:SetText(names[1] and shown(names[1]) or index.file[row] or tostring(index.key[row]), 1, 1, 1)
  for i = 2, math.min(#names, 5) do
    GameTooltip:AddLine(shown(names[i]), 0.8, 0.8, 0.8)
  end
  if index.file[row] and names[1] then
    local file = index.file[row]
    GameTooltip:AddLine(
      searching and Search.Highlight(file, query, { synonyms = ns.synonyms, file = true }) or file,
      0.5,
      0.5,
      0.5
    )
  end
  if searching then
    local parts = {}
    for _, found in ipairs(Search.Explain(index, row, query, opts)) do
      if found.word then
        local word = found.via and ("%s %s %s"):format(found.word, SYNONYM_ARROW, found.via) or found.word
        parts[#parts + 1] = ("%s (%s)"):format(word, L[MATCH_PLACES[found.where]])
      else
        local preset = Search.Preset(found.color)
        parts[#parts + 1] = ("%s %d%%"):format(preset and L[preset.label] or found.color, found.share)
      end
    end
    if #parts > 0 then
      GameTooltip:AddLine(L["Found by: %s"]:format(table.concat(parts, ", ")), 1, 0.82, 0, true)
    end
  end
  if index.id[row] and ns.ShowIconID(ns.db.settings.tooltipPicker) then
    GameTooltip:AddLine(L["Icon ID: %d"]:format(index.id[row]), 0.5, 0.8, 1)
  end
  GameTooltip:Show()
end

-- Icons per row, and sets self.iconSize so that many icons fill the width between the insets.
function View:PerRow()
  local width = (self.scrollBox:GetWidth() or 0) - 2 * ROW_INSET
  if width <= 0 then
    self.iconSize = MIN_ICON_SIZE
    return 11
  end
  local perRow = math.max(1, math.floor((width + ICON_GAP) / (MIN_ICON_SIZE + ICON_GAP)))
  self.iconSize = (width + ICON_GAP) / perRow - ICON_GAP
  return perRow
end

function View:Fill(textures, extras)
  self.data = ns.LoadData() or self.data
  self.textures = textures
  self.rows, self.data, self.positions = Catalog.Rows(self.data, textures)
  self.usable = computeUsable(self.data, extras)
  self.counts = Catalog.Counts(self.data.index, self.rows)
  self.vocabulary = nil
  self:Refresh()
end

-- Loads the textures to show; `extras` are the provider's spellbook/equipment icons (count as usable).
-- Before the icon data is loaded, the grid fills a frame later, so the frame shows before the load pause.
function View:SetTextures(textures, extras)
  self.fillTicket = (self.fillTicket or 0) + 1
  if ns.data ~= nil then
    self:Fill(textures, extras)
    return
  end
  local ticket = self.fillTicket
  self.empty:SetText(L["Loading icons…"])
  self.empty:Show()
  C_Timer.After(0, function()
    if self.fillTicket == ticket then
      self:Fill(textures, extras)
      self:SetSelected(self.selectedTexture)
      self:ScrollToSelected()
    end
  end)
end

local function formatCount(count)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(count) or tostring(count)
end

function View:UpdateFooter(shown, total)
  self.footer.count:SetText(L["%s of %s icons"]:format(formatCount(shown), formatCount(total)))
end

-- Icons to suggest while the search is empty: textures, or { query = text } for that text's results.
-- Takes effect with the next SetTextures or Refresh.
function View:SetSuggestions(entries)
  self.suggestions = entries
end

-- Position of a row's texture in the list given to SetTextures.
function View:PositionOf(row)
  return self.positions and self.positions[row]
end

function View:SetSelected(texture)
  self.selectedTexture = texture
  self.selectedKey = texture and (Catalog.ResolveId(self.data, texture) or texture) or nil
  self.scrollBox:ForEachFrame(function(frame)
    for _, button in ipairs(frame.buttons or {}) do
      if button:IsShown() then
        button.selected:SetShown(self.data.index.key[button.row] == self.selectedKey)
      end
    end
  end)
  self:NotifySelectedState()
end

-- Where the selected icon stands: "visible" in the grid, "hidden" by the search, colour chips, filters or a
-- collapsed section, or "absent" from the picker's icons.
function View:SelectedState()
  local row = self.selectedKey and self.data and self.data.index.byKey[self.selectedKey]
  if not (row and self.positions and self.positions[row]) then
    return "absent"
  end
  return self.visibleRows and self.visibleRows[row] and "visible" or "hidden"
end

function View:NotifySelectedState()
  if self.onSelectedState then
    self.onSelectedState(self:SelectedState())
  end
end

-- Scrolls to the selected icon; when it is hidden, first clears the search, colour chips and filters, or opens
-- its collapsed section.
function View:RevealSelected()
  if self:SelectedState() == "hidden" then
    local row = self.data.index.byKey[self.selectedKey]
    if not self.sectionOf[row] then
      self.search:SetText("")
      -- Drops the refresh the text change queued, which would scroll back to the top.
      self.pending = (self.pending or 0) + 1
      self.chips = {}
      self:UpdateChips()
      self.filters = {}
      self:Refresh()
    end
    local key = self.sectionOf[row]
    if key and not self.visibleRows[row] then
      self:CollapsedSet()[key] = nil
      self:Refresh(true)
    end
  end
  self:ScrollToSelected(true)
end

function View:Select(row)
  local position = self:PositionOf(row)
  local texture = position and self.textures[position] or self.data.index.texture[row]
  self:SetSelected(texture)
  if self.onSelect then
    self.onSelect(texture, position)
  end
end

-- Scrolls to the selected icon's first occurrence; with `cycle`, to the one after the last scrolled-to, wrapping.
function View:ScrollToSelected(cycle)
  local key = self.selectedKey
  if not key or not self.provider then
    return
  end
  local matches, last = {}, nil
  for _, elementData in self.provider:EnumerateEntireRange() do
    for _, row in ipairs(elementData.rows or {}) do
      if self.data.index.key[row] == key then
        matches[#matches + 1] = elementData
        if elementData == self.scrollTarget then
          last = #matches
        end
        break
      end
    end
  end
  local target = matches[cycle and last and last % #matches + 1 or 1]
  self.scrollTarget = target
  if target then
    self.scrollBox:ScrollToElementData(target, ScrollBoxConstants.AlignCenter)
  end
end

function View:QueueRefresh()
  self.pending = (self.pending or 0) + 1
  local ticket = self.pending
  C_Timer.After(SEARCH_DELAY, function()
    if self.pending == ticket then
      self:Refresh()
    end
  end)
end

-- Counts per filter value under the current search and the other groups' filters; cached until Refresh.
function View:FacetCounts()
  if not self.rows then
    return {}
  end
  if self.facets then
    return self.facets
  end
  local index, query = self.data.index, self.search:GetText() or ""
  local rows = self.rows
  if #Search.Normalize(query) >= MIN_QUERY or #self.chips > 0 then
    rows = Search.Find(index, rows, query, { synonyms = ns.synonyms, chips = self.chips })
  end
  self.facets = Catalog.FacetCounts(index, rows, self.filters, self.usable)
  return self.facets
end

-- Rebuilds the grid; `keepScroll` keeps the scroll position (layout changes), otherwise it starts at the top.
function View:Refresh(keepScroll)
  self.facets = nil
  if not self.rows then
    return
  end
  local data, index = self.data, self.data.index
  local query = self.search:GetText() or ""
  local hasText = #Search.Normalize(query) >= MIN_QUERY
  local hasQuery = hasText or #self.chips > 0
  local groupBy = self:GroupBy()

  local rows = Catalog.Filter(index, self.rows, self.filters, self.usable)
  local loose = false
  if hasQuery then
    rows, loose = Search.Find(index, rows, query, {
      synonyms = ns.synonyms,
      usable = self.usable,
      vocabulary = function()
        self.vocabulary = self.vocabulary or Search.Vocabulary(index.text)
        return self.vocabulary
      end,
      chips = self.chips,
    })
  end

  self:UpdateFooter(#rows, #self.rows)
  local perRow = self:PerRow()
  local settings = ns.db and ns.db.settings
  local recent = not hasQuery
    and settings
    and settings.showRecent
    and Catalog.RecentRows(data, rows, ns.db.recent, self.filters, self.usable)
  local suggested = not hasQuery
    and settings
    and settings.showSuggested
    and Catalog.SuggestedRows(
      data,
      rows,
      self.suggestions,
      self.filters,
      self.usable,
      MAX_SUGGESTED_ROWS * perRow,
      ns.synonyms
    )
  local sections = Catalog.Sections(data, rows, groupBy, recent or nil, suggested or nil)
  if loose and sections[1] and not sections[1].title then
    sections[1].title = L["Close matches"]
  end

  local elements, collapsed = {}, self:CollapsedSet()
  self.sectionKeys, self.sectionOf, self.visibleRows = {}, {}, {}
  for sectionIndex, section in ipairs(sections) do
    local key = (section.suggested and "suggested")
      or (section.recent and "recent")
      or tostring(section.value or section.title or "")
    local isCollapsed = section.title and collapsed[key] or false
    for _, row in ipairs(section.rows) do
      self.sectionOf[row] = key
      if not isCollapsed then
        self.visibleRows[row] = true
      end
    end
    if section.title then
      self.sectionKeys[#self.sectionKeys + 1] = key
      elements[#elements + 1] = {
        header = section.title,
        count = #section.rows,
        gap = sectionIndex > 1,
        key = key,
        collapsed = isCollapsed,
      }
    end
    for i = 1, isCollapsed and 0 or #section.rows, perRow do
      local chunk = {}
      for j = i, math.min(i + perRow - 1, #section.rows) do
        chunk[#chunk + 1] = section.rows[j]
      end
      elements[#elements + 1] = { rows = chunk }
    end
  end

  self.provider = CreateDataProvider(elements)
  self.scrollBox:SetDataProvider(
    self.provider,
    keepScroll and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition
  )

  local empty = #rows == 0
  self.empty:SetShown(empty)
  if empty then
    if hasText then
      self.empty:SetText(L['No icons match "%s".']:format(query))
    elseif hasQuery then
      self.empty:SetText(L["No icons have these colours."])
    else
      self.empty:SetText(L["No icons match these filters."])
    end
  end
  self.filter:ValidateResetState()
  self:NotifySelectedState()
end

local BUTTON_TEXT_INSET, BUTTON_ARROW_SPACE = 10, 30

-- Filter-style buttons center their text; start it near the left edge and size the button to it.
local function leftAlignText(button)
  button.Text:ClearAllPoints()
  button.Text:SetPoint("LEFT", BUTTON_TEXT_INSET, 0)
  button.resizeToText = true
  button.resizeToTextPadding = BUTTON_TEXT_INSET + BUTTON_ARROW_SPACE
  button:UpdateText()
end

-- Fills the search box's suggestion list with filter values matching the typed words.
function View:UpdateSuggestions()
  local box = self.search
  if not (self.data and box:HasFocus() and box:IsCurrentTextValidForSearch()) then
    box:HideSearchPreview()
    return
  end
  local buttons = box:GetButtons()
  -- At least SUGGEST_WIDTH wide, so long labels such as item categories fit beside a narrow search box.
  box.searchPreviewContainer:SetWidth(math.max(box:GetWidth(), SUGGEST_WIDTH))
  -- Colours that already have a chip count as active, like ticked filters.
  local active = setmetatable({ color = {} }, { __index = self.filters })
  for _, chip in ipairs(self.chips) do
    if chip.preset then
      active.color[chip.preset] = true
    end
  end
  local list = Catalog.Suggest(self.data, box:GetText(), self.counts, active, #buttons)
  for i, button in ipairs(buttons) do
    local suggestion = list[i]
    button.suggestion = suggestion
    if suggestion then
      button.Name:SetText(
        ("|cff9d9d9d%s:|r %s |cff9d9d9d%d|r"):format(suggestion.group, suggestion.label, suggestion.count)
      )
      self:SetSuggestionIcon(button.Icon, suggestion)
      button:Show()
    else
      button:Hide()
    end
  end
  if #list == 0 then
    box:HideSearchPreview()
  else
    box:UpdateSearchPreview(true, true, #list)
    -- Nothing highlighted: Enter searches; arrow keys pick a suggestion first.
    box.selectedIndex = 0
    for _, button in ipairs(buttons) do
      button.selectedTexture:Hide()
    end
  end
end

-- Class icon, profession icon or colour swatch; other suggestions show none.
function View:SetSuggestionIcon(texture, suggestion)
  texture:SetTexCoord(0, 1, 0, 1)
  texture:SetVertexColor(1, 1, 1)
  texture:SetSize(SUGGESTION_ICON_SIZE, SUGGESTION_ICON_SIZE)
  if suggestion.dim == "class" then
    local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(suggestion.value)
    if info and info.classFile then
      texture:SetAtlas(GetClassAtlas(info.classFile))
      texture:Show()
      return
    end
  elseif suggestion.dim == "profession" and self.data.professionIcons[suggestion.value] then
    texture:SetTexture(self.data.professionIcons[suggestion.value])
    texture:Show()
    return
  elseif suggestion.dim == "color" and Search.Preset(suggestion.value) then
    -- Smaller than the icon slot, centred in it.
    local c = Search.HexColor(Search.Preset(suggestion.value).hex)
    texture:SetTexture(SWATCH)
    texture:SetSize(SWATCH_ROW_SIZE, SWATCH_ROW_SIZE)
    texture:SetVertexColor(c.r, c.g, c.b)
    texture:Show()
    return
  end
  texture:SetTexture(nil)
  texture:Show()
end

-- Turns a suggestion into an active filter and drops its word from the search text.
function View:ApplySuggestion(suggestion)
  if not suggestion then
    return
  end
  if suggestion.dim == "color" then
    self:AddPresetChip(suggestion.value)
  else
    selectedSet(self.filters, suggestion.dim)[suggestion.value] = true
  end
  local text = self.search:GetText()
  for _, word in ipairs(suggestion.words) do
    text = Catalog.RemoveWord(text, word)
  end
  self.search:SetText(text)
  self.search:Close()
  self:Refresh()
end

-- Creates the picker view inside `parent`. opts.onSelect(texture) is called when an icon is clicked,
-- opts.onSelectedState(state) whenever SelectedState may have changed.
function ns.CreateView(parent, opts)
  local self = setmetatable({
    filters = {},
    chips = {},
    onSelect = opts and opts.onSelect,
    onSelectedState = opts and opts.onSelectedState,
  }, View)
  local frame = CreateFrame("Frame", nil, parent)
  self.frame = frame

  -- Toolbar band holding search, filter and group-by, set off from the grid below.
  local toolbar = CreateFrame("Frame", nil, frame)
  toolbar:SetPoint("TOPLEFT", 2, -4)
  toolbar:SetPoint("TOPRIGHT", -2, -4)
  toolbar:SetHeight(TOOLBAR_HEIGHT)
  toolbar.bg = toolbar:CreateTexture(nil, "BACKGROUND")
  toolbar.bg:SetAllPoints()
  toolbar.bg:SetColorTexture(0, 0, 0, 0.45)
  toolbar.line = toolbar:CreateTexture(nil, "BORDER")
  toolbar.line:SetPoint("BOTTOMLEFT")
  toolbar.line:SetPoint("BOTTOMRIGHT")
  toolbar.line:SetHeight(1)
  toolbar.line:SetColorTexture(1, 1, 1, 0.12)
  self.toolbar = toolbar

  -- Right to left: expand all, collapse all, group by, filter, colour chips; the search box takes the rest.
  self.expandAll = self:CreateSignButton(toolbar, true, L["Expand all sections"], function()
    self:SetAllCollapsed(false)
  end)
  self.expandAll:SetPoint("RIGHT", -10, 0)
  self.collapseAll = self:CreateSignButton(toolbar, false, L["Collapse all sections"], function()
    self:SetAllCollapsed(true)
  end)
  self.collapseAll:SetPoint("RIGHT", self.expandAll, "LEFT", -4, 0)

  self.group = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1FilterDropdownTemplate")
  leftAlignText(self.group)
  self.group:SetPoint("RIGHT", self.collapseAll, "LEFT", -10, 0)

  self.filter = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1FilterDropdownTemplate")
  leftAlignText(self.filter)
  if self.filter.ResetButton then
    self.filter.ResetButton:SetSize(RESET_SIZE, RESET_SIZE)
  end
  self.filter:SetPoint("RIGHT", self.group, "LEFT", -8, 0)

  self.colorBar = self:CreateColorBar(toolbar)
  self.colorBar:SetPoint("RIGHT", self.filter, "LEFT", -8, 0)
  self:UpdateChips()

  self.search = CreateFrame("EditBox", nil, toolbar, "IconicSearchBoxTemplate")
  self.search:ClearAllPoints()
  self.search:SetHeight(self.filter:GetHeight())
  self.search:SetPoint("LEFT", opts and opts.searchLeft or 16, 0)
  self.search:SetPoint("RIGHT", self.colorBar, "LEFT", -10, 0)
  self.search:SetAutoFocus(false)
  self.search.Instructions:SetText(L["Search…"])
  self.search:HookScript("OnTextChanged", function()
    self:QueueRefresh()
    self:UpdateSuggestions()
  end)
  self.search:HookScript("OnEditFocusGained", function()
    self:UpdateSuggestions()
  end)
  for _, button in ipairs(self.search:GetButtons()) do
    button:SetScript("OnClick", function(clicked)
      self:ApplySuggestion(clicked.suggestion)
    end)
  end
  -- Enter takes a suggestion only when one was picked with the arrow keys; otherwise it just searches.
  self.search:SetScript("OnEnterPressed", function(box)
    local picked = box.selectedIndex and box:GetButtons()[box.selectedIndex]
    if picked and picked:IsShown() and picked.suggestion then
      picked:Click()
      return
    end
    box:Close()
    self:Refresh()
  end)
  -- Line the suggestion list up with the visible edge of the search box.
  local preview = self.search.searchPreviewContainer
  preview:ClearAllPoints()
  preview:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", -5, -1)

  self.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  -- Full width so section bands reach the frame edge; rows are inset instead.
  -- The grid scrolls up to the toolbar line and down to the frame edge; padding keeps the resting gaps.
  self.scrollBox:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -2, -1)
  self.scrollBox:SetPoint("BOTTOMRIGHT", -28, -2)

  -- Icon count and branding, placed by the picker adapter or the browser.
  local footer = CreateFrame("Frame", nil, frame)
  footer:SetHeight(FOOTER_HEIGHT)
  footer.count = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer.count:SetPoint("LEFT")
  footer.brand = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer.brand:SetPoint("RIGHT")
  footer.brand:SetText(L["Iconic"])
  self.footer = footer
  self.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  self.scrollBar:SetPoint("TOPLEFT", self.scrollBox, "TOPRIGHT", 8, -GRID_PAD_TOP)
  self.scrollBar:SetPoint("BOTTOMLEFT", self.scrollBox, "BOTTOMRIGHT", 8, GRID_PAD_BOTTOM)

  local listView = CreateScrollBoxListLinearView(GRID_PAD_TOP, GRID_PAD_BOTTOM)
  listView:SetElementExtentCalculator(function(_, elementData)
    if elementData.header then
      return HEADER_HEIGHT + (elementData.gap and SECTION_GAP or 0)
    end
    return (self.iconSize or MIN_ICON_SIZE) + ICON_GAP
  end)
  listView:SetElementFactory(function(factory, elementData)
    if elementData.header then
      factory("Button", function(row, data)
        self:InitHeader(row, data)
      end)
    else
      factory("Frame", function(row, data)
        self:InitRow(row, data)
      end)
    end
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(self.scrollBox, self.scrollBar, listView)

  self.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  self.empty:SetPoint("CENTER", self.scrollBox)
  self.empty:SetWidth(320)
  self.empty:Hide()

  local lastWidth
  self.scrollBox:HookScript("OnSizeChanged", function(_, width)
    if lastWidth and math.abs(width - lastWidth) < 1 then
      return
    end
    lastWidth = width
    self:Refresh(true)
  end)

  self:SetupFilterMenu()
  self:SetupGroupMenu()
  return self
end
