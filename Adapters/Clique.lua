local ADDON_NAME, ns = ...

local Pickers = ns.Pickers

-- The icon grid on Clique's custom macro page. Clique fills the page after showing it, and creates it the first time
-- its binding window opens.
local spec, hooked

local function page()
  local config = Clique and Clique.GetBindingConfig and Clique:GetBindingConfig()
  return config and config.GetEditMacroPage and config:GetEditMacroPage()
end

local overrides = {
  -- The macro box, with its help text above it, moves up into the empty space under the binding summary. Clique's dark
  -- box behind its icon grid grows into the freed room and over its scroll bar's column, and holds Iconic's grid.
  Anchor = function(popup, viewFrame)
    local box, editBox, summary = popup.background, popup.EditBox, popup.bindSummary
    local label = editBox and editBox.Label
    local labelTop, summaryBottom = label and label:GetTop(), summary and summary:GetBottom()
    local boxTop, boxLeft, boxRight = box:GetTop(), box:GetLeft(), box:GetRight()
    local frameBottom, frameLeft, frameRight = popup:GetBottom(), popup:GetLeft(), popup:GetRight()
    local gap = labelTop and summaryBottom and summaryBottom - 10 - labelTop or 0
    if gap > 0 and boxTop and frameBottom then
      local left, right, y = boxLeft - frameLeft, boxRight - frameRight, boxTop - frameBottom + 10 + gap
      editBox:ClearAllPoints()
      editBox:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", left, y)
      editBox:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", right, y)
      local _, _, _, _, bottomY = box:GetPoint(2)
      local summaryRight = summary:GetRight()
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -6)
      box:SetPoint(
        "BOTTOMRIGHT",
        popup,
        "BOTTOMRIGHT",
        summaryRight and summaryRight - frameRight or right,
        (bottomY or 40) - 6
      )
    end
    -- Styled like the macro box above it.
    if editBox and editBox.GetBackdropColor and box.SetBackdropColor then
      box:SetBackdropColor(editBox:GetBackdropColor())
      box:SetBackdropBorderColor(editBox:GetBackdropBorderColor())
    end
    viewFrame:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    -- The icon list reaches 2 below the view, so the bottom margin clears the border.
    viewFrame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 7)
    viewFrame:SetFrameLevel(box:GetFrameLevel() + 5)
  end,
  -- Left of Cancel, centered on the buttons, which Clique places 5 above the page's bottom.
  AnchorFooter = function(popup, footer)
    local cancel = popup.CancelButton
    footer:ClearAllPoints()
    footer:SetPoint("LEFT", popup, "BOTTOMLEFT", 15, 5 + cancel:GetHeight() / 2)
    footer:SetPoint("RIGHT", cancel, "LEFT", -12, 0)
  end,
  -- The same icons Clique lists.
  GetTextures = function()
    local textures = {}
    GetMacroIcons(textures)
    GetMacroItemIcons(textures)
    return textures, {}
  end,
  GetIcon = function()
    local p = page()
    return p and p.draft and p.draft.icon
  end,
  SetIcon = function(_popup, texture)
    local p = page()
    if not p then
      return
    end
    if p.selectedButton then
      p.selectedButton.SelectedTexture:Hide()
    end
    p.selectedButton, p.selectedButtonId = nil, texture
    p:UpdateIcon(texture)
  end,
  HideNative = function(popup)
    local list = popup.iconScrollFrame
    if list then
      list:Hide()
      if list.scrollbar then
        list.scrollbar:Hide()
      end
    end
  end,
  ShowSelectedState = function() end,
  HookRefill = function(_popup, onRefill)
    local config = Clique:GetBindingConfig()
    hooksecurefunc(config, "SwitchToEditMacroPage", onRefill)
  end,
  -- Okay resets the page in its click handler, so the icon is read before.
  HookConfirm = function(popup, onConfirm)
    popup.SaveButton:HookScript("PreClick", onConfirm)
  end,
}

local function attach()
  local p = page()
  if p and p.frame and Pickers.IsEnabled(spec) then
    Pickers.Attach(p.frame, overrides)
  end
end

spec = {
  addon = "Clique",
  integration = { id = "Clique", name = "Clique", addons = { "Clique" } },
  overrides = overrides,
  frames = function()
    local config = Clique and Clique.GetBindingConfig and Clique:GetBindingConfig()
    if config and config.SwitchToEditMacroPage and not hooked then
      hooked = true
      hooksecurefunc(config, "SwitchToEditMacroPage", attach)
    end
    local p = page()
    return p and p.frame and { p.frame } or {}
  end,
}
Pickers.AddAdapter(spec)
