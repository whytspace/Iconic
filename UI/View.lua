local ADDON_NAME, ns = ...

local L = ns.L
local Catalog, Search = ns.Catalog, ns.Search

-- Icons grow from MIN_ICON_SIZE to fill the row; HEADER_GAP separates a header band from its icons.
local MIN_ICON_SIZE, ICON_GAP, ROW_INSET = 34, 4, 8
local BAND_HEIGHT, HEADER_GAP, SECTION_GAP, TOOLBAR_HEIGHT = 26, 8, 8, 40
local HEADER_HEIGHT = BAND_HEIGHT + HEADER_GAP + 2
local SEARCH_DELAY = 0.2
local MIN_QUERY = 2

local View = {}
View.__index = View

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
      for id in spells:gmatch("%d+") do
        if isSpellKnown(tonumber(id)) then
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
local SWATCH_MENU_SIZE, SWATCH_ROW_SIZE, SUGGESTION_ICON_SIZE = 12, 12, 19

local function hexToRGB(hex)
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

-- Inline colour swatch for menu labels.
local function swatch(hex, size)
  local r, g, b = hexToRGB(hex)
  return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(SWATCH, size, size, r, g, b)
end

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

    local colors = {}
    for _, color in ipairs(Search.COLORS) do
      if total("color", color.key) > 0 then
        colors[#colors + 1] = color
      end
    end
    if #colors > 0 then
      local menu = root:CreateButton(L["Color"])
      view.colorMenu = menu
      for _, color in ipairs(colors) do
        local label = swatch(color.hex, SWATCH_MENU_SIZE) .. " " .. L[color.label]
        entry(menu, label, "color", color.key, isSet("color", color.key), toggle("color", color.key))
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

-- Collapse state lives per group-by, keyed by section value.
function View:CollapsedSet()
  local groupBy = ns.db and ns.db.groupBy or "none"
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
  local names = Catalog.Names(index, row)
  GameTooltip:SetText(names[1] or index.file[row] or tostring(index.key[row]), 1, 1, 1)
  for i = 2, math.min(#names, 5) do
    GameTooltip:AddLine(names[i], 0.8, 0.8, 0.8)
  end
  if index.file[row] and names[1] then
    GameTooltip:AddLine(index.file[row], 0.5, 0.5, 0.5)
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

-- Loads the textures to show; `extras` are the provider's spellbook/equipment icons (count as usable).
function View:SetTextures(textures, extras)
  self.data = ns.LoadData() or self.data
  self.textures = textures
  self.rows, self.data, self.positions = Catalog.Rows(self.data, textures)
  self.usable = computeUsable(self.data, extras)
  self.counts = Catalog.Counts(self.data.index, self.rows)
  self.vocabulary = nil
  self:Refresh()
end

-- Position of a row's texture in the list given to SetTextures.
function View:PositionOf(row)
  return self.positions and self.positions[row]
end

function View:SetSelected(texture)
  self.selectedKey = texture and (Catalog.ResolveId(self.data, texture) or texture) or nil
  self.scrollBox:ForEachFrame(function(frame)
    for _, button in ipairs(frame.buttons or {}) do
      if button:IsShown() then
        button.selected:SetShown(self.data.index.key[button.row] == self.selectedKey)
      end
    end
  end)
end

function View:Select(row)
  local position = self:PositionOf(row)
  local texture = position and self.textures[position] or self.data.index.texture[row]
  self:SetSelected(texture)
  if self.onSelect then
    self.onSelect(texture, position)
  end
end

function View:ScrollToSelected()
  local key = self.selectedKey
  if not key or not self.provider then
    return
  end
  local target = self.provider:FindElementDataByPredicate(function(elementData)
    if elementData.rows then
      for _, row in ipairs(elementData.rows) do
        if self.data.index.key[row] == key then
          return true
        end
      end
    end
    return false
  end)
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
  if #Search.Normalize(query) >= MIN_QUERY then
    rows = Search.Find(index, rows, query, { synonyms = ns.synonyms })
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
  local hasQuery = #Search.Normalize(query) >= MIN_QUERY
  local groupBy = ns.db and ns.db.groupBy or "none"

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
    })
  end

  local recent = not hasQuery and ns.db and Catalog.RecentRows(data, rows, ns.db.recent, self.filters, self.usable)
  local sections = Catalog.Sections(data, rows, groupBy, recent or nil)
  if loose and sections[1] and not sections[1].title then
    sections[1].title = L["Close matches"]
  end

  local perRow = self:PerRow()
  local elements, collapsed = {}, self:CollapsedSet()
  self.sectionKeys = {}
  for sectionIndex, section in ipairs(sections) do
    local key = section.recent and "recent" or tostring(section.value or section.title or "")
    local isCollapsed = section.title and collapsed[key] or false
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
    if hasQuery then
      self.empty:SetText(L['No icons match "%s".']:format(query))
    else
      self.empty:SetText(L["No icons match these filters."])
    end
  end
  self.filter:ValidateResetState()
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
  local list = Catalog.Suggest(self.data, box:GetText(), self.counts, self.filters, #buttons)
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
  elseif suggestion.dim == "color" then
    for _, color in ipairs(Search.COLORS) do
      if color.key == suggestion.value then
        -- Smaller than the icon slot, centred in it.
        local r, g, b = hexToRGB(color.hex)
        texture:SetTexture(SWATCH)
        texture:SetSize(SWATCH_ROW_SIZE, SWATCH_ROW_SIZE)
        texture:SetVertexColor(r / 255, g / 255, b / 255)
        texture:Show()
        return
      end
    end
  end
  texture:SetTexture(nil)
  texture:Show()
end

-- Turns a suggestion into an active filter and drops its word from the search text.
function View:ApplySuggestion(suggestion)
  if not suggestion then
    return
  end
  selectedSet(self.filters, suggestion.dim)[suggestion.value] = true
  self.search:SetText(Catalog.RemoveWord(self.search:GetText(), suggestion.word))
  self.search:Close()
  self:Refresh()
end

-- Creates the picker view inside `parent`. opts.onSelect(texture) is called when an icon is clicked.
function ns.CreateView(parent, opts)
  local self = setmetatable({ filters = {}, onSelect = opts and opts.onSelect }, View)
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

  -- Right to left: expand all, collapse all, group by, filter; the search box takes the rest.
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
  self.filter:SetPoint("RIGHT", self.group, "LEFT", -8, 0)

  self.search = CreateFrame("EditBox", nil, toolbar, "IconicSearchBoxTemplate")
  self.search:ClearAllPoints()
  self.search:SetHeight(self.filter:GetHeight())
  self.search:SetPoint("LEFT", 16, 0)
  self.search:SetPoint("RIGHT", self.filter, "LEFT", -10, 0)
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
  preview:SetPoint("TOPRIGHT", self.search, "BOTTOMRIGHT", -5, -1)

  self.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  -- Full width so section bands reach the frame edge; rows are inset instead.
  self.scrollBox:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -2, -8)
  self.scrollBox:SetPoint("BOTTOMRIGHT", -28, 4)
  self.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  self.scrollBar:SetPoint("TOPLEFT", self.scrollBox, "TOPRIGHT", 8, 0)
  self.scrollBar:SetPoint("BOTTOMLEFT", self.scrollBox, "BOTTOMRIGHT", 8, 0)

  local listView = CreateScrollBoxListLinearView()
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
