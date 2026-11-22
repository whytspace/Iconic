std = "lua51"
codes = true
max_line_length = false
ignore = {
  "211/ADDON_NAME",
  "212/self",
}

exclude_files = {
  ".claude/**",
  ".devcontainer/**",
  ".cache/**",
  "Iconic_Data/**",
}

files["spec"] = {
  std = "lua51+busted",
}

globals = {
  "Iconic",
  "IconicData",
  "IconicDB",
  "SLASH_ICONIC1",
  "SlashCmdList",
}

read_globals = {
  "BankPanel",
  "ButtonFrameTemplate_HideAttic",
  "ButtonFrameTemplate_HidePortrait",
  "C_AddOns",
  "C_ClassColor",
  "C_Container",
  "C_CreatureInfo",
  "C_CurrencyInfo",
  "C_Item",
  "C_MountJournal",
  "C_Spell",
  "C_SpellBook",
  "C_Timer",
  "CLOSE",
  "CreateAndInitFromMixin",
  "CreateAtlasMarkup",
  "CreateColor",
  "CreateDataProvider",
  "CreateFrame",
  "CreateScrollBoxListLinearView",
  "FrameTemplate_SetButtonBarHeight",
  "Enum",
  "GameTooltip",
  "GearManagerPopupFrame",
  "GetClassAtlas",
  "GetInventoryItemTexture",
  "GetLocale",
  "GuildBankPopupFrame",
  "hooksecurefunc",
  "IconDataProviderExtraType",
  "IconDataProviderMixin",
  "IsAltKeyDown",
  "IsControlKeyDown",
  "IsPlayerSpell",
  "IsShiftKeyDown",
  "ItemRefTooltip",
  "MacroPopupFrame",
  "MenuResponse",
  "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
  "RAID_CLASS_COLORS",
  "ScrollBoxConstants",
  "ScrollUtil",
  "Settings",
  "strtrim",
  "tinsert",
  "TooltipDataProcessor",
  "TransmogFrame",
  "UIParent",
  "UISpecialFrames",
}
