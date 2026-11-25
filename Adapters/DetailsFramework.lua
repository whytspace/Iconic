local ADDON_NAME, ns = ...

local Pickers, TemplateAdapter = ns.Pickers, ns.Pickers.TemplateAdapter

-- The icon picker of DetailsFramework, the library behind Details!, Plater and World Quest Tracker. A click picks
-- an icon at once; there is no selected icon or Okay button.
local WIDTH, HEIGHT = 560, 560

local picked, confirms = {}, {}

local function frameOf(widget)
  return widget and (widget.widget or widget)
end

local overrides = {
  Anchor = function(popup, viewFrame)
    popup:SetSize(WIDTH, HEIGHT)
    viewFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -30)
    viewFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -10, 44)
    viewFrame:SetFrameLevel(popup:GetFrameLevel() + 5)
    popup:HookScript("OnHide", function()
      picked[popup] = nil
    end)
    -- DF's grid hid the icon path's preview on hover; without it, keep it only for a typed path being edited or hovered.
    local preview, entry = popup.preview, frameOf(popup.customIconEntry)
    if preview and entry then
      local function update()
        if entry:GetText() == "" or not (entry:HasFocus() or entry:IsMouseOver()) then
          preview:Hide()
        end
      end
      preview:HookScript("OnShow", update)
      for _, script in ipairs({ "OnTextChanged", "OnLeave", "OnEditFocusLost" }) do
        entry:HookScript(script, update)
      end
    end
  end,
  -- Right of the icon path row, up to the window's edge.
  AnchorFooter = function(popup, footer)
    local accept = frameOf(popup.customIconAccept)
    local right, edge = accept and accept:GetRight(), popup:GetRight()
    footer:ClearAllPoints()
    if not (right and edge) then
      footer:Hide()
      return
    end
    footer:SetPoint("LEFT", accept, "RIGHT", 12, 0)
    footer:SetWidth(edge - right - 24)
  end,
  -- The macro picker's icons, which DetailsFramework shows too.
  GetTextures = function()
    local provider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook)
    local textures, extras = TemplateAdapter.GetTextures({ iconDataProvider = provider })
    provider:Release()
    return textures, extras
  end,
  GetIcon = function(popup)
    return picked[popup]
  end,
  SetIcon = function(popup, texture)
    picked[popup] = texture
    local callback, param1, param2 = popup.callback, popup.param1, popup.param2
    if callback then
      xpcall(function()
        callback(texture, param1, param2)
      end, geterrorhandler())
    end
    if confirms[popup] then
      confirms[popup]()
    end
    if popup.click_close then
      popup:Hide()
    end
  end,
  HideNative = function(popup)
    for _, widget in ipairs({ DetailsFrameworkIconPickFrameScroll, popup.search, popup.searchLabel }) do
      local frame = frameOf(widget)
      if frame and frame:IsShown() then
        frame:Hide()
      end
    end
  end,
  -- DetailsFramework shows its grid again whenever the search text resets.
  HookStateChanges = function(_popup, onChange)
    local scroll = DetailsFrameworkIconPickFrameScroll
    if scroll then
      scroll:HookScript("OnShow", onChange)
    end
  end,
  ShowSelectedState = function() end,
  HookConfirm = function(popup, onConfirm)
    confirms[popup] = onConfirm
  end,
}

-- The frame exists once an add-on first opens the picker, so Iconic attaches right after IconPick.
local spec, hookedPick

local function hookLibrary()
  local DF = LibStub and LibStub("DetailsFramework-1.0", true)
  if not DF or not DF.IconPick or DF.IconPick == hookedPick then
    return
  end
  hooksecurefunc(DF, "IconPick", function()
    if Pickers.IsEnabled(spec) then
      Pickers.Attach(DetailsFrameworkIconPickFrame, overrides)
    end
  end)
  hookedPick = DF.IconPick
end

spec = {
  integration = {
    id = "DetailsFramework",
    name = "Details!, Plater, World Quest Tracker",
    addons = { "Details", "Plater", "WorldQuestTracker" },
  },
  overrides = overrides,
  frames = function()
    hookLibrary()
    return DetailsFrameworkIconPickFrame and { DetailsFrameworkIconPickFrame } or {}
  end,
}
Pickers.AddAdapter(spec)
