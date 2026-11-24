local ADDON_NAME, ns = ...

local L = ns.L
local Color, View = ns.Color, ns.View

-- While a color is dragged in the picker, the grid follows at most this often.
local COLOR_REFRESH_INTERVAL = 0.1
-- Hue wheel on the same sphere as View.SWATCH (scripts/build_swatch.py), for the button that adds a color chip.
local COLOR_WHEEL = "Interface\\AddOns\\Iconic\\Assets\\colorwheel"

local MAX_CHIPS, CHIP_SIZE, CHIP_GAP, CHIP_MIN_SWATCH = 3, 22, 8, 8
local MIN_WEIGHT = 0.1

-- A color chip: its color { r, g, b } (0-1), OKLab target, weight (0.1-1) and the preset it came from, if any.
local function newChip(color, weight, preset)
  return { color = color, target = Color.ChipTarget(color.r, color.g, color.b), weight = weight or 1, preset = preset }
end

local function chipLabel(chip)
  local preset = chip.preset and Color.Preset(chip.preset)
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

-- Color chips and the button that adds one, in a bar left of the filter button. Each chip is a color the icons
-- must contain: click changes it in Blizzard's color picker, right-click removes it.
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
    button.swatch:SetTexture(View.SWATCH)
    -- The same red X as the filter button's reset, in the chip's corner.
    local remove = CreateFrame("Button", nil, button)
    -- Level with the filter's X: on the filter's top edge, 3 px in from the swatch's right edge.
    remove:SetSize(View.RESET_SIZE, View.RESET_SIZE)
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
    GameTooltip:SetText(L["Search by color"], 1, 1, 1)
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
      self.chips[i] = newChip(Color.FromHex(Color.Preset(chip.key).hex), chip.weight, chip.key)
    end
  end
  self:UpdateChips()
  self:QueueColorRefresh()
end

-- Sets chip `i` (or a new last chip) to a picked color { r, g, b }, keeping its weight.
function View:SetChipColor(i, color, weight)
  local chips = self.chips
  i = math.min(i, #chips + 1, MAX_CHIPS)
  chips[i] = newChip(color, weight or (chips[i] and chips[i].weight))
  self:UpdateChips()
  self:QueueColorRefresh()
end

-- Sets the weight (MIN_WEIGHT-1) of chip `i`.
function View:SetChipWeight(i, weight)
  local chip = self.chips[i]
  if chip then
    self.chips[i] = newChip(chip.color, math.max(MIN_WEIGHT, math.min(1, weight)), chip.preset)
    self:UpdateChips()
    self:QueueColorRefresh()
  end
end

-- Adds a chip for a color preset unless it is there already or the bar is full.
function View:AddPresetChip(key)
  for _, chip in ipairs(self.chips) do
    if chip.preset == key then
      return
    end
  end
  local preset = Color.Preset(key)
  if preset and #self.chips < MAX_CHIPS then
    self.chips[#self.chips + 1] = newChip(Color.FromHex(preset.hex), 1, key)
    self:UpdateChips()
  end
end

function View:RemoveChip(i)
  table.remove(self.chips, i)
  self:UpdateChips()
  self:QueueColorRefresh()
end

-- Refreshes soon after a color change; unlike QueueRefresh, further changes don't push it back, so the grid
-- keeps up while the color is dragged.
function View:QueueColorRefresh()
  if self.colorRefreshQueued then
    return
  end
  self.colorRefreshQueued = true
  C_Timer.After(COLOR_REFRESH_INTERVAL, function()
    self.colorRefreshQueued = false
    self:Refresh()
  end)
end

-- Blizzard's color picker is shared: while Iconic uses it, its Cancel button is hidden and Okay centered, it sits beside
-- Iconic's window, and a weight slider hangs below it. All is restored when it closes.
local colorPicker, weightPanel

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
  panel.hint:SetText(L["How much this color counts in the color search."])
  panel.slider = CreateFrame("Frame", nil, panel, "MinimalSliderWithSteppersTemplate")
  panel.slider:SetPoint("TOPLEFT", panel.hint, "BOTTOMLEFT", -2, -6)
  panel.slider:SetPoint("RIGHT", -64, 0)
  panel.slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    if panel.view then
      panel.view:SetColorPickerWeight(value / 100)
    end
  end, panel)
  return panel
end

local function prepareColorPicker(anchor)
  local frame = ColorPickerFrame
  if not colorPicker then
    colorPicker = {}
    frame:HookScript("OnHide", function()
      if colorPicker.okay then
        colorPicker.cancel:Show()
        colorPicker.okay:ClearAllPoints()
        for _, point in ipairs(colorPicker.okayPoints) do
          colorPicker.okay:SetPoint(unpack(point))
        end
      end
      if colorPicker.points then
        frame:ClearAllPoints()
        for _, point in ipairs(colorPicker.points) do
          frame:SetPoint(unpack(point))
        end
        frame:SetClampedToScreen(colorPicker.clamped)
        colorPicker.points = nil
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
    colorPicker.cancel, colorPicker.okay, colorPicker.okayPoints = cancel, okay, {}
    for i = 1, okay:GetNumPoints() do
      colorPicker.okayPoints[i] = { okay:GetPoint(i) }
    end
    local _, _, _, _, y = cancel:GetPoint(1)
    cancel:Hide()
    okay:ClearAllPoints()
    okay:SetPoint("BOTTOM", cancel:GetParent(), "BOTTOM", 0, y or 0)
  end
  if not colorPicker.points then
    colorPicker.points, colorPicker.clamped = {}, frame:IsClampedToScreen()
    for i = 1, frame:GetNumPoints() do
      colorPicker.points[i] = { frame:GetPoint(i) }
    end
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -2, -1)
  frame:SetClampedToScreen(true)
end

-- Opens Blizzard's color picker for chip `i`, or for a new chip; the grid follows the color and weight while they
-- change, and closing the picker keeps them.
function View:OpenColorPicker(i)
  if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
  end
  if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
    return
  end
  local slot = i or #self.chips + 1
  -- Counted before the picker opens: it reports its start color at once, which already adds a new chip.
  local chipCount = math.max(#self.chips, slot)
  local editing = i and self.chips[i]
  -- A new chip starts at white: no hue picked, full lightness.
  local start = editing and editing.color or { r = 1, g = 1, b = 1 }
  self.colorPickerSlot, self.colorPickerWeight = slot, editing and editing.weight or 1
  ColorPickerFrame:SetupColorPickerAndShow({
    r = start.r,
    g = start.g,
    b = start.b,
    hasOpacity = false,
    swatchFunc = function()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      -- Opening the picker reports the start color: a new chip appears only once a color is picked, and a preset
      -- chip keeps its name until the color changes.
      local unchanged = math.abs(r - start.r) + math.abs(g - start.g) + math.abs(b - start.b) < 0.005
      if not unchanged then
        self:SetChipColor(slot, { r = r, g = g, b = b }, self.colorPickerWeight)
      end
    end,
  })
  prepareColorPicker(self.frame:GetParent())
  weightPanel = weightPanel or createWeightPanel(ColorPickerFrame)
  weightPanel.view = nil
  weightPanel.slider:Init(self.colorPickerWeight * 100, MIN_WEIGHT * 100, 100, 18, {
    [MinimalSliderWithSteppersMixin.Label.Right] = function(value)
      return ("%d%%"):format(value + 0.5)
    end,
  })
  weightPanel.view = self
  -- A weight only matters next to another chip.
  weightPanel:SetShown(chipCount > 1)
end

-- The weight slider under the color picker, once it exists (for /iconic shot demo).
function View:WeightSlider()
  return weightPanel and weightPanel.slider
end

-- The weight slider under the color picker moved: applies to the chip being picked, or to the next one.
function View:SetColorPickerWeight(weight)
  self.colorPickerWeight = weight
  if self.chips[self.colorPickerSlot] then
    self:SetChipWeight(self.colorPickerSlot, weight)
  end
end
