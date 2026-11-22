local ADDON_NAME, ns = ...

ns.locale = GetLocale and GetLocale() or "enUS"

-- Locale tables register themselves here; English needs none (keys are the strings).
ns.Locales = {}

-- Never swapped, so a file-scope `local L = ns.L` stays valid. Never call L[] at file scope.
ns.L = setmetatable({}, {
  __index = function(_, key)
    local locale = ns.Locales[ns.locale]
    local value = locale and locale[key]
    if value ~= nil then
      return value
    end
    return key
  end,
})
