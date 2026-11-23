local ADDON_NAME, ns = ...

-- Suggestion sources for Blizzard's pickers: each returns textures, then the name being entered as a query.
local Pickers, TemplateAdapter = ns.Pickers, ns.Pickers.TemplateAdapter

local EQUIPPED_SLOTS = 19
local GUILD_BANK_SLOTS = 98

local function withName(popup, list)
  for _, entry in ipairs(TemplateAdapter.GetSuggestions(popup)) do
    list[#list + 1] = entry
  end
  return list
end

local function isEditing(popup)
  return IconSelectorPopupFrameModes and popup.mode == IconSelectorPopupFrameModes.Edit
end

local function classIcon()
  local _, classFile = UnitClass("player")
  return classFile and ("Interface\\Icons\\ClassIcon_" .. classFile)
end

local function specIcon(index)
  local info = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
  return info and select(4, info(index))
end

-- Talent tree icons, for clients where a class has a single spec with several talent trees (WoW Forever).
local function treeIcons(list)
  if not (C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_ClassTalents) then
    return
  end
  local S = C_SpecializationInfo
  local configID = C_ClassTalents.GetActiveConfigID()
    or (S.GetCombatConfigIDForSpecGroup and S.GetCombatConfigIDForSpecGroup(S.GetActiveSpecGroup()))
  local config = configID and C_Traits.GetConfigInfo(configID)
  local treeID = config and config.treeIDs and config.treeIDs[1]
  for _, group in ipairs(treeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
    list[#list + 1] = group.icon
  end
end

-- The class icon, then the assigned spec's icon, or every spec or talent tree icon when none is assigned.
local function classAndSpecIcons(list, assignedSpec)
  list[#list + 1] = classIcon() or false
  if assignedSpec then
    list[#list + 1] = specIcon(assignedSpec) or false
    return
  end
  local classID = select(3, UnitClass("player"))
  local S = C_SpecializationInfo
  local count = S and S.GetNumSpecializationsForClassID and S.GetNumSpecializationsForClassID(classID) or 0
  for i = 1, count do
    list[#list + 1] = specIcon(i) or false
  end
  if count <= 1 then
    treeIcons(list)
  end
end

local function itemIcon(item)
  local ok, icon = pcall(C_Item.GetItemIconByID, item)
  return ok and icon or nil
end

local function spellIcon(spell)
  local ok, icon = pcall(C_Spell.GetSpellTexture, spell)
  return ok and icon or nil
end

local function containerIcons(list, bag)
  for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
    local info = C_Container.GetContainerItemInfo(bag, slot)
    list[#list + 1] = info and info.iconFileID or false
  end
end

-- Drops the nil and false entries left by missing data.
local function compact(list, count)
  local result = {}
  for i = 1, count or table.maxn(list) do
    if list[i] then
      result[#result + 1] = list[i]
    end
  end
  return result
end

Pickers.ADAPTERS.gear = {
  GetSuggestions = function(popup)
    local list = {}
    local setID = isEditing(popup) and popup.setID
    local E = C_EquipmentSet
    classAndSpecIcons(list, setID and E.GetEquipmentSetAssignedSpec and E.GetEquipmentSetAssignedSpec(setID))
    if setID then
      local items, slots = E.GetItemIDs(setID) or {}, {}
      for slot in pairs(items) do
        slots[#slots + 1] = slot
      end
      table.sort(slots)
      for _, slot in ipairs(slots) do
        list[#list + 1] = items[slot] and items[slot] > 0 and itemIcon(items[slot]) or false
      end
    else
      for slot = 1, EQUIPPED_SLOTS do
        list[#list + 1] = GetInventoryItemTexture("player", slot) or false
      end
    end
    return withName(popup, compact(list))
  end,
}

Pickers.ADAPTERS.macro = {
  GetSuggestions = function(popup)
    local list = {}
    local macroFrame = isEditing(popup) and MacroFrame
    if macroFrame then
      local _, _, body = GetMacroInfo(macroFrame:GetMacroDataIndex(macroFrame:GetSelectedIndex()))
      for _, term in ipairs(ns.Catalog.MacroTerms(body)) do
        if term.slot then
          list[#list + 1] = GetInventoryItemTexture("player", term.slot) or false
        else
          local icon = spellIcon(term.name) or itemIcon(term.name)
          list[#list + 1] = icon or { query = term.name }
        end
      end
    end
    return withName(popup, compact(list))
  end,
}

Pickers.ADAPTERS.bank = {
  GetSuggestions = function(popup)
    local list = {}
    local tab = popup.GetSelectedTabData and popup:GetSelectedTabData()
    if tab and tab.ID then
      containerIcons(list, tab.ID)
    end
    return withName(popup, compact(list))
  end,
}

-- Baganator's bank windows, one per skin, each with its own copies of Blizzard's bank tab settings menu.
function Pickers.AttachBaganator()
  local skins = Baganator and Baganator.API and Baganator.API.Skins
  local skin = skins and skins.GetCurrentSkin and skins.GetCurrentSkin()
  if not skin then
    return
  end
  for _, kind in ipairs({ "Single", "Category" }) do
    local view = _G["Baganator_" .. kind .. "ViewBankViewFrame" .. skin]
    for _, tabs in ipairs({ view and view.Character or false, view and view.Warband or false }) do
      if tabs and tabs.TabSettingsMenu then
        Pickers.Attach(tabs.TabSettingsMenu, Pickers.ADAPTERS.bank)
      end
    end
  end
end

Pickers.ADAPTERS.guildBank = {
  GetSuggestions = function(popup)
    local list = {}
    local tab = GetCurrentGuildBankTab()
    for slot = 1, tab and GUILD_BANK_SLOTS or 0 do
      list[slot] = GetGuildBankItemInfo(tab, slot) or false
    end
    return withName(popup, compact(list, GUILD_BANK_SLOTS))
  end,
  -- A tab's items arrive after the picker opens.
  HookSuggestionChanges = function(_popup, onChange)
    local events = CreateFrame("Frame")
    events:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    events:SetScript("OnEvent", onChange)
  end,
}

Pickers.ADAPTERS.transmog = {
  GetSuggestions = function(popup)
    local list = {}
    local T = C_TransmogOutfitInfo
    local outfit = popup.outfitData
    if outfit and T and outfit.outfitID == T.GetCurrentlyViewedOutfitID() then
      for _, slotInfo in ipairs(T.GetAllSlotLocationInfo() or {}) do
        local info = T.GetViewedOutfitSlotInfo(slotInfo.slot, slotInfo.type, Enum.TransmogOutfitSlotOption.None)
        list[#list + 1] = info and info.texture or false
      end
    end
    return withName(popup, compact(list))
  end,
}
