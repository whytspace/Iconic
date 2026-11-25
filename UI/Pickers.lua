local ADDON_NAME, ns = ...

local Pickers = { attached = {}, pending = {} }
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
  else
    -- Classic updates the drag state straight in OnEvent.
    popup:HookScript("OnEvent", function(_, event)
      if event == "CURSOR_CHANGED" then
        onChange()
      end
    end)
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
function TemplateAdapter.HookSelectedIconClick(popup, onClick, onTextReset)
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

-- Calls `onRefill` when the popup gets new contents after it was shown, or while it stays shown.
function TemplateAdapter.HookRefill(_popup, _onRefill) end

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
      state.view = ns.View.Create(popup, {
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
      adapter.HookSelectedIconClick(popup, function()
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
  adapter.HookRefill(popup, function()
    if popup:IsShown() then
      onShow()
    end
  end)
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

-- Adapters for pickers of the game's own UI and of other add-ons, one file each in Adapters/ (Pickers.AddAdapter).
Pickers.adapters = {}
local eventAdapters = {}
local adapterEvents = CreateFrame("Frame")

-- False for an adapter whose integration the player turned off in the settings.
function Pickers.IsEnabled(spec)
  local disabled = ns.db and ns.db.disabledIntegrations
  return not (spec.integration and disabled and disabled[spec.integration.id])
end

local function attachAdapter(spec)
  if not Pickers.IsEnabled(spec) then
    return
  end
  local ok, frames = pcall(spec.frames)
  for _, popup in ipairs(ok and frames or {}) do
    Pickers.Attach(popup, spec.overrides)
  end
end

adapterEvents:SetScript("OnEvent", function(_, event)
  if ns.db then
    for _, spec in ipairs(eventAdapters[event]) do
      attachAdapter(spec)
    end
  end
end)

-- Registers an adapter: { addon, frames, overrides, events, integration }. `addon` is the add-on whose pickers it
-- handles (nil for the game's always-loaded UI); frames() returns the picker frames that exist now; `overrides`
-- replace TemplateAdapter functions; `events` name further events after which its pickers may exist.
-- `integration` ({ id, name, addons }) makes it a setting players can turn off, shared by adapters with the same id
-- and shown while one of `addons` is installed.
function Pickers.AddAdapter(spec)
  Pickers.adapters[#Pickers.adapters + 1] = spec
  for _, event in ipairs(spec.events or {}) do
    eventAdapters[event] = eventAdapters[event] or {}
    table.insert(eventAdapters[event], spec)
    adapterEvents:RegisterEvent(event)
  end
end

local function isLoaded(addon)
  return not addon or not (C_AddOns and C_AddOns.IsAddOnLoaded) or C_AddOns.IsAddOnLoaded(addon)
end

-- The integrations of the registered adapters, one per id, in registration order.
function Pickers.Integrations()
  local list, seen = {}, {}
  for _, spec in ipairs(Pickers.adapters) do
    local integration = spec.integration
    if integration and not seen[integration.id] then
      seen[integration.id] = true
      list[#list + 1] = integration
    end
  end
  return list
end

-- Turns integration `id` on or off. Turning it on attaches its loaded pickers now; pickers already replaced stay so
-- until /reload.
function Pickers.SetIntegrationEnabled(id, enabled)
  if not ns.db then
    return
  end
  ns.db.disabledIntegrations[id] = not enabled or nil
  if enabled then
    for _, spec in ipairs(Pickers.adapters) do
      if spec.integration and spec.integration.id == id and isLoaded(spec.addon) then
        attachAdapter(spec)
      end
    end
  end
end

-- Attaches the pickers of every adapter whose add-on is loaded.
function Pickers.AttachAll()
  for _, spec in ipairs(Pickers.adapters) do
    if isLoaded(spec.addon) then
      attachAdapter(spec)
    end
  end
end

-- Attaches the pickers of the adapters for add-on `name`, and of the game's own UI, which may have just loaded.
function Pickers.OnAddonLoaded(name)
  for _, spec in ipairs(Pickers.adapters) do
    if not spec.addon or spec.addon == name then
      attachAdapter(spec)
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
