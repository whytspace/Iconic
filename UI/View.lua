local ADDON_NAME, ns = ...

local L = ns.L
local Catalog, Search = ns.Catalog, ns.Search

local ICON_SIZE, ICON_GAP, HEADER_HEIGHT, SECTION_GAP, TOOLBAR_HEIGHT, ROW_INSET = 36, 4, 32, 8, 40, 8
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

-- Appends the number of icons a filter value matches.
local function withCount(label, count)
  return label .. " |cff9d9d9d" .. (count or 0) .. "|r"
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
    local counts = view.counts or {}
    local function count(dim, value)
      return counts[dim] and counts[dim][value]
    end
    root:CreateCheckbox(L["Only my spells & items"], function()
      return view.filters.usable or false
    end, function()
      view.filters.usable = not view.filters.usable or nil
      view:Refresh()
      return MenuResponse.Refresh
    end)
    root:CreateDivider()

    local source = root:CreateButton(L["Source"])
    for _, entry in ipairs(Catalog.SOURCES) do
      local label = withCount(L[entry.label], count("source", entry.key))
      source:CreateCheckbox(label, isSet("source", entry.key), toggle("source", entry.key))
    end
    if not data then
      return
    end

    local class = root:CreateButton(L["Class"])
    for _, classId in ipairs(sortedKeys(data.classes)) do
      local label = withCount(classLabel(classId, data.classes[classId]), count("class", classId))
      class:CreateCheckbox(label, isSet("class", classId), toggle("class", classId))
    end

    local category = root:CreateButton(L["Item category"])
    for _, top in ipairs(sortedKeys(data.itemClasses, true)) do
      local keys = subcategories(data.itemClasses, top)
      local name = withCount(data.itemClasses[top], count("category", top))
      if #keys <= 1 then
        -- A lone subcategory adds nothing; filter by it straight from the category entry.
        local key = keys[1] or top
        category:CreateCheckbox(name, isSet("category", key), toggle("category", key))
      else
        local sub = category:CreateButton(name)
        sub:CreateButton(L["All"], toggleAll("category", keys))
        sub:CreateDivider()
        for _, key in ipairs(keys) do
          local label = withCount(data.itemClasses[key], count("category", key))
          sub:CreateCheckbox(label, isSet("category", key), toggle("category", key))
        end
      end
    end

    local profession = root:CreateButton(L["Profession"])
    for _, prof in ipairs(sortedKeys(data.professions)) do
      local label = iconLabel(data.professionIcons and data.professionIcons[prof], data.professions[prof])
      label = withCount(label, count("profession", prof))
      profession:CreateCheckbox(label, isSet("profession", prof), toggle("profession", prof))
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

function View:SetupGroupMenu()
  local view = self
  -- Before SetupMenu, which renders the initial selection text.
  self.group:SetSelectionTranslator(function(selection)
    return L["Group: %s"]:format(selection.text)
  end)
  self.group:SetupMenu(function(_, root)
    for _, entry in ipairs(Catalog.GROUPS) do
      root:CreateRadio(L[entry.label], function()
        return (ns.db and ns.db.groupBy or "none") == entry.key
      end, function()
        if ns.db then
          ns.db.groupBy = entry.key
        end
        view:Refresh()
      end, entry.key)
    end
  end)
end

-- Section header: a band fading out to the right, with the title and icon count.
function View:InitHeader(frame, elementData)
  if not frame.label then
    frame.band = frame:CreateTexture(nil, "BACKGROUND")
    frame.band:SetPoint("BOTTOMLEFT", 0, 4)
    frame.band:SetPoint("BOTTOMRIGHT", 0, 4)
    frame.band:SetHeight(HEADER_HEIGHT - 6)
    frame.band:SetColorTexture(1, 1, 1, 1)
    frame.band:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.12), CreateColor(1, 1, 1, 0.02))
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    frame.label:SetPoint("LEFT", frame.band, "LEFT", ROW_INSET + 8, 0)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.count:SetPoint("BOTTOMLEFT", frame.label, "BOTTOMRIGHT", 8, 1)
  end
  frame.label:SetText(elementData.header)
  frame.count:SetText(elementData.count or "")
end

function View:CreateIconButton(parent)
  local view = self
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(ICON_SIZE, ICON_SIZE)
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
      button:SetPoint("TOPLEFT", ROW_INSET + (i - 1) * (ICON_SIZE + ICON_GAP), 0)
      frame.buttons[i] = button
    end
    button.row = row
    button.icon:SetTexture(index.texture[row])
    button.selected:SetShown(index.key[row] == self.selectedKey)
    button:Show()
  end
  for i = #elementData.rows + 1, #frame.buttons do
    frame.buttons[i]:Hide()
  end
end

function View:ShowTooltip(button)
  local index, row = self.data.index, button.row
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
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

function View:PerRow()
  local width = self.scrollBox:GetWidth()
  if not width or width <= 0 then
    return 11
  end
  return math.max(1, math.floor((width - ROW_INSET + ICON_GAP) / (ICON_SIZE + ICON_GAP)))
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

-- Rebuilds the grid; `keepScroll` keeps the scroll position (layout changes), otherwise it starts at the top.
function View:Refresh(keepScroll)
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
  local elements = {}
  for sectionIndex, section in ipairs(sections) do
    if section.title then
      elements[#elements + 1] = { header = section.title, count = #section.rows, gap = sectionIndex > 1 }
    end
    for i = 1, #section.rows, perRow do
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

  self.group = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate")
  self.group:SetWidth(150)
  self.group:SetPoint("RIGHT", -10, 0)

  self.filter = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1FilterDropdownTemplate")
  self.filter:SetWidth(110)
  self.filter:SetPoint("RIGHT", self.group, "LEFT", -8, 0)

  self.search = CreateFrame("EditBox", nil, toolbar, "SearchBoxTemplate")
  self.search:SetHeight(22)
  self.search:SetPoint("LEFT", 16, 0)
  self.search:SetPoint("RIGHT", self.filter, "LEFT", -12, 0)
  self.search:SetAutoFocus(false)
  self.search.Instructions:SetText(L["Search names, spells, items…"])
  self.search:HookScript("OnTextChanged", function()
    self:QueueRefresh()
  end)
  self.search:HookScript("OnEnterPressed", function(box)
    box:ClearFocus()
    self:Refresh()
  end)

  self.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  -- Full width so section bands reach the frame edge; rows are inset instead.
  self.scrollBox:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -2, -8)
  self.scrollBox:SetPoint("BOTTOMRIGHT", -16, 2)
  self.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  self.scrollBar:SetPoint("TOPLEFT", self.scrollBox, "TOPRIGHT", 4, 0)
  self.scrollBar:SetPoint("BOTTOMLEFT", self.scrollBox, "BOTTOMRIGHT", 4, 0)

  local listView = CreateScrollBoxListLinearView()
  listView:SetElementExtentCalculator(function(_, elementData)
    if elementData.header then
      return HEADER_HEIGHT + (elementData.gap and SECTION_GAP or 0)
    end
    return ICON_SIZE + ICON_GAP
  end)
  listView:SetElementFactory(function(factory, elementData)
    if elementData.header then
      factory("Frame", function(row, data)
        self:InitHeader(row, data)
      end)
    else
      factory("Button", function(row, data)
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
