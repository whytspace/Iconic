local ADDON_NAME, ns = ...

local L = ns.L
local Catalog, Search = ns.Catalog, ns.Search

-- Icons grow from MIN_ICON_SIZE to fill the row; HEADER_GAP separates a header band from its icons.
local MIN_ICON_SIZE, ICON_GAP, ROW_INSET = 34, 4, 8
local BAND_HEIGHT, HEADER_GAP, SECTION_GAP, TOOLBAR_HEIGHT = 26, 8, 8, 40
local HEADER_HEIGHT = BAND_HEIGHT + HEADER_GAP + 2
local SEARCH_DELAY = 0.2
local MIN_QUERY = 2
local MAX_SUGGESTED_ROWS = 3
local FOOTER_HEIGHT = 16
local GRID_PAD_TOP, GRID_PAD_BOTTOM = 7, 6

local View = {}
View.__index = View
ns.View = View

-- Shaded gray sphere (scripts/build_swatch.py), tinted per color.
View.SWATCH = "Interface\\AddOns\\Iconic\\Assets\\swatch"
-- Size of the red X on color chips and on the filter button (Blizzard's is 23).
View.RESET_SIZE = 20

-- The saved group-by key; ActiveGroupBy is the one in effect.
function View.SavedGroupBy()
  return ns.db and ns.db.groupBy or "none"
end

-- Class file name ("HUNTER") of a class ID, or nil.
function View.ClassFile(classId)
  local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classId)
  return info and info.classFile
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
    local id = Catalog.ResolveId(texture)
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
  for slot = 1, ns.EQUIPPED_SLOTS do
    local texture = GetInventoryItemTexture("player", slot)
    if texture then
      add(texture)
    end
  end
  return set
end

-- The selected values of one filter group, created when missing.
function View:FilterSet(dim)
  self.filters[dim] = self.filters[dim] or {}
  return self.filters[dim]
end

-- The search text, whether it is long enough to search, and whether it or color chips make a query.
function View:Query()
  local text = self.search and self.search:GetText() or ""
  local hasText = #Search.Normalize(text) >= MIN_QUERY
  return text, hasText, hasText or #self.chips > 0
end

-- Search.Find options for the current synonyms and color chips.
function View:SearchOptions()
  return { synonyms = ns.synonyms, chips = self.chips }
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

-- Grouping in effect: grouping by color pauses while color chips rank the icons.
function View:ActiveGroupBy()
  local groupBy = View.SavedGroupBy()
  if groupBy == "color" and #self.chips > 0 then
    return "none"
  end
  return groupBy
end

-- Collapse state lives per group-by, keyed by section value.
function View:CollapsedSet()
  local groupBy = self:ActiveGroupBy()
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

-- Icons per row and their size, so that many icons fill the width between the insets.
function View:RowLayout()
  local width = (self.scrollBox:GetWidth() or 0) - 2 * ROW_INSET
  if width <= 0 then
    return 11, MIN_ICON_SIZE
  end
  local perRow = math.max(1, math.floor((width + ICON_GAP) / (MIN_ICON_SIZE + ICON_GAP)))
  return perRow, (width + ICON_GAP) / perRow - ICON_GAP
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
  self.selectedKey = texture and (Catalog.ResolveId(texture) or texture) or nil
  self.scrollBox:ForEachFrame(function(frame)
    for _, button in ipairs(frame.buttons or {}) do
      if button:IsShown() then
        button.selected:SetShown(self.data.index.key[button.row] == self.selectedKey)
      end
    end
  end)
  self:NotifySelectedState()
end

-- Where the selected icon stands: "visible" in the grid, "hidden" by the search, color chips, filters or a
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

-- Scrolls to the selected icon; when it is hidden, first clears the search, color chips and filters, or opens
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
  local index, rows = self.data.index, self.rows
  local query, _, hasQuery = self:Query()
  if hasQuery then
    rows = Search.Find(index, rows, query, self:SearchOptions())
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
  local query, hasText, hasQuery = self:Query()
  local groupBy = self:ActiveGroupBy()

  local rows = Catalog.Filter(index, self.rows, self.filters, self.usable)
  local loose = false
  if hasQuery then
    local opts = self:SearchOptions()
    opts.usable = self.usable
    opts.vocabulary = function()
      self.vocabulary = self.vocabulary or Search.Vocabulary(index.text)
      return self.vocabulary
    end
    rows, loose = Search.Find(index, rows, query, opts)
  end

  self:UpdateFooter(#rows, #self.rows)
  local perRow
  perRow, self.iconSize = self:RowLayout()
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
      self.empty:SetText(L["No icons have these colors."])
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

-- Creates the picker view inside `parent`. opts.onSelect(texture) is called when an icon is clicked,
-- opts.onSelectedState(state) whenever SelectedState may have changed.
function View.Create(parent, opts)
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

  -- Right to left: expand all, collapse all, group by, filter, color chips; the search box takes the rest.
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
    self.filter.ResetButton:SetSize(View.RESET_SIZE, View.RESET_SIZE)
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
    self:UpdateHints()
  end)
  self.search:HookScript("OnEditFocusGained", function()
    self:UpdateHints()
  end)
  for _, button in ipairs(self.search:GetButtons()) do
    button:SetScript("OnClick", function(clicked)
      self:ApplyHint(clicked.hint)
    end)
  end
  -- Enter takes a hint only when one was picked with the arrow keys; otherwise it just searches.
  self.search:SetScript("OnEnterPressed", function(box)
    local picked = box.selectedIndex and box:GetButtons()[box.selectedIndex]
    if picked and picked:IsShown() and picked.hint then
      picked:Click()
      return
    end
    box:Close()
    self:Refresh()
  end)
  -- Line the hint list up with the visible edge of the search box.
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
  footer.brand:SetText(L["Iconic"])
  -- Pickers get a settings button after the brand; the browser has one in its title bar.
  if opts and opts.settingsButton then
    footer.settings = ns.SettingsPage.CreateButton(footer)
    footer.settings:SetPoint("RIGHT")
    footer.brand:SetPoint("RIGHT", footer.settings, "LEFT", -4, 0)
  else
    footer.brand:SetPoint("RIGHT")
  end
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
