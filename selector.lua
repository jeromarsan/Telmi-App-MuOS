-- Écran d'accueil Telmi : Histoires / Musique / Mode nuit (portage de app_selector.h)
local C = require("core")
local json = require("json")
local Stories = require("stories")
local Music = require("music")
local V = C.video

local A = {}
local APP_COUNT, APP_STORIES, APP_MUSIC, APP_NIGHTMODE = 3, 0, 1, 2
local appImages = { [0] = "selectStories.png", "selectMusic.png", "selectNightMode.png" }

local appIndex = 0
local appOpened = false

local function validAppIndex(current, direction)
  local n = current + direction
  if n >= APP_COUNT then return validAppIndex(-1 * direction, direction) end
  if n < 0 then return validAppIndex(APP_COUNT - 1 - direction, direction) end
  if n == APP_NIGHTMODE and C.params.storyDisableNightMode then return validAppIndex(n, direction) end
  return n
end

local function refreshScreen()
  V.displayImage(C.RES, appImages[appIndex])
  C.display_setScreen(true)
  C.autosleep_unlock(C.params.screenOnInactivityTime, C.params.screenOffInactivityTime)
end

local function current()
  if appIndex == APP_MUSIC then return Music end
  return Stories
end

function A.update() if appOpened then current().update() end end

function A.forceRefreshScreen()
  if appOpened then current().forceRefreshScreen() else refreshScreen() end
end

function A.menu() if appOpened then current().menu() end end

function A.previous()
  if appOpened then current().previous()
  else appIndex = validAppIndex(appIndex, -1); refreshScreen() end
end

function A.next()
  if appOpened then current().next()
  else appIndex = validAppIndex(appIndex, 1); refreshScreen() end
end

function A.up() if appOpened then current().up() end end
function A.down() if appOpened then current().down() end end
function A.pause() if appOpened then current().pause() end end

function A.ok()
  if appOpened then
    current().ok()
  else
    appOpened = true
    if appIndex == APP_STORIES then Stories.init()
    elseif appIndex == APP_MUSIC then Music.init()
    elseif appIndex == APP_NIGHTMODE then Stories.initNightMode() end
  end
end

function A.home()
  if appOpened then
    if current().home() then
      appOpened = false
      refreshScreen()
    end
  end
end

function A.save() if appOpened then current().save() end end

function A.init()
  local saved = C.fs.loadJson(C.SAVEFILE)
  local a = json.getInt(saved, "app")
  if a ~= nil and a >= 0 and a < APP_COUNT then
    appIndex = a
    A.ok()
  else
    refreshScreen()
  end
end

return A
