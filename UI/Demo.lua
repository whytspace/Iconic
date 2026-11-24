local ADDON_NAME, ns = ...

-- Maintainer tool behind /iconic shot demo: opens a new equipment set's icon picker, plays the README animation's
-- steps and captures every step with /iconic shot's black and white backdrops. For scripts/make-demo.sh it stores
-- each frame's display time (IconicDB.demoFrames) and mouse pointer spot (demoPointerX, demoPointerY), and the screen
-- area of the set's picker and the color picker (demoBox); the game writes them on /reload. It never saves the set.
local Demo = {}
ns.Demo = Demo

-- Lets the search (debounced in View) and the grid settle after a step, before its capture.
local SETTLE = 0.5
-- Display times (seconds) in the animation.
local HOLD_LETTER, HOLD_WORD, HOLD_PAUSE, HOLD_MOTION, HOLD_END = 0.12, 0.6, 0.8, 0.08, 2.5
-- The new equipment set's name, typed first, NAME_CHUNK letters per frame to keep the capture short.
local SET_NAME, NAME_CHUNK = "Avenger Tank", 3
-- The first color, typed; the second is picked in the color picker and weighted down to SECOND_WEIGHT.
local FIRST_COLOR, SECOND_WEIGHT = "purple", 25
-- The color picker's start color (white) and gold, walked between in COLOR_STEPS steps.
local COLOR_FROM, COLOR_TO, COLOR_STEPS = { 1, 1, 1 }, { 0.83, 0.65, 0.17 }, 12
-- How far down the results scroll, in SCROLL_STEPS steps.
local SCROLL_TO, SCROLL_STEPS = 0.12, 8
-- The icon picked at the end.
local TARGET_ICON = "Ward of the Violet Citadel"

local function chat(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Iconic:|r " .. message)
end

-- Opens the character window's equipment sets and starts a new set, as Blizzard's "New Set" button does; returns
-- the set's icon picker view.
local function openNewSet()
  ToggleCharacter("PaperDollFrame", true)
  PaperDollFrame_SetSidebar(nil, 3)
  GearSetButton_OnClick({})
  local state = ns.Pickers.attached[GearManagerPopupFrame]
  return state and state.view
end

-- The suggestion button for `value`, marked as selected like the arrow keys do (it has no hover highlight).
local function selectSuggestion(view, value)
  for i, button in ipairs(view.search:GetButtons()) do
    if button:IsShown() and button.suggestion and button.suggestion.value == value then
      view.search:SetSearchPreviewSelection(i)
      return button
    end
  end
end

-- The button showing the icon named `name`, scrolling it into view first.
local function iconButton(view, name)
  local index, found = view.data.index
  local function isTarget(row)
    for _, n in ipairs(ns.Catalog.Names(index, row)) do
      if n == name then
        return true
      end
    end
  end
  local element = view.provider:FindElementDataByPredicate(function(elementData)
    for _, row in ipairs(elementData.rows or {}) do
      if isTarget(row) then
        return true
      end
    end
  end)
  if element then
    view.scrollBox:ScrollToElementData(element, ScrollBoxConstants.AlignCenter)
  end
  view.scrollBox:ForEachFrame(function(frame)
    for _, button in ipairs(frame.buttons or {}) do
      if button:IsShown() and isTarget(button.row) then
        found = button
      end
    end
  end)
  return found
end

-- Screen pixels per unit of a region's effective scale, and the screen size.
local function screenScale()
  local width, height = GetPhysicalScreenSize()
  return height / (UIParent:GetHeight() * UIParent:GetEffectiveScale()), width, height
end

-- Center of a frame or texture in screen pixels from the top left, or nil when it isn't shown.
local function screenCenter(region)
  if not (region and region:IsVisible() and region:GetCenter()) then
    return nil
  end
  local toPixels, _, height = screenScale()
  local x, y = region:GetCenter()
  local scale = region:GetEffectiveScale() * toPixels
  return x * scale, height - y * scale
end

-- Grows `box` (screen pixels from the top left) around the shown frames: the set's icon picker, its search
-- suggestions, and the color picker with its weight panel.
local function growBox(box, view)
  local toPixels, width, height = screenScale()
  local slider = view:WeightSlider()
  for _, frame in ipairs({
    GearManagerPopupFrame,
    view.search.searchPreviewContainer,
    ColorPickerFrame or false,
    slider and slider:GetParent() or false,
  }) do
    if frame and frame:IsVisible() and frame:GetLeft() then
      local scale = frame:GetEffectiveScale() * toPixels
      box.left = math.min(box.left or math.huge, frame:GetLeft() * scale)
      box.right = math.max(box.right or 0, frame:GetRight() * scale)
      box.top = math.min(box.top or math.huge, height - frame:GetTop() * scale)
      box.bottom = math.max(box.bottom or 0, height - frame:GetBottom() * scale)
    end
  end
  box.screenWidth, box.screenHeight = width, height
end

-- The demo's frames, in order: { hold = display time, run = what changes before the capture, pointer = the region
-- the mouse pointer is on, drawn in by scripts/make-demo.sh; without one it stays where it was }.
local function frames(view, nameBox)
  local list = {}
  local function add(hold, run, pointer)
    list[#list + 1] = { hold = hold, run = run or function() end, pointer = pointer }
  end
  local function typeInto(box, word, chunk)
    chunk = chunk or 1
    for i = chunk, #word + chunk - 1, chunk do
      local length = math.min(i, #word)
      add(length == #word and HOLD_WORD or HOLD_LETTER * chunk, function()
        box:SetFocus()
        box:SetText(word:sub(1, length))
      end, i == chunk and function()
        return box
      end or nil)
    end
  end
  local function okayButton()
    return ColorPickerFrame.Footer and ColorPickerFrame.Footer.OkayButton or _G.ColorPickerOkayButton
  end

  add(HOLD_PAUSE, function()
    view.filters = {}
    view:SetChips({})
    view.search:SetText("")
    view:Refresh()
    nameBox:SetText("")
    nameBox:SetFocus()
  end, function()
    return nameBox
  end)
  typeInto(nameBox, SET_NAME, NAME_CHUNK)
  typeInto(view.search, FIRST_COLOR)
  local suggestion
  add(HOLD_PAUSE, function()
    suggestion = selectSuggestion(view, FIRST_COLOR)
  end, function()
    return suggestion
  end)
  add(HOLD_WORD, function()
    if suggestion then
      suggestion:Click()
    end
    view.search:SetFocus()
  end)
  typeInto(view.search, "shield")
  for k = 1, SCROLL_STEPS do
    add(k == SCROLL_STEPS and HOLD_PAUSE or HOLD_MOTION, function()
      view.scrollBox:SetScrollPercentage(SCROLL_TO * k / SCROLL_STEPS)
    end, k == 1 and function()
      return view.scrollBox
    end or nil)
  end
  add(HOLD_WORD, function()
    view.search:ClearFocus()
    view.addColorButton:LockHighlight()
  end, function()
    return view.addColorButton
  end)
  add(HOLD_WORD, function()
    view.addColorButton:UnlockHighlight()
    view:OpenColorPicker()
  end)
  for k = 1, COLOR_STEPS do
    add(k == COLOR_STEPS and HOLD_PAUSE or HOLD_MOTION, function()
      local t = k / COLOR_STEPS
      local function mix(c)
        return COLOR_FROM[c] + (COLOR_TO[c] - COLOR_FROM[c]) * t
      end
      ColorPickerFrame.Content.ColorPicker:SetColorRGB(mix(1), mix(2), mix(3))
    end, function()
      return ColorPickerFrame.Content.ColorPicker.WheelThumb
    end)
  end
  for weight = 95, SECOND_WEIGHT, -5 do
    add(weight == SECOND_WEIGHT and HOLD_PAUSE or HOLD_MOTION, function()
      local slider = view:WeightSlider()
      if slider then
        slider:SetValue(weight)
      end
    end, function()
      local slider = view:WeightSlider()
      return slider and slider.Slider.Thumb
    end)
  end
  add(HOLD_WORD, nil, okayButton)
  add(HOLD_PAUSE, function()
    ColorPickerFrame:Hide()
  end)
  local icon
  add(HOLD_WORD, function()
    icon = iconButton(view, TARGET_ICON)
    if icon then
      icon:LockHighlight()
    end
  end, function()
    return icon
  end)
  add(HOLD_END, function()
    if icon then
      icon:UnlockHighlight()
      icon:Click()
    end
  end)
  return list
end

-- Ends a running demo after the frame being captured.
function Demo:Stop()
  if self.running then
    self.stopping = true
    chat("stopping after this frame.")
  end
end

function Demo:Run()
  if self.running then
    return chat("the demo is already running.")
  end
  if InCombatLockdown() then
    return chat("the demo needs you out of combat.")
  end
  local view = openNewSet()
  if not view then
    return chat("could not open a new equipment set.")
  end
  self.running, self.stopping = true, false
  -- Grouping pauses while color chips are set, but not before the first one: start ungrouped.
  local groupBy = ns.db.groupBy
  ns.db.groupBy = "none"
  view:UpdateGroupText()
  local list = frames(view, GearManagerPopupFrame.BorderBox.IconSelectorEditBox)
  local holds, box, pointerX, pointerY = {}, {}, {}, {}
  chat(("capturing %d frames; keep the mouse away from the windows."):format(#list))

  local i = 0
  local function done(err)
    self.running = false
    ns.db.groupBy = groupBy
    view:UpdateGroupText()
    if err then
      chat("demo stopped: " .. tostring(err))
      return
    end
    ns.db.demoFrames, ns.db.demoBox = holds, box
    ns.db.demoPointerX, ns.db.demoPointerY = pointerX, pointerY
    chat("demo captured; /reload, then run scripts/make-demo.sh. Cancel the new set unless you want to keep it.")
  end
  local function nextFrame()
    i = i + 1
    local frame = list[i]
    if self.stopping then
      return done("stopped")
    elseif not frame then
      return done()
    end
    local ok, err = pcall(frame.run)
    if not ok then
      return done(err)
    end
    C_Timer.After(SETTLE, function()
      growBox(box, view)
      -- The pointer stays where it was unless this frame names a target; the first frames always do.
      local found, x, y = pcall(function()
        return screenCenter(frame.pointer and frame.pointer())
      end)
      if not (found and x) then
        x, y = pointerX[#pointerX], pointerY[#pointerY]
      end
      ns.Screenshot:Capture(CharacterFrame, function(captureErr)
        if captureErr then
          return done(captureErr)
        end
        holds[#holds + 1] = frame.hold
        pointerX[#holds], pointerY[#holds] = x or 0, y or 0
        nextFrame()
      end, { ColorPickerFrame })
    end)
  end
  nextFrame()
end
