-- Lecteur d'histoires Telmi (portage de stories_reader.h)
local C = require("core")
local json = require("json")
local V, audio = C.video, C.audio

local S = {}
local APP_STORIES = 0
local MAX_STORIES_NIGHT_MODE = 16
local DISPLAY_SINGLE, DISPLAY_TILES = 0, 1

local SYSTEM_RESOURCES = C.RES
local STORIES_RESOURCES = C.STORIES
local STORIES_SAVES = C.STORIES_SAVES

local storiesDiplayMode = DISPLAY_SINGLE
local storiesNightModeEnabled = false
local storiesNightModePlaying = false
local storiesNightModeIndex = 0
local storiesNightModePlaylist = {} -- indices 0..15, "" = vide
local storiesNightModeCurrentAudio = ""
for i = 0, MAX_STORIES_NIGHT_MODE - 1 do storiesNightModePlaylist[i] = "" end

local storiesList = nil -- indices 0..n-1
local storiesHasSaveList = {}
local storiesIndexByName = {}
local storiesCount = 0
local storyIndex = 0

local storyJson = nil
local hasInventory = false
local storyInventoryCountLength = -1
local storyInventoryCount = nil -- indices 0..n-1
local storyStageKey = ""
local storyActionKey = ""
local storyActionOptionIndex = 0
local storyActionOptionsCount = 0
local storyTime = 0
local storyScreenEnabled = true
local storyAutoplay = false
local storyOkAction = true

local storyShowTimeline = false
local storyScreenUpdateTime = 0
local storyDrawTimelineTime = 0
local storyScreenEnableEndTime = 0

local storyLastPlayingTime = 0
local storyPlayingTime = 0

local callback_stories_autoplay, callback_stories_nightMode, callback_stories_reset
local callback_stories_audio_hook = nil

local function getStoryIndex(name)
  local i = storiesIndexByName[name]
  if i == nil then return -1 end
  return i
end

local function stories_autosleep_unlock()
  C.autosleep_unlock(C.params.screenOnInactivityTime, C.params.screenOffInactivityTime)
end

local function initPlayingTime()
  storyPlayingTime = 0
  storyLastPlayingTime = C.get_time()
end

local function getPlayingTime()
  local t = C.get_time()
  storyPlayingTime = storyPlayingTime + (t - storyLastPlayingTime)
  storyLastPlayingTime = t
  return storyPlayingTime
end

local function fmt(x) return string.format("%f", x or 0) end

local function saveSession(jsonPath)
  if storiesNightModeEnabled then
    if storiesNightModePlaying then
      local pl = {}
      for i = 0, MAX_STORIES_NIGHT_MODE - 1 do pl[#pl + 1] = '"' .. json.str(storiesNightModePlaylist[i]) .. '"' end
      C.file_save(jsonPath, string.format('{"app":%d, "nightMode":true, "playlist":[%s], "storyIndex":%d, "storyTime":%s}',
        APP_STORIES, table.concat(pl, ","), storiesNightModeIndex, fmt(storyTime)))
    end
  else
    local inv = {}
    if hasInventory then
      for i = 0, storyInventoryCountLength - 1 do inv[#inv + 1] = tostring(storyInventoryCount[i]) end
    end
    C.file_save(jsonPath, string.format(
      '{"app":%d, "storyPath":"%s", "storyActionKey":"%s", "storyActionOptionIndex":%d, "storyTime":%s, "storyPlayingTime":%d, "inventory":[%s]}',
      APP_STORIES, json.str(storiesList[storyIndex]), json.str(storyActionKey), storyActionOptionIndex,
      fmt(storyAutoplay and audio.getPosition() or 0), getPlayingTime(), table.concat(inv, ",")))
  end
end

local function loadJsonSession(pathJson)
  storyIndex = 0
  storyStageKey = ""
  storyActionKey = ""
  storyActionOptionIndex = 0
  storyTime = 0
  initPlayingTime()

  local saved = C.fs.loadJson(pathJson)
  if type(saved) ~= "table" then return false end

  local a = json.getInt(saved, "app")
  if a ~= nil and a == APP_STORIES then
    if json.getBool(saved, "nightMode") then
      storiesNightModeEnabled = true
      local arr = json.get(saved, "playlist")
      for i = 0, MAX_STORIES_NIGHT_MODE - 1 do
        local v = json.at(arr, i)
        storiesNightModePlaylist[i] = type(v) == "string" and v or ""
      end
      storiesNightModeIndex = json.getInt(saved, "storyIndex") or storiesNightModeIndex
    else
      local storyPath = json.getString(saved, "storyPath")
      if not storyPath then return false end
      storyIndex = getStoryIndex(storyPath)
      if storyIndex == -1 then
        storyIndex = 0
        return false
      end
      storyActionKey = json.getString(saved, "storyActionKey") or storyActionKey
      storyActionOptionIndex = json.getInt(saved, "storyActionOptionIndex") or storyActionOptionIndex
      storyPlayingTime = json.getInt(saved, "storyPlayingTime") or storyPlayingTime

      local inv = json.get(saved, "inventory")
      if json.isArray(inv) and json.size(inv) > 0 then
        storyInventoryCountLength = json.size(inv)
        storyInventoryCount = {}
        for i = 0, storyInventoryCountLength - 1 do
          local v = json.at(inv, i)
          storyInventoryCount[i] = type(v) == "number" and math.floor(v) or 0
        end
      else
        storyInventoryCount = nil
        storyInventoryCountLength = -1
      end
    end
    storyTime = json.getNumber(saved, "storyTime") or storyTime
    return true
  end
  return false
end

local function loadSession(pathJson)
  local result = loadJsonSession(pathJson)
  C.fs.remove(pathJson)
  return result
end

local function saveCurrentSession()
  if storiesNightModeEnabled then return end
  storiesHasSaveList[storyIndex] = true
  saveSession(STORIES_SAVES .. storiesList[storyIndex])
end

local function loadCurrentSession()
  if storiesNightModeEnabled or not storiesHasSaveList[storyIndex] then return end
  loadSession(STORIES_SAVES .. storiesList[storyIndex])
  storiesHasSaveList[storyIndex] = false
end

-- Mode nuit -------------------------------------------------------------------------
local function nightMode_reset()
  storiesNightModeEnabled = false
  storiesNightModePlaying = false
  storyShowTimeline = false
  storiesNightModeIndex = 0
  for i = 0, MAX_STORIES_NIGHT_MODE - 1 do storiesNightModePlaylist[i] = "" end
end

local function nightMode_count()
  for i = 0, MAX_STORIES_NIGHT_MODE - 1 do
    if storiesNightModePlaylist[i] == "" then return i end
  end
  return MAX_STORIES_NIGHT_MODE
end

local function nightMode_screenDisplayCount()
  V.screenAddImage(SYSTEM_RESOURCES, "storytellerNightModeCounter.png", 33, 2, 64)
  V.screenWriteFont(tostring(nightMode_count()), C.fontBold20, C.colorPurple, 74, 1, V.ALIGN_CENTER)
end

local function nightMode_isFull()
  return storiesNightModePlaylist[MAX_STORIES_NIGHT_MODE - 1] ~= ""
end

local function nightMode_isPlaylistableAudio()
  return storiesNightModeCurrentAudio ~= ""
end

local function nightMode_addToPlaylist()
  if nightMode_isFull() then return true end
  storiesNightModePlaylist[nightMode_count()] = storiesNightModeCurrentAudio
  return nightMode_isFull()
end

local function nightMode_play()
  callback_stories_audio_hook = callback_stories_nightMode
  audio.play_path(storiesNightModePlaylist[storiesNightModeIndex] or "", storyTime, true)
end

local function nightMode_resume()
  C.autosleep_lock()
  V.displayBlackScreen()
  C.display_setScreen(false)
  storyScreenEnabled = false
  storiesNightModePlaying = true
  storyShowTimeline = not C.params.storyDisableTimeline
  storiesNightModeCurrentAudio = ""
  nightMode_play()
end

local function nightMode_start()
  storyAutoplay = false
  storiesNightModeIndex = 0
  storyTime = 0
  nightMode_resume()
end

local function nightMode_next()
  storiesNightModeIndex = storiesNightModeIndex + 1
  if nightMode_count() > storiesNightModeIndex then
    storyTime = 0
    nightMode_play()
  else
    storiesNightModePlaying = false
    storyShowTimeline = false
    callback_stories_audio_hook = nil
    C.autosleep_unlock(5, 5) -- fin de la liste : extinction 5 s plus tard
  end
end

-- Inventaire ------------------------------------------------------------------------
local function inventoryItem(i)
  return json.at(json.get(storyJson, "inventory"), i)
end

local function inventory_screenDraw()
  local itemsDisplayCount = 0
  for i = 0, storyInventoryCountLength - 1 do
    if storyInventoryCount[i] > 0 and json.num(inventoryItem(i), "display") < 2 then
      itemsDisplayCount = itemsDisplayCount + 1
    end
  end
  if itemsDisplayCount == 0 then return end

  V.screenAddImage(SYSTEM_RESOURCES, "storytellerInventoryBg.png", 0, 384, 640)
  if itemsDisplayCount > 8 then itemsDisplayCount = 8 end

  local itemWidth = 80
  local width = itemsDisplayCount * itemWidth
  local x = 320 + math.floor(width / 2)
  local y = 400
  local storyPath = STORIES_RESOURCES .. storiesList[storyIndex] .. "/images/"

  for i = 0, storyInventoryCountLength - 1 do
    if storyInventoryCount[i] > 0 then
      local item = inventoryItem(i)
      local display = json.num(item, "display")
      if display ~= 2 then
        local maxNumber = json.num(item, "maxNumber")
        local xItem = x - itemsDisplayCount * itemWidth
        V.screenAddImage(storyPath, json.getString(item, "image"), xItem, y, itemWidth)
        if display == 0 then
          if maxNumber > 1 then
            V.screenWriteFont(tostring(storyInventoryCount[i]), C.fontBold24, C.colorWhite,
              xItem + itemWidth - 2, y + itemWidth - 27, V.ALIGN_RIGHT)
          end
        elseif display == 1 then
          V.drawRectangle(xItem + 4, y + 73, 72, 3, 75, 75, 75)
          if maxNumber ~= 0 then
            V.drawRectangle(xItem + 4, y + 73, math.floor(storyInventoryCount[i] * 72 / maxNumber), 3, 230, 230, 230)
          end
          V.screenAddImage(SYSTEM_RESOURCES, "storytellerInventoryBar.png", xItem + 2, y + 71, 76)
        end
        itemsDisplayCount = itemsDisplayCount - 1
        if itemsDisplayCount == 0 then break end
      end
    end
  end
end

local function inventory_defaultValue()
  for i = 0, storyInventoryCountLength - 1 do
    storyInventoryCount[i] = json.num(inventoryItem(i), "initialNumber")
  end
end

local function trunc(x) if x >= 0 then return math.floor(x) else return math.ceil(x) end end

local function inventory_updateGetValue(t, number, itemNumber, maxNumber)
  if t == 0 then itemNumber = itemNumber + number
  elseif t == 1 then itemNumber = itemNumber - number
  elseif t == 2 then itemNumber = number
  elseif t == 3 then itemNumber = itemNumber * number
  elseif t == 4 then if number ~= 0 then itemNumber = trunc(itemNumber / number) end
  elseif t == 5 then if number ~= 0 then itemNumber = math.fmod(itemNumber, number) end
  end
  if itemNumber > maxNumber then return maxNumber end
  if itemNumber < 0 then return 0 end
  return itemNumber
end

local function inventory_update_getNumber(updateItem)
  local number = json.getInt(updateItem, "number")
  if number ~= nil then return number end
  local item = json.getInt(updateItem, "assignItem")
  if item ~= nil then return storyInventoryCount[item] or 0 end
  if json.getBool(updateItem, "playingTime") then return getPlayingTime() end
  return 0
end

local function inventory_update(node)
  if json.isTrue(json.get(node, "inventoryReset")) then inventory_defaultValue() end
  local updateItems = json.get(node, "items")
  if json.isArray(updateItems) and json.size(updateItems) > 0 then
    for i = 0, json.size(updateItems) - 1 do
      local u = json.at(updateItems, i)
      local index = json.getInt(u, "item") or 0
      local t = json.getInt(u, "type") or 0
      if storyInventoryCount[index] ~= nil then
        storyInventoryCount[index] = inventory_updateGetValue(t, inventory_update_getNumber(u),
          storyInventoryCount[index], json.num(inventoryItem(index), "maxNumber"))
      end
    end
  end
end

local function inventory_test(comparator, conditionNumber, itemNumber)
  if comparator == 0 then return itemNumber < conditionNumber
  elseif comparator == 1 then return itemNumber <= conditionNumber
  elseif comparator == 2 then return itemNumber == conditionNumber
  elseif comparator == 3 then return itemNumber > conditionNumber
  elseif comparator == 4 then return itemNumber >= conditionNumber
  elseif comparator == 5 then return itemNumber ~= conditionNumber
  end
  return false
end

local function inventory_testNode_getNumber(condition)
  local number = json.getInt(condition, "number")
  if number ~= nil then return number end
  local item = json.getInt(condition, "compareItem")
  if item ~= nil then return storyInventoryCount[item] or 0 end
  return 0
end

local function inventory_testNode(node)
  local conditions = json.get(node, "conditions")
  if not json.isArray(conditions) or json.size(conditions) == 0 then return true end
  for i = 0, json.size(conditions) - 1 do
    local c = json.at(conditions, i)
    local index = json.getInt(c, "item") or 0
    local comparator = json.getInt(c, "comparator") or 0
    if not inventory_test(comparator, inventory_testNode_getNumber(c), storyInventoryCount[index] or 0) then
      return false
    end
  end
  return true
end

-- Ligne de temps --------------------------------------------------------------------
local function mmss(t) return string.format("%d:%02d", math.floor(t / 60), t % 60) end

local function drawTimeline(forceDraw)
  local storyPosition = math.floor(audio.getPosition())
  if not forceDraw and storyDrawTimelineTime == storyPosition then return end
  storyDrawTimelineTime = storyPosition
  local storyDuration = math.floor(audio.getDuration())

  V.screenBlack()
  if storyDuration > 0 then
    V.drawRectangle(80, 217, math.floor((storyPosition / storyDuration) * 479.0), 19, 255, 186, 0)
  end
  V.screenAddImage(SYSTEM_RESOURCES, "storytellerStoryPlayer.png", 61, 203, 518)
  if audio.isPaused() then
    V.screenAddImage(SYSTEM_RESOURCES, "storytellerPause.png", 308, 245, 24)
  else
    V.screenAddImage(SYSTEM_RESOURCES, "storytellerPlay.png", 308, 245, 24)
  end
  if storyOkAction then
    V.screenAddImage(SYSTEM_RESOURCES, "storytellerSkip.png", 270, 300, 101)
  end
  V.screenWriteFont(mmss(storyPosition), C.fontRegular20, C.colorWhite, 85, 244, V.ALIGN_LEFT)
  V.screenWriteFont(storyDuration > 0 and mmss(storyDuration) or "-:--", C.fontRegular20, C.colorWhite, 554, 244, V.ALIGN_RIGHT)
  if storiesNightModePlaying then
    V.screenWriteFont(string.format("%d / %d", storiesNightModeIndex + 1, nightMode_count()),
      C.fontRegular20, C.colorWhite, 298, 244, V.ALIGN_RIGHT)
  end
  inventory_screenDraw()
  V.applyToVideo()
end

local function screenUpdate()
  if not C.display_enabled or not storyShowTimeline then return end
  local cTime = C.get_time()
  if cTime ~= storyScreenUpdateTime then
    storyScreenUpdateTime = cTime
    if not C.overlayActive() and cTime > storyScreenEnableEndTime then
      V.screenBlack()
      V.applyToVideo()
      C.display_setScreen(false)
      return
    end
  end
  drawTimeline(false)
end

local function showTimeline()
  if storyShowTimeline then
    storyScreenEnableEndTime = C.get_time() + 5
    C.display_setScreen(true)
    drawTimeline(true)
  end
end

-- Lecture du graphe de l'histoire ----------------------------------------------------
local function getStage()
  local stages = json.get(storyJson, "stages")
  if stages == nil then return nil end
  return json.get(stages, storyStageKey)
end

local function getAction()
  if storyActionKey == "" then return nil end
  local actions = json.get(storyJson, "actions")
  if actions == nil then return nil end
  return json.get(actions, storyActionKey)
end

local function readStage()
  local stageNode = getStage()
  if stageNode == nil then return end

  if hasInventory then inventory_update(stageNode) end

  local controlJson = json.get(stageNode, "control")
  storyAutoplay = json.isTrue(json.get(controlJson, "autoplay"))
  storyOkAction = true
  storyShowTimeline = false
  callback_stories_audio_hook = nil

  local audioName = json.getString(stageNode, "audio")
  local isAudioDefined = audioName ~= nil

  if not isAudioDefined and storyAutoplay then
    audio.free_music()
    storyOkAction = false
    storyScreenEnabled = false
    if storiesNightModeEnabled then storiesNightModeCurrentAudio = "" end
    callback_stories_autoplay()
    return
  end

  local imageName = json.getString(stageNode, "image")
  local isImageDefined = imageName ~= nil

  local story_audio_path = STORIES_RESOURCES .. storiesList[storyIndex] .. "/audios/"
  local story_image_path = STORIES_RESOURCES .. storiesList[storyIndex] .. "/images/"

  if isAudioDefined then
    audio.play(story_audio_path, audioName, storyTime, not isImageDefined)
    if storyAutoplay then
      callback_stories_audio_hook = callback_stories_autoplay
      storyOkAction = json.isTrue(json.get(controlJson, "ok"))
      C.autosleep_lock()
    else
      stories_autosleep_unlock()
    end
  else
    audio.free_music()
    stories_autosleep_unlock()
  end

  if isImageDefined then
    C.display_setScreen(true)
    storyScreenEnabled = true
    V.screenBlack()
    V.screenAddImage(story_image_path, imageName, 0, 0, 640)
    if hasInventory then inventory_screenDraw() end
    if storiesNightModeEnabled then
      storiesNightModeCurrentAudio = ""
      nightMode_screenDisplayCount()
    end
    V.applyToVideo()
  else
    storyScreenEnabled = false
    if storiesNightModeEnabled and storyAutoplay and not storyOkAction then
      storiesNightModeCurrentAudio = story_audio_path .. audioName
      C.display_setScreen(true)
      V.screenBlack()
      V.screenAddImage(SYSTEM_RESOURCES, "storytellerNightMode.png", 0, 0, 640)
      nightMode_screenDisplayCount()
      V.applyToVideo()
    else
      storyShowTimeline = not C.params.storyDisableTimeline
      V.displayBlackScreen()
      if not C.overlayActive() then C.display_setScreen(false) end
      if storiesNightModeEnabled then storiesNightModeCurrentAudio = "" end
    end
  end
end

local function readAction(direction)
  if storiesCount == 0 then return end
  storyActionOptionIndex = storyActionOptionIndex + direction
  if direction == 0 then direction = 1 end

  local nodeAction = getAction()
  if nodeAction == nil then return end

  local initialOptionIndex = -1
  while true do
    if storyActionOptionIndex < 0 then
      storyActionOptionIndex = storyActionOptionsCount - 1
    elseif storyActionOptionIndex >= storyActionOptionsCount then
      storyActionOptionIndex = 0
    end
    if initialOptionIndex == storyActionOptionIndex then
      return callback_stories_reset()
    end
    if initialOptionIndex == -1 then initialOptionIndex = storyActionOptionIndex end

    local option = json.at(nodeAction, storyActionOptionIndex)
    if option == nil or (hasInventory and not inventory_testNode(option)) then
      storyActionOptionIndex = storyActionOptionIndex + direction
    else
      storyStageKey = json.getString(option, "stage") or storyStageKey
      readStage()
      return
    end
  end
end

local function loadAction()
  local nodeAction = getAction()
  if nodeAction == nil or not json.isArray(nodeAction) then return callback_stories_reset() end

  storyActionOptionsCount = json.size(nodeAction)
  if storyActionOptionsCount == 0 then return callback_stories_reset() end

  if storyActionOptionIndex < 0 then
    if not hasInventory then
      storyActionOptionIndex = love.math.random(0, storyActionOptionsCount - 1)
    else
      local idx = {}
      for i = 0, storyActionOptionsCount - 1 do
        if inventory_testNode(json.at(nodeAction, i)) then idx[#idx + 1] = i end
      end
      if #idx == 0 then return callback_stories_reset() end
      storyActionOptionIndex = idx[love.math.random(1, #idx)]
    end
  end

  if storyActionOptionIndex >= storyActionOptionsCount then
    storyActionOptionIndex = storyActionOptionsCount - 1
  end

  readAction(0)
end

local function loadAction_keyIndex(transition)
  storyTime = 0
  storyActionKey = json.getString(transition, "action") or storyActionKey
  local index = json.getInt(transition, "index")
  if index ~= nil then storyActionOptionIndex = index; return end
  local item = json.getInt(transition, "indexItem")
  if item ~= nil then
    storyActionOptionIndex = (storyInventoryCount and storyInventoryCount[item]) or 0
    return
  end
  storyActionOptionIndex = 0
end

local function load()
  if storiesCount == 0 or storiesCount <= storyIndex then return end

  loadCurrentSession()

  storyJson = C.fs.loadJson(STORIES_RESOURCES .. storiesList[storyIndex] .. "/nodes.json")
  if storyJson == nil then return end

  local inventory = json.get(storyJson, "inventory")
  hasInventory = json.isArray(inventory) and json.size(inventory) > 0
  if hasInventory then
    local inventorySize = json.size(inventory)
    if storyInventoryCount ~= nil and storyInventoryCountLength ~= inventorySize then
      storyInventoryCount = nil
      storyInventoryCountLength = -1
    end
    if storyInventoryCount == nil then
      storyInventoryCountLength = inventorySize
      storyInventoryCount = {}
      inventory_defaultValue()
    end
  end

  if storyActionKey == "" then
    initPlayingTime()
    local startTransition = json.get(storyJson, "startAction")
    if startTransition == nil then return callback_stories_reset() end
    loadAction_keyIndex(startTransition)
  end

  loadAction()
end

-- Choix de l'histoire ---------------------------------------------------------------
local function title_single()
  local story_path = STORIES_RESOURCES .. storiesList[storyIndex] .. "/"
  V.drawRectangle(0, 0, 640, 480, 0, 0, 0)
  V.screenAddImage(story_path, "title.png", 0, 0, 640)
  if not storiesNightModeEnabled and storiesHasSaveList[storyIndex] then
    V.screenAddImage(SYSTEM_RESOURCES, "storytellerResumeStory.png", 15, 15, 48)
  end
  V.applyToVideo()
end

local function title_tile(base, pos)
  local sIndex = base + pos
  if sIndex >= storiesCount then return end
  local x = 33 + (pos % 3) * 201
  local y = 28 + math.floor(pos / 3) * 148
  if storyIndex == sIndex then
    V.drawRectangle(x - 5, y - 5, 181, 138, 255, 186, 0)
  end
  local story_path = STORIES_RESOURCES .. storiesList[sIndex] .. "/"
  V.drawRectangle(x, y, 171, 128, 0, 0, 0)
  V.screenAddImage(story_path, "title.png", x, y, 171)
  if not storiesNightModeEnabled and storiesHasSaveList[sIndex] then
    V.screenAddImage(SYSTEM_RESOURCES, "storytellerResumeStory.png", x + 5, y + 5, 48)
  end
end

local function title_tiles()
  local baseIndex = math.floor(storyIndex / 9) * 9
  V.screenAddImage(SYSTEM_RESOURCES, "storiesTiles.png", 0, 0, 640)
  for p = 0, 8 do title_tile(baseIndex, p) end
  if storiesNightModeEnabled then nightMode_screenDisplayCount() end
  V.screenWriteFont(string.format("%d / %d", storyIndex + 1, storiesCount), C.fontRegular16, C.colorWhite60, 606, 456, V.ALIGN_RIGHT)
  V.applyToVideo()
end

local function title()
  if storiesCount == 0 then
    V.displayImage(SYSTEM_RESOURCES, "noStory.png")
    return
  end
  if storyIndex < 0 then storyIndex = storiesCount - 1
  elseif storyIndex >= storiesCount then storyIndex = 0 end

  stories_autosleep_unlock()
  storyAutoplay = false
  storyTime = 0

  audio.play(STORIES_RESOURCES .. storiesList[storyIndex] .. "/", "title.mp3", storyTime, false)
  callback_stories_audio_hook = nil

  storyScreenEnabled = true
  C.display_setScreen(storyScreenEnabled)
  if storiesDiplayMode == DISPLAY_SINGLE then title_single() else title_tiles() end
end

local function transition(name)
  if storiesCount == 0 then return end
  local stageNode = getStage()
  if stageNode == nil then return callback_stories_reset() end
  local transitionNode = json.get(stageNode, name)
  if transitionNode == nil then return callback_stories_reset() end
  callback_stories_audio_hook = nil
  loadAction_keyIndex(transitionNode)
  loadAction()
end

local function setMode(dm)
  storiesDiplayMode = dm
  if storiesDiplayMode == DISPLAY_SINGLE then title_single() else title_tiles() end
end

local function changeTitle(direction)
  if not storyAutoplay and storyActionKey == "" then
    storyIndex = storyIndex + direction
    title()
  end
end

function S.up()
  if storiesCount == 0 then return end
  if storyAutoplay or storiesNightModePlaying then
    showTimeline()
  elseif storyActionKey == "" and storiesDiplayMode == DISPLAY_TILES then
    changeTitle(-3)
  end
end

function S.down()
  if storiesCount == 0 then return end
  if storyAutoplay or storiesNightModePlaying then
    showTimeline()
  elseif storyActionKey == "" and storiesDiplayMode == DISPLAY_TILES then
    changeTitle(3)
  end
end

local function rewind(t)
  storyTime = audio.getPosition() + t
  local audioDuration = audio.getDuration()
  if audioDuration > 0 and storyTime >= audioDuration then
    if callback_stories_audio_hook ~= nil then
      callback_stories_audio_hook()
      return
    end
    storyTime = audioDuration - 1.0
  elseif storyTime < 0 then
    storyTime = 0
  end
  audio.setPosition(storyTime)
end

function S.next()
  if storiesCount == 0 then return end
  if storyAutoplay or storiesNightModePlaying then
    rewind(10)
    showTimeline()
  elseif storyActionKey == "" then
    changeTitle(1)
  else
    readAction(1)
  end
end

function S.previous()
  if storiesCount == 0 then return end
  if storyAutoplay or storiesNightModePlaying then
    rewind(-10)
    showTimeline()
  elseif storyActionKey == "" then
    changeTitle(-1)
  else
    readAction(-1)
  end
end

function S.forceRefreshScreen()
  if C.overlayActive() then
    C.display_setScreen(true)
  else
    C.display_setScreen(storyScreenEnabled)
  end
  V.applyToVideo()
end

function S.menu()
  if storiesCount == 0 or storiesNightModePlaying then return end
  if storyActionKey == "" then
    if storiesDiplayMode == DISPLAY_SINGLE then setMode(DISPLAY_TILES) else setMode(DISPLAY_SINGLE) end
  else
    saveCurrentSession()
    callback_stories_reset()
  end
end

function S.ok()
  if storiesCount == 0 then return end
  if storiesNightModePlaying then
    showTimeline()
    return
  end
  if storyActionKey == "" then
    load()
  elseif nightMode_isPlaylistableAudio() then
    if nightMode_addToPlaylist() then nightMode_start() else transition("home") end
  elseif storyOkAction then
    transition("ok")
  else
    showTimeline()
  end
end

local function autoplay()
  storyOkAction = true
  S.ok()
end

function S.pause()
  if storiesCount == 0 then return end
  if nightMode_isPlaylistableAudio() then
    nightMode_addToPlaylist()
    nightMode_start()
  elseif audio.isPlaying() then
    if audio.isPaused() then
      C.autosleep_lock()
      audio.resume()
    else
      stories_autosleep_unlock()
      audio.pause()
    end
    showTimeline()
  end
end

function S.home()
  if storiesCount == 0 then
    nightMode_reset()
    return true
  end
  if storyActionKey == "" or storiesNightModePlaying then
    callback_stories_audio_hook = nil
    audio.free_music()
    nightMode_reset()
    return true
  end
  transition("home")
  return false
end

function S.save()
  if storiesCount == 0 then return end
  if audio.isPlaying() and not audio.isPaused() then S.pause() end
  saveSession(C.SAVEFILE)
end

local function reset()
  callback_stories_audio_hook = nil
  storyAutoplay = false
  storyOkAction = true
  storyStageKey = ""
  storyActionKey = ""
  storyActionOptionIndex = 0
  storyTime = 0
  storyShowTimeline = false
  storyScreenUpdateTime = 0
  storyScreenEnableEndTime = 0
  storyLastPlayingTime = 0
  storyPlayingTime = 0
  if hasInventory then
    hasInventory = false
    storyInventoryCount = nil
    storyInventoryCountLength = -1
  end
  storyJson = nil
  title()
end

local function callCallback()
  if callback_stories_audio_hook ~= nil and audio.isFinished() then
    callback_stories_audio_hook()
    return true
  end
  return false
end

function S.update()
  if not callCallback() then screenUpdate() end
end

function S.init()
  if storiesList ~= nil then return title() end
  V.displayImage(SYSTEM_RESOURCES, "loadingStories.png")

  callback_stories_autoplay = autoplay
  callback_stories_reset = reset
  callback_stories_nightMode = nightMode_next

  storiesDiplayMode = C.params.storyDisplayTiles and DISPLAY_TILES or DISPLAY_SINGLE

  C.fs.mkdirs(STORIES_SAVES)

  local names = C.sort(C.fs.list(STORIES_RESOURCES, "directory"))
  storiesList, storiesHasSaveList, storiesIndexByName = {}, {}, {}
  for i, n in ipairs(names) do
    storiesList[i - 1] = n
    storiesHasSaveList[i - 1] = false
    storiesIndexByName[n] = i - 1
  end
  storiesCount = #names
  if storiesCount == 0 then return title() end

  for _, f in ipairs(C.fs.list(STORIES_SAVES, "file")) do
    local sIndex = getStoryIndex(f)
    if sIndex ~= -1 then storiesHasSaveList[sIndex] = true end
  end

  if loadSession(C.SAVEFILE) then
    if storiesNightModeEnabled then
      return nightMode_resume()
    elseif storyActionKey ~= "" then
      return load()
    end
  end
  title()
end

function S.initNightMode()
  storiesNightModeEnabled = true
  S.init()
end

return S
