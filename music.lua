-- Lecteur de musique Telmi (portage de music_player.h)
-- Fichiers attendus dans Music/ : "Artiste_Album_NumPiste_Titre.mp3" + ".png" (pochette)
local C = require("core")
local json = require("json")
local V, audio = C.video, C.audio

local M = {}
local APP_MUSIC = 1
local MODE_PLAYER, MODE_ALBUM = 0, 1
local REPEAT_ALL, REPEAT_SHUFFLE, REPEAT_ALBUM, REPEAT_TITLE = 0, 1, 2, 3

local SYSTEM_RESOURCES = C.RES
local MUSICPLAYER_RESOURCES = C.MUSIC

local musicPlayerMode = MODE_PLAYER
local tracks = nil -- indices 0..n-1
local tracksCount = 0
local trackIndex = 0
local trackPosition = 0
local albumsIndex = {} -- indices 0..n-1
local albumsCount = 0
local albumIndex = 0
local repeatMode = REPEAT_ALL
local drawInterfaceTime = 0
local screenUpdateTime = 0
local lastActivity = 0
local callback_autoplay = nil

local function saveSession()
  C.file_save(C.SAVEFILE, string.format('{"app":%d, "musicIndex":%d, "musicPosition":%f}',
    APP_MUSIC, trackIndex, audio.getPosition()))
end

local function loadSession()
  local saved = C.fs.loadJson(C.SAVEFILE)
  if type(saved) == "table" and json.getInt(saved, "app") == APP_MUSIC then
    trackIndex = json.getInt(saved, "musicIndex") or trackIndex
    trackPosition = json.getNumber(saved, "musicPosition") or trackPosition
    C.fs.remove(C.SAVEFILE)
  end
end

local function autosleep_unlock()
  C.autosleep_unlock(C.params.screenOnInactivityTime, C.params.screenOffInactivityTime)
end

local function autosleep_lock()
  C.autosleep_unlock(C.params.musicInactivityTime, C.params.musicInactivityTime)
end

-- découpe comme strtok(nom, "_") : les champs vides sont ignorés
local function parseName(fileName)
  local imageName = fileName:sub(1, -5)
  local parts = {}
  for p in imageName:gmatch("[^_]+") do parts[#parts + 1] = p end
  local artist, album, track, titleText = parts[1] or "", parts[2] or "", parts[3] or "", parts[4] or ""
  return imageName, track .. ". " .. titleText, artist .. " - " .. album
end

local function drawSideMusic(index, top)
  local mIndex = trackIndex + index
  if mIndex < 0 then mIndex = tracksCount + mIndex
  elseif mIndex >= tracksCount then mIndex = mIndex - tracksCount end
  if mIndex < 0 or mIndex >= tracksCount then return end

  local imageName, writeTitle, writeArtist = parseName(tracks[mIndex])
  V.screenAddImage(MUSICPLAYER_RESOURCES, imageName .. ".png", 55, top + 9, 64)
  V.screenWriteFont(writeTitle, C.fontBold20, C.colorWhite60, 150, top + 17, V.ALIGN_LEFT)
  V.screenWriteFont(writeArtist, C.fontRegular16, C.colorWhite60, 150, top + 43, V.ALIGN_LEFT)
end

local function mmss(t) return string.format("%d:%02d", math.floor(t / 60), t % 60) end

local function drawInterface(forceDraw)
  local musicPosition = math.floor(audio.getPosition())
  if not forceDraw and musicPosition == drawInterfaceTime then return end
  drawInterfaceTime = musicPosition

  local musicDuration = math.floor(audio.getDuration())
  local imageName, writeTitle, writeArtist = parseName(tracks[trackIndex])

  V.screenBlack()
  if musicDuration > 0 then
    V.drawRectangle(185, 258, math.floor(musicPosition * 422.0 / musicDuration), 12, 255, 186, 0)
  end
  V.screenAddImage(SYSTEM_RESOURCES, "musicPlayer.png", 0, 0, 640)
  V.screenAddImage(MUSICPLAYER_RESOURCES, imageName .. ".png", 24, 176, 128)
  V.screenWriteFont(writeTitle, C.fontBold24, C.colorWhite, 185, 190, V.ALIGN_LEFT)
  V.screenWriteFont(writeArtist, C.fontRegular20, C.colorWhite, 185, 222, V.ALIGN_LEFT)
  V.screenWriteFont(mmss(musicPosition), C.fontRegular18, C.colorWhite, 185, 275, V.ALIGN_LEFT)
  V.screenWriteFont(musicDuration > 0 and mmss(musicDuration) or "-:--", C.fontRegular18, C.colorWhite, 605, 275, V.ALIGN_RIGHT)
  if not C.params.musicDisableRepeatModes then
    V.screenAddImage(SYSTEM_RESOURCES, "musicPlayerRepeatMode" .. repeatMode .. ".png", 332, 274, 128)
  end
  drawSideMusic(-2, 0)
  drawSideMusic(-1, 83)
  drawSideMusic(1, 314)
  drawSideMusic(2, 397)
  V.applyToVideo()
end

local function drawAlbum(baseIndex, pos)
  local aIndex = baseIndex + pos
  if aIndex >= albumsCount then return end
  local mIndex = albumsIndex[aIndex]
  local imageName = tracks[mIndex]:sub(1, -5)
  local x = 51 + (pos % 3) * 205
  local y = 28 + math.floor(pos / 3) * 148
  if albumIndex == aIndex then
    V.drawRectangle(x - 5, y - 5, 138, 138, 255, 186, 0)
  end
  V.screenAddImage(MUSICPLAYER_RESOURCES, imageName .. ".png", x, y, 128)
end

local function albumDraw()
  if albumIndex >= albumsCount then albumIndex = 0
  elseif albumIndex < 0 then albumIndex = albumsCount - 1 end
  local baseIndex = math.floor(albumIndex / 9) * 9
  V.screenAddImage(SYSTEM_RESOURCES, "musicPlayerAlbums.png", 0, 0, 640)
  for p = 0, 8 do drawAlbum(baseIndex, p) end
  V.screenWriteFont(string.format("%d / %d", albumIndex + 1, albumsCount), C.fontRegular16, C.colorWhite60, 590, 456, V.ALIGN_RIGHT)
  V.applyToVideo()
end

local function getCurrentAlbumIndex()
  local index = albumsCount - 1
  for i = 1, albumsCount - 1 do
    if trackIndex < albumsIndex[i] then
      index = i - 1
      break
    end
  end
  return index
end

local function screenUpdate(forceDraw)
  if not C.display_enabled or tracks == nil or tracksCount == 0 then return end
  local ts = C.get_time()
  if screenUpdateTime ~= ts then
    screenUpdateTime = ts
    local inactivityTime = ts - lastActivity
    if inactivityTime > 10 and not C.overlayActive() then
      V.displayBlackScreen()
      C.display_setScreen(false)
      return
    end
  end
  if musicPlayerMode == MODE_PLAYER then drawInterface(forceDraw) end
end

local function callCallback()
  if callback_autoplay ~= nil and audio.isFinished() then
    callback_autoplay()
    return true
  end
  return false
end

function M.update()
  if not callCallback() then screenUpdate(false) end
end

local function screenActivate()
  lastActivity = C.get_time()
  C.display_setScreen(true)
end

local function setMode(mode)
  musicPlayerMode = mode
  if musicPlayerMode == MODE_PLAYER then
    screenUpdate(true)
  else
    albumIndex = getCurrentAlbumIndex()
    albumDraw()
  end
end

local function load()
  if tracksCount == 0 then
    V.displayImage(SYSTEM_RESOURCES, "noMusic.png")
    return
  end
  if trackIndex < 0 then trackIndex = tracksCount - 1
  elseif trackIndex >= tracksCount then trackIndex = 0 end

  local isPaused = audio.isPlaying() and audio.isPaused()
  audio.play(MUSICPLAYER_RESOURCES, tracks[trackIndex], trackPosition, true)
  if isPaused then audio.pause() end

  if C.display_enabled and musicPlayerMode == MODE_PLAYER then drawInterface(true) end
end

local function changeAlbum(direction)
  albumIndex = albumIndex + direction
  albumDraw()
end

local function changeSong(direction)
  if tracksCount == 0 then return end
  trackPosition = 0.0
  if repeatMode == REPEAT_ALL then
    trackIndex = trackIndex + direction
  elseif repeatMode == REPEAT_SHUFFLE then
    trackIndex = love.math.random(0, tracksCount - 1)
  elseif repeatMode == REPEAT_ALBUM then
    local oldAlbumIndex = getCurrentAlbumIndex()
    trackIndex = trackIndex + direction
    if trackIndex < 0 then
      if albumsCount > 1 then trackIndex = albumsIndex[1] - 1 else trackIndex = tracksCount - 1 end
    elseif trackIndex >= tracksCount then
      trackIndex = albumsIndex[albumsCount - 1]
    else
      local newAlbumIndex = getCurrentAlbumIndex()
      if oldAlbumIndex > newAlbumIndex then
        local nextAlbumIndex = oldAlbumIndex + 1
        if nextAlbumIndex >= albumsCount then trackIndex = tracksCount - 1
        else trackIndex = albumsIndex[nextAlbumIndex] - 1 end
      elseif oldAlbumIndex < newAlbumIndex then
        trackIndex = albumsIndex[oldAlbumIndex]
      end
    end
  end
  -- REPEAT_TITLE : même morceau
  load()
end

local function nextSong() changeSong(1) end

function M.up()
  if tracksCount == 0 then return end
  screenActivate()
  if musicPlayerMode == MODE_PLAYER then changeSong(-1) else changeAlbum(-3) end
end

function M.down()
  if tracksCount == 0 then return end
  screenActivate()
  if musicPlayerMode == MODE_PLAYER then nextSong() else changeAlbum(3) end
end

local function rewind(t)
  local musicDuration = audio.getDuration()
  trackPosition = audio.getPosition() + t
  if trackPosition < 0 then
    trackPosition = 0.0
  elseif musicDuration > 0 and trackPosition >= musicDuration then
    callback_autoplay()
    return
  end
  audio.setPosition(trackPosition)
  drawInterface(true)
end

function M.next()
  if tracksCount == 0 then return end
  screenActivate()
  if musicPlayerMode == MODE_PLAYER then rewind(10) else changeAlbum(1) end
end

function M.previous()
  if tracksCount == 0 then return end
  screenActivate()
  if musicPlayerMode == MODE_PLAYER then rewind(-10) else changeAlbum(-1) end
end

function M.ok()
  if tracksCount == 0 then return end
  if not C.display_enabled then
    screenActivate()
    return
  end
  if musicPlayerMode == MODE_PLAYER then
    if not C.params.musicDisableRepeatModes then
      repeatMode = repeatMode + 1
      if repeatMode > REPEAT_TITLE then repeatMode = REPEAT_ALL end
      drawInterface(true)
    end
  else
    musicPlayerMode = MODE_PLAYER
    trackPosition = 0.0
    trackIndex = albumsIndex[albumIndex]
    load()
  end
end

function M.pause()
  if tracksCount == 0 then return end
  screenActivate()
  if audio.isPlaying() then
    if audio.isPaused() then
      audio.resume()
      autosleep_lock()
    else
      audio.pause()
      trackPosition = audio.getPosition()
      autosleep_unlock()
    end
  end
end

function M.home()
  if tracksCount == 0 then return true end
  if musicPlayerMode == MODE_PLAYER then
    if audio.isPlaying() and not audio.isPaused() then trackPosition = audio.getPosition() end
    audio.free_music()
    return true
  end
  screenActivate()
  setMode(MODE_PLAYER)
  return false
end

function M.forceRefreshScreen()
  if not C.display_enabled and C.overlayActive() then C.display_setScreen(true) end
  if tracksCount == 0 then
    V.applyToVideo()
    return
  end
  setMode(musicPlayerMode)
end

function M.menu()
  if tracksCount == 0 then return end
  screenActivate()
  if musicPlayerMode == MODE_PLAYER then setMode(MODE_ALBUM) else setMode(MODE_PLAYER) end
end

function M.save()
  if tracksCount == 0 then return end
  if audio.isPlaying() and not audio.isPaused() then M.pause() end
  saveSession()
end

local function albumKey(fileName)
  local a = fileName:find("_", 1, true)
  local b = a and fileName:find("_", a + 1, true)
  if not b then return fileName end
  return fileName:sub(1, b - 1)
end

function M.init()
  autosleep_lock()
  screenActivate()

  if tracks ~= nil then return load() end

  V.displayImage(SYSTEM_RESOURCES, "loadingMusic.png")
  callback_autoplay = nextSong

  local names = {}
  for _, n in ipairs(C.fs.list(MUSICPLAYER_RESOURCES, "file")) do
    if n:sub(-4) == ".mp3" then names[#names + 1] = n end
  end
  C.sort(names)
  tracks = {}
  tracksCount = #names
  for i, n in ipairs(names) do tracks[i - 1] = n end
  if tracksCount == 0 then return load() end

  albumsIndex, albumsCount = {}, 0
  local lastAlbum = nil
  for i = 0, tracksCount - 1 do
    local k = albumKey(tracks[i])
    if k ~= lastAlbum then
      lastAlbum = k
      albumsIndex[albumsCount] = i
      albumsCount = albumsCount + 1
    end
  end

  loadSession()
  load()
end

return M
