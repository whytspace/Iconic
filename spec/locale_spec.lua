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
