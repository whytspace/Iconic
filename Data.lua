local ADDON_NAME, ns = ...

local DATA_ADDON = "Iconic_Data"

-- Loads the icon data add-on once; returns the parsed data, or nil when it is missing.
function ns.LoadData()
  if ns.data ~= nil then
    return ns.data or nil
  end
  if not IconicData and C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn(DATA_ADDON)
  end
  if type(IconicData) == "table" then
    ns.data = ns.Catalog.Parse(IconicData)
    IconicData = nil
    -- Loaded with the data only in a client whose text language has a translation.
    if type(IconicDataLocale) == "table" then
      ns.Catalog.ApplyLocale(ns.data, IconicDataLocale)
      IconicDataLocale = nil
    end
  else
    ns.data = false
  end
  ns.synonyms = ns.Search.BuildSynonyms(ns.SYNONYMS)
  return ns.data or nil
end
