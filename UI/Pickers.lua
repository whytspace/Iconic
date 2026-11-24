local ADDON_NAME, ns = ...

local Pickers = { attached = {}, pending = {}, ADAPTERS = {} }
ns.Pickers = Pickers

local L = ns.L

-- Adapter for frames built on Blizzard's IconSelectorPopupFrameTemplate. Third-party adapters override
-- any of these functions; each receives the picker frame first.
local TemplateAdapter = {}
Pickers.TemplateAdapter = TemplateAdapter

-- Places the view over the area of Blizzard's icon grid and its filter dropdown.
function TemplateAdapter.Anchor(popup, viewFrame)
  local grid = popup.IconSelector
  viewFrame:SetPoint("TOPLEFT", grid, "TOPLEFT", -10, 36)
  viewFrame:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, 0)
  viewFrame:SetFrameStrata(grid:GetFrameStrata())
  viewFrame:SetFrameLevel(grid:GetFrameLevel() + 5)
end

-- Places the icon count and branding in the button bar, left of Okay.
function TemplateAdapter.AnchorFooter(popup, footer)
  local box = popup.BorderBox
  local okay = box and box.OkayButton
  if not okay then
    footer:Hide()
    return
  end
  -- Above the popup's border art, shown with the view.
  local view = footer:GetParent()
  footer:SetParent(box)
  footer:SetFrameLevel(box:GetFrameLevel() + 10)
  footer:SetShown(view:IsShown())
  view:HookScript("OnShow", function()
    footer:Show()
  end)
  view:HookScript("OnHide", function()
    footer:Hide()
  end)
  footer:ClearAllPoints()
  footer:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 16, 12)
  footer:SetPoint("TOPRIGHT", okay, "TOPLEFT", -12, -1)
end

-- Textures in the popup's own order, and the extra (spellbook/equipment/outfit) ones.
function TemplateAdapter.GetTextures(popup)
  local provider = popup.iconDataProvider
  local textures, extras = {}, {}
  if not provider then
    return textures, extras
  end
  for i = 1, provider:GetNumIcons() do
    textures[i] = provider:GetIconByIndex(i)
  end
  if provider.ShouldShowExtraIcons and provider:ShouldShowExtraIcons() then
    for i, texture in ipairs(provider.extraIcons or {}) do
      extras[i] = texture
    end
  end
  return textures, extras
end

function TemplateAdapter.GetIcon(popup)
  return popup.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
end

-- `position` is the texture's index in the popup's provider, when known.
function TemplateAdapter.SetIcon(popup, texture, position)
  popup.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(texture)
  if popup.IconSelector then
    popup.IconSelector:SetSelectedIndex(position)
  end
  if popup.SetSelectedIconText then
    popup:SetSelectedIconText()
  end
end

-- True while the player drags a spell/item onto the popup; Blizzard then shows its drop area.
function TemplateAdapter.IsDragging(popup)
  local area = popup.BorderBox and popup.BorderBox.IconDragArea
  return area and area:IsShown() or false
end

function TemplateAdapter.HideNative(popup)
  popup.IconSelector:Hide()
  if popup.BorderBox.IconTypeDropdown then
    popup.BorderBox.IconTypeDropdown:Hide()
  end
  if popup.BorderBox.IconSelectionText then
    popup.BorderBox.IconSelectionText:Hide()
  end
end

-- Calls `onChange` whenever the popup re-evaluates what to show (drag state, filter).
function TemplateAdapter.HookStateChanges(popup, onChange)
  if popup.UpdateStateFromCursorType then
    hooksecurefunc(popup, "UpdateStateFromCursorType", onChange)
  end
end

-- Says what a click on the selected icon does, by View:SelectedState: "visible", "hidden" or "absent".
function TemplateAdapter.ShowSelectedState(popup, selectedState)
  local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
  local text = area and area.SelectedIconText
  local description = text and text.SelectedIconDescription
  if not description then
    return
  end
  if selectedState == "visible" then
    description:SetText(ICON_SELECTION_CLICK)
    description:SetFontObject(GameFontHighlightSmall)
  elseif selectedState == "hidden" then
    description:SetText(L["Click to clear the search and view it"])
    description:SetFontObject(GameFontHighlightSmall)
  else
    description:SetText(ICON_SELECTION_NOTINLIST)
    description:SetFontObject(GameFontDisableSmall)
  end
  if text.Layout then
    text:Layout()
  end
end

-- Calls `onClick` when the selected icon is clicked, and `onTextReset` after Blizzard rewrites its text.
function TemplateAdapter.HookSelected(popup, onClick, onTextReset)
  local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
  if area and area.SelectedIconButton then
    area.SelectedIconButton:HookScript("OnClick", onClick)
  end
  if popup.SetSelectedIconText then
    hooksecurefunc(popup, "SetSelectedIconText", onTextReset)
  end
end

-- Icons to suggest: textures, or { query = text } for that text's results. By default the name being entered.
function TemplateAdapter.GetSuggestions(popup)
  local editBox = popup.BorderBox and popup.BorderBox.IconSelectorEditBox
  local name = editBox and editBox:GetText()
  return name and name ~= "" and { { query = name } } or {}
end

-- Calls `onChange` when the suggestions may have changed while the picker is open.
function TemplateAdapter.HookSuggestionChanges(_popup, _onChange) end

function TemplateAdapter.HookConfirm(popup, onConfirm)
  if popup.OkayButton_OnClick then
    hooksecurefunc(popup, "OkayButton_OnClick", onConfirm)
  end
end

local function adapterFor(overrides)
  return setmetatable(overrides or {}, { __index = TemplateAdapter })
end

-- Replaces the icon grid of `popup` with Iconic's view.
function Pickers.Attach(popup, overrides)
  if not popup or Pickers.attached[popup] then
    return Pickers.attached[popup]
  end
  local adapter = adapterFor(overrides)
  local state = { adapter = adapter }
  Pickers.attached[popup] = state

  local function sync()
    if not state.view then
      return
    end
    local dragging = adapter.IsDragging(popup)
    state.view.frame:SetShown(not dragging and popup:IsShown())
    if not dragging then
      adapter.HideNative(popup)
    end
  end

  local function suggestions()
    local ok, entries = pcall(adapter.GetSuggestions, popup)
    return ok and entries or nil
  end

  local function onShow()
    if not state.view then
      state.view = ns.CreateView(popup, {
        settingsButton = true,
        onSelect = function(texture, position)
          adapter.SetIcon(popup, texture, position)
        end,
        onSelectedState = function(selectedState)
          state.selectedState = selectedState
          adapter.ShowSelectedState(popup, selectedState)
        end,
      })
      adapter.Anchor(popup, state.view.frame)
      adapter.AnchorFooter(popup, state.view.footer)
      adapter.HookSelected(popup, function()
        state.view:RevealSelected()
      end, function()
        if state.selectedState then
          adapter.ShowSelectedState(popup, state.selectedState)
        end
      end)
    end
    local textures, extras = adapter.GetTextures(popup)
    state.view:SetSuggestions(suggestions())
    state.view:SetTextures(textures, extras)
    state.view:SetSelected(adapter.GetIcon(popup))
    state.view:ScrollToSelected()
    sync()
  end

  popup:HookScript("OnShow", onShow)
  adapter.HookStateChanges(popup, sync)
  adapter.HookSuggestionChanges(popup, function()
    if state.view and popup:IsShown() then
      state.view:SetSuggestions(suggestions())
      state.view:Refresh(true)
    end
  end)
  adapter.HookConfirm(popup, function()
    ns.AddRecent(adapter.GetIcon(popup))
  end)
  if popup:IsShown() then
    onShow()
  end
  return state
end

-- Blizzard pickers: the frame to look up and, for load-on-demand UIs, the add-on that creates it.
Pickers.BLIZZARD = {
  {
    key = "macro",
    addon = "Blizzard_MacroUI",
    frame = function()
      return MacroPopupFrame
    end,
  },
  {
    key = "gear",
    frame = function()
      return GearManagerPopupFrame
    end,
  },
  {
    key = "guildBank",
    addon = "Blizzard_GuildBankUI",
    frame = function()
      return GuildBankPopupFrame
    end,
  },
  {
    key = "bank",
    frame = function()
      return BankPanel and BankPanel.TabSettingsMenu
    end,
  },
  {
    key = "transmog",
    addon = "Blizzard_Transmog",
    frame = function()
      return TransmogFrame and TransmogFrame.OutfitPopup
    end,
  },
}

-- Attaches every Blizzard picker that exists now; call again after an add-on loads.
function Pickers.AttachBlizzard()
  for _, entry in ipairs(Pickers.BLIZZARD) do
    local ok, popup = pcall(entry.frame)
    if ok and popup and popup.IconSelector then
      Pickers.Attach(popup, Pickers.ADAPTERS[entry.key])
    end
  end
end

-- Registers a picker that may not exist yet: `resolve` returns the frame once it does.
function Pickers.Register(resolve, overrides)
  local popup = type(resolve) == "function" and resolve() or resolve
  if popup then
    return Pickers.Attach(popup, overrides) ~= nil
  end
  table.insert(Pickers.pending, { resolve = resolve, overrides = overrides })
  return false
end

function Pickers.RetryPending()
  for i = #Pickers.pending, 1, -1 do
    local entry = Pickers.pending[i]
    local ok, popup = pcall(entry.resolve)
    if ok and popup then
      table.remove(Pickers.pending, i)
      Pickers.Attach(popup, entry.overrides)
    end
  end
end
