local addon = require("spec.helpers.addon")

-- Every interface text the code passes to L[] has a translation in each locale file.
describe("Translations", function()
  local function usedKeys()
    local keys, labels = {}, {}
    local files = io.popen(
      'find "'
        .. addon.root
        .. '" -type f -name "*.lua" -not -path "*/.luarocks/*" -not -path "*/spec/*" -not -path "*/Iconic_Data/*" -not -path "*/Locales/*" -not -path "*/.cache/*"'
    )
    for path in files:lines() do
      local source = assert(io.open(path)):read("*a")
      for key in source:gmatch('L%["(.-)"%]') do
        keys[key] = true
      end
      for key in source:gmatch("L%['(.-)'%]") do
        keys[key] = true
      end
      for label in source:gmatch('label = "(.-)"') do
        labels[label] = true
      end
    end
    files:close()
    for label in pairs(labels) do
      keys[label] = true
    end
    -- Keys as Lua reads them: decimal escapes such as \194\183 become bytes.
    local decoded = {}
    for key in pairs(keys) do
      decoded[key:gsub("\\(%d%d?%d?)", function(code)
        return string.char(tonumber(code))
      end)] = true
    end
    return decoded
  end

  it("cover every text in German", function()
    local ns = addon.load()
    local german = ns.Locales.deDE
    local missing = {}
    for key in pairs(usedKeys()) do
      if german[key] == nil then
        missing[#missing + 1] = key
      end
    end
    table.sort(missing)
    assert.are.same({}, missing)
  end)
end)

-- Every picture tag in scripts/icon_tags.json and every synonym word has single-word translations in each locale's
-- scripts/search_words_<locale>.json, which scripts/build_data.py ships as the locale's translated words.
describe("Search word translations", function()
  local function read(path)
    local file = assert(io.open(path))
    local text = file:read("*a")
    file:close()
    return text
  end

  local tags = {}
  for list in read(addon.root .. "/scripts/icon_tags.json"):gmatch("%[(.-)%]") do
    for tag in list:gmatch('"(.-)"') do
      tags[tag] = true
    end
  end
  for _, group in ipairs(addon.load().SYNONYMS) do
    for _, word in ipairs(group) do
      tags[word] = true
    end
  end

  for _, locale in ipairs({ "deDE" }) do
    it("cover every tag and synonym in " .. locale, function()
      local translated, bad = {}, {}
      for tag, words in read(addon.root .. "/scripts/search_words_" .. locale .. ".json"):gmatch('"(.-)":%s*%[(.-)%]') do
        translated[tag] = true
        local count, phrase = 0, false
        for word in words:gmatch('"(.-)"') do
          count = count + 1
          phrase = phrase or word == "" or word:find("%s") ~= nil
        end
        if count == 0 or phrase then
          bad[#bad + 1] = tag
        end
      end
      local missing = {}
      for tag in pairs(tags) do
        if not translated[tag] then
          missing[#missing + 1] = tag
        end
      end
      table.sort(missing)
      table.sort(bad)
      assert.are.same({}, missing)
      assert.are.same({}, bad)
    end)
  end
end)
