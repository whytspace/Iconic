local ADDON_NAME, ns = ...

-- Search hints: filter values matching the typed words, listed under the search box.
local Catalog, Color, View = ns.Catalog, ns.Color, ns.View

local HINT_WIDTH = 320
local SWATCH_ROW_SIZE, HINT_ICON_SIZE = 12, 19

-- Fills the search box's hint list with filter values matching the typed words.
function View:UpdateHints()
  local box = self.search
  if not (self.data and box:HasFocus() and box:IsCurrentTextValidForSearch()) then
    box:HideSearchPreview()
    return
  end
  local buttons = box:GetButtons()
  -- At least HINT_WIDTH wide, so long labels such as item categories fit beside a narrow search box.
  box.searchPreviewContainer:SetWidth(math.max(box:GetWidth(), HINT_WIDTH))
  -- Colors that already have a chip count as active, like ticked filters.
  local active = setmetatable({ color = {} }, { __index = self.filters })
  for _, chip in ipairs(self.chips) do
    if chip.preset then
      active.color[chip.preset] = true
    end
  end
  local list = Catalog.Hints(self.data, box:GetText(), self.counts, active, #buttons)
  for i, button in ipairs(buttons) do
    local hint = list[i]
    button.hint = hint
    if hint then
      button.Name:SetText(("|cff9d9d9d%s:|r %s |cff9d9d9d%d|r"):format(hint.group, hint.label, hint.count))
      self:SetHintIcon(button.Icon, hint)
      button:Show()
    else
      button:Hide()
    end
  end
  if #list == 0 then
    box:HideSearchPreview()
  else
    box:UpdateSearchPreview(true, true, #list)
    -- Nothing highlighted: Enter searches; arrow keys pick a hint first.
    box.selectedIndex = 0
    for _, button in ipairs(buttons) do
      button.selectedTexture:Hide()
    end
  end
end

-- Class icon, profession icon or color swatch; other hints show none.
function View:SetHintIcon(texture, hint)
  texture:SetTexCoord(0, 1, 0, 1)
  texture:SetVertexColor(1, 1, 1)
  texture:SetSize(HINT_ICON_SIZE, HINT_ICON_SIZE)
  local classFile = hint.dim == "class" and View.ClassFile(hint.value)
  local preset = hint.dim == "color" and Color.Preset(hint.value)
  if classFile then
    texture:SetAtlas(GetClassAtlas(classFile))
  elseif hint.dim == "profession" and self.data.professionIcons[hint.value] then
    texture:SetTexture(self.data.professionIcons[hint.value])
  elseif preset then
    -- Smaller than the icon slot, centered in it.
    local c = Color.FromHex(preset.hex)
    texture:SetTexture(View.SWATCH)
    texture:SetSize(SWATCH_ROW_SIZE, SWATCH_ROW_SIZE)
    texture:SetVertexColor(c.r, c.g, c.b)
  else
    texture:SetTexture(nil)
  end
  texture:Show()
end

-- Turns a hint into an active filter and drops its word from the search text.
function View:ApplyHint(hint)
  if not hint then
    return
  end
  if hint.dim == "color" then
    self:AddPresetChip(hint.value)
  else
    self:FilterSet(hint.dim)[hint.value] = true
  end
  local text = self.search:GetText()
  for _, word in ipairs(hint.words) do
    text = Catalog.RemoveWord(text, word)
  end
  self.search:SetText(text)
  self.search:Close()
  self:Refresh()
end
