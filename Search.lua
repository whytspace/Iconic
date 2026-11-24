local ADDON_NAME, ns = ...

local Search = {}
ns.Search = Search

local Color = ns.Color

local byte, find, gsub, lower, sub = string.byte, string.find, string.gsub, string.lower, string.sub

-- Weights per search-text field: name buckets (1st, 2nd, 3rd-4th, rest), file name, description.
-- Names and file name compete for the best hit; the description adds on top.
local FIELD_WEIGHTS = { 10, 8, 6, 4, 6, 3 }
-- Weight of a hit on an icon's item category name (index.categoryWords): below its names, above its description.
local CATEGORY_WEIGHT = 5
local NO_CATS = {}
local DESC_FIELD = 6
local QUALITY_EXACT, QUALITY_PREFIX, QUALITY_SYNONYM, QUALITY_FUZZY = 1, 0.7, 0.6, 0.5
-- Keys of the synonym map's translated words ({ words = sorted list, english = word -> tokens }) and readable words
-- (token -> word); no token has "#".
local TRANSLATED, READABLE = "#translated", "#readable"
local BONUS_PHRASE, BONUS_USABLE, BONUS_PLAYER, SCORE_ID = 5, 2, 2, 1000
-- With words and color chips, the share of the word match in the order; color closeness has the rest. Both are
-- taken relative to the best result.
local TEXT_SHARE = 0.5

-- Must match STOPWORDS in scripts/build_data.py.
local STOPWORDS = {}
for word in
  ([[a an and are as at be but by can for from has have in into is it its of on or per than that the their them
  then they this to up upon when while will with you your yours also each all any not over after before]]):gmatch(
    "%S+"
  )
do
  STOPWORDS[word] = true
end

-- Must match FILE_NOISE in scripts/build_data.py.
local FILE_NOISE = { inv = true, misc = true, ability = true, spell = true, icon = true, achievement = true }

-- Accented Latin letters (UTF-8) to base letters. Must match FOLD in scripts/build_data.py.
local FOLD = { ["\225\186\158"] = "ss" }
do
  local bases = {
    { "\192\193\194\195\196\197\224\225\226\227\228\229", "a" },
    { "\198\230", "ae" },
    { "\199\231", "c" },
    { "\200\201\202\203\232\233\234\235", "e" },
    { "\204\205\206\207\236\237\238\239", "i" },
    { "\208\240", "d" },
    { "\209\241", "n" },
    { "\210\211\212\213\214\216\242\243\244\245\246\248", "o" },
    { "\217\218\219\220\249\250\251\252", "u" },
    { "\221\253\255", "y" },
    { "\222\254", "th" },
    { "\223", "ss" },
  }
  -- Latin-1 code point c (192-255) is "\195" followed by c - 64 in UTF-8.
  for _, entry in ipairs(bases) do
    for i = 1, #entry[1] do
      FOLD["\195" .. string.char(byte(entry[1], i) - 64)] = entry[2]
    end
  end
end

function Search.Normalize(text)
  text = gsub(gsub(text or "", "\225\186\158", FOLD), "\195[\128-\191]", FOLD)
  text = lower(text)
  text = gsub(text, "'", "")
  text = gsub(text, "\226\128\153", "")
  text = gsub(text, "[^%w]+", " ")
  return (gsub(gsub(text, "^%s+", ""), "%s+$", ""))
end

-- Light English suffix stripping so "marks", "marked" and "marking" meet at "mark". Mirrored in build_data.py.
function Search.Stem(token)
  local n = #token
  if n <= 3 or find(token, "^%d+$") then
    return token
  end
  if n > 5 and sub(token, -3) == "ing" then
    return sub(token, 1, -4)
  end
  if n > 4 and sub(token, -3) == "ies" then
    return sub(token, 1, -4) .. "y"
  end
  if n > 4 and sub(token, -2) == "ed" then
    return sub(token, 1, -3)
  end
  if n > 4 and (sub(token, -3) == "hes" or sub(token, -3) == "xes" or sub(token, -3) == "ses") then
    return sub(token, 1, -3)
  end
  if sub(token, -1) == "s" and sub(token, -2) ~= "ss" then
    return sub(token, 1, -2)
  end
  return token
end

-- Normalized, stemmed tokens without stopwords.
function Search.Tokens(text)
  local tokens = {}
  for token in gsub(Search.Normalize(text), "%s+", " "):gmatch("%S+") do
    if not STOPWORDS[token] then
      tokens[#tokens + 1] = Search.Stem(token)
    end
  end
  return tokens
end

-- Search text for an icon without data: only its file name is known. Camel-case words split as in build_data.py.
function Search.FileText(file)
  local list = {}
  for _, token in ipairs(Search.Tokens(gsub(gsub(file or "", "(%l)(%u)", "%1 %2"), "%d+", " "))) do
    if not FILE_NOISE[token] then
      list[#list + 1] = token
    end
  end
  return "||||" .. table.concat(list, " ") .. "|"
end

-- Pads a data search field string ("a b|c|...") so every token is surrounded by spaces.
function Search.PadText(text)
  return " " .. gsub(text or "", "|", " | ") .. " "
end

-- Synonym groups ({ {"cloak", "cape", ...}, ... }) become token -> { other tokens }. `translated` (translated token ->
-- "english words") lets a translation's words count as the English words they stand for. The map also keeps a
-- readable word per token (Search.DisplayWord).
function Search.BuildSynonyms(groups, translated)
  local map, readable = {}, {}
  local function token(word)
    local t = Search.Tokens(word)[1]
    if t and not readable[t] then
      readable[t] = Search.Normalize(word)
    end
    return t
  end
  for _, group in ipairs(groups or {}) do
    local stems = {}
    for _, word in ipairs(group) do
      stems[#stems + 1] = token(word)
    end
    for _, t in ipairs(stems) do
      map[t] = map[t] or {}
      local seen = {}
      for _, other in ipairs(map[t]) do
        seen[other] = true
      end
      for _, other in ipairs(stems) do
        if other ~= t and not seen[other] then
          seen[other] = true
          map[t][#map[t] + 1] = other
        end
      end
    end
  end
  local words, english = {}, {}
  for word, list in pairs(translated or {}) do
    words[#words + 1] = word
    english[word] = {}
    for en in list:gmatch("%S+") do
      english[word][#english[word] + 1] = token(en)
    end
  end
  if #words > 0 then
    table.sort(words)
    map[TRANSLATED] = { words = words, english = english }
  end
  map[READABLE] = readable
  return map
end

-- The word to show for a search token, such as "iris" for "iri".
function Search.DisplayWord(synonyms, token)
  local readable = synonyms and synonyms[READABLE]
  return readable and readable[token] or token
end

-- Edit distance with adjacent swaps, capped at `max` (returns max + 1 when exceeded).
function Search.Distance(a, b, max)
  local la, lb = #a, #b
  if math.abs(la - lb) > max then
    return max + 1
  end
  local min = math.min
  local prev2, prev = nil, {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    local cur = { [0] = i }
    local rowMin = i
    local ca = byte(a, i)
    for j = 1, lb do
      local cb = byte(b, j)
      local v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == cb and 0 or 1))
      if prev2 and j > 1 and ca == byte(b, j - 1) and byte(a, i - 1) == cb then
        v = min(v, prev2[j - 2] + 1)
      end
      cur[j] = v
      if v < rowMin then
        rowMin = v
      end
    end
    if rowMin > max then
      return max + 1
    end
    prev2, prev = prev, cur
  end
  return prev[lb]
end

-- Cheap pre-check: typo candidates share the first letter, or swap the first two.
local function couldBeTypo(token, word)
  local t1, w1 = byte(token, 1), byte(word, 1)
  return t1 == w1 or (t1 == byte(word, 2) and byte(token, 2) == w1)
end

local function fuzzyBudget(token)
  if #token >= 7 then
    return 2
  elseif #token >= 4 then
    return 1
  end
  return 0
end

-- Every distinct token of the given texts, for typo lookups.
function Search.Vocabulary(texts)
  local seen, list = {}, {}
  for _, text in ipairs(texts) do
    for token in text:gmatch("[^%s|]+") do
      if not seen[token] then
        seen[token] = true
        list[#list + 1] = token
      end
    end
  end
  return list
end

-- Field (1-6) of a position in a padded search text.
local function fieldAt(text, pos)
  local field, p = 1, find(text, "|", 1, true)
  while p and p < pos do
    field = field + 1
    p = find(text, "|", p + 1, true)
  end
  return field
end

-- Whether a term also finds longer words; synonyms are whole words, so "cap" mustn't find "cape".
local function prefixAllowed(term, quality)
  return #term >= 3 and quality ~= QUALITY_SYNONYM
end

-- Best name/file hit and description hit of one term in a padded search text, and the field of the name hit.
local function termScore(text, term, quality)
  local needle = " " .. term
  local p = find(text, needle, 1, true)
  if not p then
    return 0, 0, nil
  end
  local allowPrefix = prefixAllowed(term, quality)
  local name, desc, nameField = 0, 0, nil
  local len = #needle
  while p do
    local exact = byte(text, p + len) == 32
    if exact or allowPrefix then
      local field = fieldAt(text, p)
      local score = FIELD_WEIGHTS[field] * quality * (exact and 1 or QUALITY_PREFIX)
      if field == DESC_FIELD then
        if score > desc then
          desc = score
        end
      elseif score > name then
        name, nameField = score, field
      end
    end
    p = find(text, needle, p + len, true)
  end
  return name, desc, nameField
end

-- Score of one query token over its variants (itself, synonyms, typo variants): the best name hit plus
-- the best description hit, which may come from different variants.
local function tokenScore(text, variants)
  local bestName, bestDesc = 0, 0
  for i = 1, #variants, 2 do
    local name, desc = termScore(text, variants[i], variants[i + 1])
    if name > bestName then
      bestName = name
    end
    if desc > bestDesc then
      bestDesc = desc
    end
  end
  return bestName + bestDesc
end

-- A partly typed word expands to translated words only while it starts at most this many.
local MAX_PREFIX_WORDS = 5

-- Adds `term` with `quality`, once per term at its best quality, reached from `parent`; `seen` maps term -> its
-- quality slot, `from` term -> parent.
local function addTerm(variants, seen, from, term, quality, parent)
  local slot = seen[term]
  if not slot then
    variants[#variants + 1] = term
    variants[#variants + 1] = quality
    seen[term], from[term] = #variants, parent
  elseif quality > variants[slot] then
    variants[slot], from[term] = quality, parent
  end
end

-- Adds `word` with `quality` and its synonyms.
local function addWord(variants, seen, from, synonyms, word, quality, parent)
  addTerm(variants, seen, from, word, quality, parent)
  for _, other in ipairs(synonyms[word] or {}) do
    addTerm(variants, seen, from, other, QUALITY_SYNONYM, word)
  end
end

-- Translated words a partly typed token starts, or none when it starts more than MAX_PREFIX_WORDS.
local function startedWords(translated, token)
  local started = {}
  if #token < 3 then
    return started
  end
  for _, word in ipairs(translated.words) do
    if find(word, token, 1, true) == 1 then
      started[#started + 1] = word
      if #started > MAX_PREFIX_WORDS then
        return {}
      end
    end
  end
  return started
end

-- A translated word counts as its English words typed. A partly typed one counts as their prefix, but a complete
-- word doesn't reach longer ones: "schwert" isn't "schwertlilie".
local function addTranslations(variants, seen, from, synonyms, token)
  local translated = synonyms[TRANSLATED]
  if not translated then
    return
  end
  local own = translated.english[token]
  if own then
    for _, en in ipairs(own) do
      addWord(variants, seen, from, synonyms, en, QUALITY_EXACT, token)
    end
    return
  end
  for _, word in ipairs(startedWords(translated, token)) do
    for _, en in ipairs(translated.english[word]) do
      addWord(variants, seen, from, synonyms, en, QUALITY_PREFIX, token)
    end
  end
end

-- Words of the vocabulary within the token's typo budget.
local function addTypos(variants, seen, from, token, vocabulary)
  local budget = fuzzyBudget(token)
  if budget == 0 then
    return
  end
  for _, word in ipairs(vocabulary) do
    if word ~= token and couldBeTypo(token, word) and Search.Distance(token, word, budget) <= budget then
      addTerm(variants, seen, from, word, QUALITY_FUZZY, token)
    end
  end
end

-- The query token's variants as { term, quality, ... }, and term -> the term it was reached from.
local function variantsFor(token, synonyms, vocabulary)
  local variants, seen, from = {}, {}, {}
  addWord(variants, seen, from, synonyms, token, QUALITY_EXACT)
  addTranslations(variants, seen, from, synonyms, token)
  if vocabulary then
    addTypos(variants, seen, from, token, vocabulary)
  end
  return variants, from
end

-- Per category number, the best hit of a token's variants on the category's words, weighted like a field.
local function categoryHits(categoryWords, variants)
  local hits = {}
  for number, words in pairs(categoryWords or {}) do
    local best = 0
    for i = 1, #variants, 2 do
      local term, quality = variants[i], variants[i + 1]
      local p = find(words, " " .. term, 1, true)
      if p then
        local exact = byte(words, p + #term + 1) == 32
        if exact or prefixAllowed(term, quality) then
          best = math.max(best, CATEGORY_WEIGHT * quality * (exact and 1 or QUALITY_PREFIX))
        end
      end
    end
    if best > 0 then
      hits[number] = best
    end
  end
  return hits
end

-- Word part of a row's score: each token's best hit on its text or item categories, plus the phrase bonus. Without
-- `loose` every token must hit; with it, the score shrinks with the share of tokens that hit.
local function wordScore(text, rowCats, q, loose)
  local score, matched, tokenCount = 0, 0, #q.variants
  for i = 1, tokenCount do
    local s = tokenScore(text, q.variants[i])
    for _, number in ipairs(rowCats or NO_CATS) do
      local hit = q.catHits[i][number]
      if hit and hit > s then
        s = hit
      end
    end
    if s > 0 then
      matched = matched + 1
      score = score + s
    elseif not loose then
      return 0
    end
  end
  if score > 0 then
    if loose then
      score = score * matched / tokenCount
    end
    if q.phrase and find(text, q.phrase, 1, true) then
      score = score + BONUS_PHRASE
    end
  end
  return score
end

-- Sorts results: by color alone without words; with words, by a blend of word match and color; ties by score,
-- then by their order in `rows`.
local function sortResults(results, rows, scores, closeness, chips, hasWords)
  local position = {}
  for i, row in ipairs(rows) do
    position[row] = i
  end
  local order = chips and closeness
  if chips and hasWords then
    local bestScore, bestClose = 0, 0
    for _, row in ipairs(results) do
      bestScore, bestClose = math.max(bestScore, scores[row]), math.max(bestClose, closeness[row])
    end
    order = {}
    for _, row in ipairs(results) do
      order[row] = TEXT_SHARE * scores[row] / bestScore + (1 - TEXT_SHARE) * closeness[row] / bestClose
    end
  end
  table.sort(results, function(a, b)
    if order and order[a] ~= order[b] then
      return order[a] > order[b]
    end
    if scores[a] ~= scores[b] then
      return scores[a] > scores[b]
    end
    return position[a] < position[b]
  end)
end

-- One pass over the candidate rows. `index` holds the columns (see Catalog.NewIndex).
local function run(index, rows, query, opts, loose)
  local tokens = Search.Tokens(query)
  local synonyms = opts.synonyms or {}
  local usable = opts.usable
  local idQuery = tonumber(Search.Normalize(query))

  local vocabulary = loose and opts.vocabulary and opts.vocabulary() or nil
  local q = { variants = {}, catHits = {}, phrase = #tokens > 1 and (" " .. table.concat(tokens, " ") .. " ") or nil }
  for i, token in ipairs(tokens) do
    q.variants[i] = variantsFor(token, synonyms, vocabulary)
    q.catHits[i] = categoryHits(index.categoryWords, q.variants[i])
  end

  local texts, ids, keys, spells, categories = index.text, index.id, index.key, index.spells, index.categories
  local chips = opts.chips and #opts.chips > 0 and opts.chips or nil
  local bands = {}
  for i, chip in ipairs(chips or {}) do
    bands[i] = Color.ChipBand(chip)
  end
  local scores, closeness, results = {}, {}, {}
  for _, row in ipairs(rows) do
    local score
    local colorPart = chips and Color.ChipScore(index, row, chips, bands)
    if chips and not colorPart then
      score = 0
    elseif idQuery and ids[row] == idQuery then
      score = SCORE_ID
    elseif #tokens == 0 then
      -- Color chips alone keep every icon that has their colors.
      score = chips and 1 or 0
    else
      score = wordScore(texts[row], categories[row], q, loose)
    end
    if score > 0 then
      if usable and usable[keys[row]] then
        score = score + BONUS_USABLE
      end
      if spells[row] then
        score = score + BONUS_PLAYER
      end
      scores[row] = score
      closeness[row] = colorPart
      results[#results + 1] = row
    end
  end
  sortResults(results, rows, scores, closeness, chips, #tokens > 0)
  return results, scores
end

-- Ranked rows matching every query token; when none do, a looser pass (any token, typos) and
-- `isLoose = true`. Returns rows, isLoose, scores (row -> score).
-- opts: synonyms (from BuildSynonyms), usable (key -> true), vocabulary (function returning a token list),
-- chips (color chips, see Color.ChipScore: keeps icons with every chip's color and ranks them by the weakest first).
function Search.Find(index, rows, query, opts)
  opts = opts or {}
  local results, scores = run(index, rows, query, opts, false)
  if #results > 0 or #Search.Tokens(query) == 0 then
    return results, false, scores
  end
  results, scores = run(index, rows, query, opts, true)
  return results, true, scores
end

-- Color for the words of a name that a search word finds (the game's gold).
local HIGHLIGHT = "|cffffd100"

-- Each query token with the word typed for it and its variants (itself, synonyms).
local function queryTerms(query, synonyms)
  local terms = {}
  for word in Search.Normalize(query):gmatch("%S+") do
    local token = Search.Tokens(word)[1]
    if token then
      local variants, from = variantsFor(token, synonyms or {})
      terms[#terms + 1] = { word = word, token = token, variants = variants, from = from }
    end
  end
  return terms
end

local function startsWith(text, term, quality)
  return text == term or (prefixAllowed(term, quality) and sub(text, 1, #term) == term)
end

-- Why a row matches a query: per search word { word, via = the words it matched through, such as { "sword", "claymore" },
-- if any, where = "name" | "tag" | "description" |
-- "category" }, then per color chip { color = name, share = 0-100 }. Words that don't match are left out.
-- opts: synonyms, chips (as for Search.Find).
function Search.Explain(index, row, query, opts)
  opts = opts or {}
  local text = index.text[row]
  local found = {}
  for _, term in ipairs(queryTerms(query, opts.synonyms)) do
    local best, where, via = 0, nil, nil
    for i = 1, #term.variants, 2 do
      local variant = term.variants[i]
      local name, desc, nameField = termScore(text, variant, term.variants[i + 1])
      if name > best then
        best, via, where = name, i > 1 and variant or nil, nameField <= 4 and "name" or "tag"
      end
      if desc > best then
        best, via, where = desc, i > 1 and variant or nil, "description"
      end
    end
    for number, hit in pairs(categoryHits(index.categoryWords, term.variants)) do
      for _, own in ipairs(index.categories[row] or NO_CATS) do
        if own == number and hit > best then
          best, where, via = hit, "category", nil
        end
      end
    end
    if where then
      local path
      if via then
        path = {}
        local step = via
        while step and step ~= term.token do
          table.insert(path, 1, Search.DisplayWord(opts.synonyms, step))
          step = term.from[step]
        end
      end
      found[#found + 1] = { word = term.word, via = path, where = where }
    end
  end
  for _, chip in ipairs(opts.chips or {}) do
    local t = chip.target
    local _, share = Color.ChipValue(index, row, Color.ChipBand(chip))
    found[#found + 1] = { color = chip.preset or Color.Name(t[1], t[2], t[3]), share = math.floor(share + 0.5) }
  end
  return found
end

-- `text` with the words a query's words find colored, by the same stemming, prefix and synonym rules as Find.
-- opts: synonyms.
function Search.Highlight(text, query, opts)
  local terms = queryTerms(query, opts and opts.synonyms)
  if #terms == 0 then
    return text
  end
  local translated = opts and opts.synonyms and opts.synonyms[TRANSLATED]
  local found = {}
  for _, term in ipairs(terms) do
    for i = 1, #term.variants, 2 do
      found[term.variants[i]] = true
    end
  end
  -- Whether a search word finds `token` as a whole word, directly or through its English translation.
  local function finds(token)
    if found[token] then
      return true
    end
    for _, en in ipairs(translated and translated.english[token] or {}) do
      if found[en] then
        return true
      end
    end
    return false
  end
  local function mark(word)
    local normal = Search.Normalize(word)
    if normal == "" or STOPWORDS[normal] then
      return word
    end
    local stem = Search.Stem(normal)
    for _, term in ipairs(terms) do
      for i = 1, #term.variants, 2 do
        local variant, quality = term.variants[i], term.variants[i + 1]
        if stem == variant or normal == variant then
          return HIGHLIGHT .. word .. "|r"
        elseif startsWith(normal, variant, quality) or startsWith(stem, variant, quality) then
          -- A prefix match colors only the typed part, where it lines up with the word's letters.
          for k = #variant, #word do
            if Search.Normalize(sub(word, 1, k)) == variant then
              return HIGHLIGHT .. sub(word, 1, k) .. "|r" .. sub(word, k + 1)
            end
          end
          return HIGHLIGHT .. word .. "|r"
        end
      end
    end
    -- A translated word whose English word a search word finds, such as "Klinge" (blade) for "sword".
    if finds(stem) then
      return HIGHLIGHT .. word .. "|r"
    end
    -- A compound ending in such a word: "Warpklinge".
    if translated then
      for k = 2, #normal - 3 do
        local tail = sub(normal, k)
        if finds(Search.Stem(tail)) then
          for j = 2, #word do
            if Search.Normalize(sub(word, j)) == tail then
              return sub(word, 1, j - 1) .. HIGHLIGHT .. sub(word, j) .. "|r"
            end
          end
          return HIGHLIGHT .. word .. "|r"
        end
      end
    end
    return word
  end
  return (gsub(text, "[%w\128-\255]+", mark))
end
