local ADDON_NAME, ns = ...

local L = ns.L
local Catalog = ns.Catalog

local Browser = {}
local FOOTER_HEIGHT = 52
local LOGO_SIZE = 50
-- Room for the portrait left of the search box.
local SEARCH_LEFT = 56
ns.Browser = Browser

-- Every icon Blizzard offers in its pickers, spellbook icons first; also returns those extra icons.
local function allTextures()
  local provider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook)
  local textures, extras = {}, {}
  for i = 1, provider:GetNumIcons() do
    textures[i] = provider:GetIconByIndex(i)
  end
  for i, texture in ipairs(provider.extraIcons or {}) do
    extras[i] = texture
  end
  provider:Release()
  return textures, extras
end

function Browser:Create()
  local frame = CreateFrame("Frame", "IconicBrowserFrame", UIParent, "ButtonFrameTemplate")
  -- The logo, smaller than the portrait circle, on black.
  local portrait = frame:GetPortrait()
  portrait:SetColorTexture(0, 0, 0, 1)
  local logo = portrait:GetParent():CreateTexture(nil, "OVERLAY", nil, 1)
  logo:SetTexture("Interface\\AddOns\\Iconic\\Assets\\logo")
  logo:SetSize(LOGO_SIZE, LOGO_SIZE)
  logo:SetPoint("CENTER", portrait, "CENTER", 0, 2)
  -- No empty band under the title; a footer tall enough for the 36px preview.
  ButtonFrameTemplate_HideAttic(frame)
  FrameTemplate_SetButtonBarHeight(frame, FOOTER_HEIGHT)
  frame:SetSize(560, 560)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:Hide()
  tinsert(UISpecialFrames, frame:GetName())
  frame:SetTitle(L["Iconic"])

  -- Opens Iconic's settings page, left of the close button.
  local settings = CreateFrame("Button", nil, frame)
  settings:SetSize(15, 16)
  settings:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
  -- Above the title bar's border art, like the close button.
  settings:SetFrameLevel(frame.CloseButton:GetFrameLevel())
  settings:SetNormalAtlas("questlog-icon-setting")
  settings:SetHighlightAtlas("questlog-icon-setting", "ADD")
  settings:GetHighlightTexture():SetAlpha(0.4)
  settings:SetScript("OnClick", ns.OpenSettings)
  settings:SetScript("OnEnter", function(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Settings"])
    GameTooltip:Show()
  end)
  settings:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  self.view = ns.CreateView(frame, {
    searchLeft = SEARCH_LEFT,
    onSelect = function(texture)
      self:SetSelected(texture)
    end,
  })
  self.view.frame:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 3, -6)
  self.view.frame:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -4, 4)

  local preview = CreateFrame("Button", nil, frame)
  preview:SetSize(36, 36)
  preview:SetPoint("BOTTOMLEFT", 12, 8)
  preview.icon = preview:CreateTexture(nil, "ARTWORK")
  preview.icon:SetAllPoints()
  preview.iconicButton = true
  preview:SetScript("OnEnter", function(owner)
    if self.selectedRow then
      self.view:ShowTooltip(owner, self.selectedRow)
    end
  end)
  preview:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  self.preview = preview

  local idLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  idLabel:SetPoint("TOPLEFT", preview, "TOPRIGHT", 8, -2)
  idLabel:SetText(L["Icon ID"])

  local idBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  idBox:SetSize(110, 20)
  idBox:SetPoint("BOTTOMLEFT", preview, "BOTTOMRIGHT", 12, 0)
  idBox:SetAutoFocus(false)
  idBox:SetScript("OnEditFocusGained", function(box)
    box:HighlightText()
  end)
  idBox:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(box.value or "")
      box:HighlightText()
    end
  end)
  idBox:SetScript("OnEscapePressed", idBox.ClearFocus)
  self.idBox = idBox

  local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  nameText:SetPoint("LEFT", idBox, "RIGHT", 12, 0)
  nameText:SetPoint("RIGHT", frame, "RIGHT", -190, 0)
  nameText:SetJustifyH("LEFT")
  nameText:SetWordWrap(false)
  self.nameText = nameText

  local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  close:SetSize(80, 22)
  close:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -10, 20)
  close:SetText(CLOSE)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  local choose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  choose:SetSize(90, 22)
  choose:SetPoint("RIGHT", close, "LEFT", -6, 0)
  choose:SetText(L["Choose"])
  choose:SetScript("OnClick", function()
    local callback, texture = self.onChoose, self.selected
    if callback and texture then
      ns.AddRecent(texture)
      frame:Hide()
      callback(texture)
    end
  end)
  self.choose = choose

  local footer = self.view.footer
  footer.brand:Hide()
  footer:SetWidth(200)
  footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
  footer.count:ClearAllPoints()
  footer.count:SetPoint("RIGHT")

  frame:SetScript("OnHide", function()
    self.onChoose = nil
  end)
  self.frame = frame
end

function Browser:SetSelected(texture)
  self.selected = texture
  self.view:SetSelected(texture)
  self.preview.icon:SetTexture(texture or 134400)
  local data = self.view.data
  local id = texture and Catalog.ResolveId(texture)
  self.idBox.value = id and tostring(id) or ""
  self.idBox:SetText(self.idBox.value)
  local row = data and data.index.byKey[id or texture or ""]
  self.selectedRow = row
  local names, pending = {}, false
  if row then
    names, pending = Catalog.Names(data.index, row)
  end
  if pending then
    ns.AfterNames("browser", function()
      if self.selected == texture then
        self:SetSelected(texture)
      end
    end)
  end
  self.nameText:SetText(row and (names[1] or data.index.file[row] or tostring(data.index.key[row])) or "")
  self.choose:SetEnabled(texture ~= nil)
end

-- Shows the browser. opts: onChoose(texture) turns it into a picker with a Choose button; icon preselects.
function Browser:Open(opts)
  opts = opts or {}
  if not self.frame then
    self:Create()
  end
  self.onChoose = opts.onChoose
  self.choose:SetShown(opts.onChoose ~= nil)
  self.frame:SetTitle(opts.title or L["Iconic"])
  self.frame:Show()
  local textures, extras = allTextures()
  self.view:SetTextures(textures, extras)
  self:SetSelected(opts.icon)
  self.view:ScrollToSelected()
end

function Browser:Toggle()
  if self.frame and self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Open()
  end
end
