-- Couche système de Telmi pour muOS / LÖVE.
-- Remplace les fichiers C d'origine : app_parameters, app_lock, app_volume,
-- app_brightness, app_autosleep, app_battery, time_helper, sdl_helper (vidéo)
-- et mp3_reader (audio). Les noms et comportements suivent le code officiel.
local json = require("json")
local lg = love.graphics

local C = {}

-- Chemins ---------------------------------------------------------------
local function trimSlash(p) return (p:gsub("[/\\]+$", "")) end
C.SRC = trimSlash((love.filesystem.getRealDirectory("main.lua") or love.filesystem.getSource()):gsub("\\", "/"))
C.ROOT = trimSlash(((os.getenv("TELMI_ROOT") ~= nil and os.getenv("TELMI_ROOT") ~= "") and os.getenv("TELMI_ROOT") or C.SRC):gsub("\\", "/"))
C.RES = C.SRC .. "/res/"
C.STORIES = C.ROOT .. "/Stories/"
C.STORIES_SAVES = C.ROOT .. "/Saves/Stories/"
C.MUSIC = C.ROOT .. "/Music/"
C.SAVEFILE = C.ROOT .. "/Saves/.storytellerState"
C.PARAMETERS = C.ROOT .. "/Saves/.parameters"
C.IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- Fichiers --------------------------------------------------------------
-- Les fichiers situés dans le dossier de l'appli passent par love.filesystem
-- (lecture audio en continu depuis la carte SD), les autres par io.
local fs = {}
C.fs = fs

local function rel(p)
  local pre = C.SRC .. "/"
  if p:sub(1, #pre) == pre then return p:sub(#pre + 1) end
  return nil
end

function fs.read(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

function fs.exists(p)
  local r = rel(p)
  if r then return love.filesystem.getInfo(r) ~= nil end
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

-- liste les entrées d'un dossier ; kind = "directory" ou "file"
function fs.list(dir, kind)
  dir = trimSlash(dir)
  local out = {}
  local r = rel(dir .. "/")
  if r then
    r = trimSlash(r)
    for _, name in ipairs(love.filesystem.getDirectoryItems(r)) do
      local info = love.filesystem.getInfo(r .. "/" .. name)
      if info and info.type == kind then out[#out + 1] = name end
    end
    return out
  end
  local t = kind == "directory" and "d" or "f"
  local q = dir:gsub("'", "'\\''")
  local cmd = "cd '" .. q .. "' 2>/dev/null && for f in * .[!.]* ..?*; do [ -" .. t .. ' "$f" ] && echo "$f"; done'
  local p = io.popen(cmd)
  if p then
    for line in p:lines() do
      if line ~= "" then out[#out + 1] = line end
    end
    p:close()
  end
  print("[telmi] " .. dir .. " : " .. #out .. " " .. (kind == "directory" and "dossier(s)" or "fichier(s)"))
  return out
end

function fs.write(p, s)
  local f = io.open(p, "w")
  if not f then print("[telmi] ecriture impossible : " .. p); return false end
  f:write(s)
  f:flush()
  f:close()
  return true
end

function fs.remove(p) os.remove(p) end

function fs.mkdirs(p)
  p = trimSlash(p)
  if C.IS_WINDOWS then
    os.execute('mkdir "' .. p:gsub("/", "\\") .. '" >nul 2>nul')
  else
    os.execute('mkdir -p "' .. p .. '" 2>/dev/null')
  end
end

function fs.fileData(p)
  local r = rel(p)
  if r then
    local ok, fd = pcall(love.filesystem.newFileData, r)
    if ok then return fd end
    return nil
  end
  local d = fs.read(p)
  if not d then return nil end
  local ok, fd = pcall(love.filesystem.newFileData, d, p:match("[^/]+$") or "file")
  if ok then return fd end
  return nil
end

function fs.loadJson(p) return json.decode(fs.read(p)) end

-- comparaison octet par octet (strcmp) pour trier comme Telmi
function C.sort(list)
  table.sort(list, function(a, b)
    local n = math.min(#a, #b)
    for i = 1, n do
      local x, y = a:byte(i), b:byte(i)
      if x ~= y then return x < y end
    end
    return #a < #b
  end)
  return list
end

-- Temps -----------------------------------------------------------------
-- get_time() : secondes entières, comme dans Telmi
function C.get_time() return os.time() end

local lastWait = 0
-- time_wait() : anti-rebond de 50 ms entre deux actions
function C.time_wait()
  local t = love.timer.getTime() * 1000
  if t - lastWait > 50 then lastWait = t; return true end
  return false
end

-- Paramètres (Saves/.parameters) ---------------------------------------------
local P = {
  audioVolumeStartup = 0.3, audioVolumeMax = 0.6, systemAudioVolumeMax = 25.0,
  screenBrightnessStartup = 0.3, screenBrightnessMax = 0.6, systemScreenBrightnessMax = 10.0,
  screenOnInactivityTime = 120, screenOffInactivityTime = 300, musicInactivityTime = 3600,
  storyDisplayTiles = false, storyDisableNightMode = false, storyDisableTimeline = false,
  musicDisableRepeatModes = false,
}
C.params = P

local function round(x) return math.floor(x + 0.5) end

function C.parameters_init()
  local j = fs.loadJson(C.PARAMETERS)
  if type(j) ~= "table" then return end
  for _, k in ipairs({ "audioVolumeStartup", "audioVolumeMax", "screenBrightnessStartup", "screenBrightnessMax" }) do
    local v = json.getNumber(j, k); if v then P[k] = v end
  end
  for _, k in ipairs({ "screenOnInactivityTime", "screenOffInactivityTime", "musicInactivityTime" }) do
    local v = json.getInt(j, k); if v then P[k] = v end
  end
  for _, k in ipairs({ "storyDisplayTiles", "storyDisableNightMode", "storyDisableTimeline", "musicDisableRepeatModes" }) do
    if j[k] ~= nil and j[k] ~= json.null then P[k] = j[k] == true end
  end
end

function C.getAudioVolumeStartup() return round(P.audioVolumeStartup * P.systemAudioVolumeMax) end
function C.getAudioVolumeMax() return round(P.audioVolumeMax * P.systemAudioVolumeMax) end
function C.getSystemAudioVolumeMax() return math.floor(P.systemAudioVolumeMax) end
function C.getAudioVolumeValidation(v)
  local m = C.getAudioVolumeMax()
  return v > m and m or v
end
function C.getScreenBrightnessStartup() return round(P.screenBrightnessStartup * P.systemScreenBrightnessMax) end
function C.getScreenBrightnessMax() return round(P.screenBrightnessMax * P.systemScreenBrightnessMax) end
function C.getSystemScreenBrightnessMax() return math.floor(P.systemScreenBrightnessMax) end
function C.getScreenBrightnessValidation(b)
  local m = C.getScreenBrightnessMax()
  return b > m and m or b
end

-- Écran / luminosité (muOS : /opt/muos/script/device/bright.sh) ---------------
-- Les appels passent par un fil séparé, dans l'ordre, sans bloquer l'appli.
local BRIGHT = "/opt/muos/script/device/bright.sh"
local hasBright = (not C.IS_WINDOWS) and fs.exists(BRIGHT)
local brightMax = tonumber(os.getenv("TELMI_BRIGHT_MAX") or "") or 0
if brightMax <= 0 then
  local p = (not C.IS_WINDOWS) and io.popen("cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n 1")
  if p then brightMax = tonumber(p:read("*l") or "") or 0; p:close() end
end
if brightMax <= 0 then brightMax = 255 end
local brightThread, brightChannel
if hasBright then
  brightChannel = love.thread.getChannel("telmi_bright")
  brightThread = love.thread.newThread([[
    require("love.thread")
    local ch = love.thread.getChannel("telmi_bright")
    while true do
      local cmd = ch:demand()
      while ch:getCount() > 0 do cmd = ch:pop() end -- seule la dernière valeur compte
      if cmd == "__quit" then break end
      os.execute(cmd)
    end
  ]])
  brightThread:start()
end

C.settings = { volume = 20, brightness = 7 }
C.display_enabled = true

-- même courbe que Telmi (display_setBrightness) : 3 * exp(0.350656 * v) % de PWM
local function brightnessValue(level)
  local pct = 3.0 * math.exp(0.350656 * level) / 100
  return math.max(1, math.min(brightMax, round(brightMax * pct)))
end

local function brightSend(value)
  if not hasBright then return end
  if value <= 0 then
    brightChannel:push(BRIGHT .. " 0 >/dev/null 2>&1")
  else
    brightChannel:push(BRIGHT .. " " .. value .. " transient >/dev/null 2>&1")
  end
end

function C.display_setScreen(enabled)
  if C.display_enabled == enabled then return end
  C.display_enabled = enabled
  if enabled then brightSend(brightnessValue(C.settings.brightness)) else brightSend(0) end
  C.dirty = true
end

function C.settings_setBrightness(value)
  if value > 10 then value = 10 elseif value < 0 then value = 0 end
  C.settings.brightness = value
  if C.display_enabled then brightSend(brightnessValue(value)) end
end

-- même courbe que Telmi (setVolume) : -60 dB + 48 * log10(1 + v), plafonnée à 0 dB
local function volumeGain(v)
  if v <= 0 then return 0 end
  local base, boost = v, 0
  if base > 20 then boost = base - 20; base = 20 end
  local db = -60 + round(48 * math.log10(1 + base)) + boost
  return math.min(1, 10 ^ (db / 20))
end

function C.settings_setVolume(value)
  if value > 25 then value = 25 elseif value < 0 then value = 0 end
  local changed = C.settings.volume ~= value
  C.settings.volume = value
  love.audio.setVolume(volumeGain(value))
  return changed
end

function C.quitScreen()
  if brightChannel then brightChannel:push("__quit") end
end

-- Volume / luminosité : affichage de la barre 2 s (app_volume / app_brightness) ----
local vol = { showed = false, time = 0 }
local bri = { showed = false, time = 0 }

function C.app_volume_isShowed() return vol.showed end
local function volShow() vol.time = C.get_time() + 2; vol.showed = true; return true end
function C.app_volume_getCurrent() return C.settings.volume end
function C.app_volume_up()
  C.settings_setVolume(C.getAudioVolumeValidation(C.settings.volume + 1)); return volShow()
end
function C.app_volume_down() C.settings_setVolume(C.settings.volume - 1); return volShow() end
function C.app_volume_checkDisplay()
  if vol.showed and vol.time <= C.get_time() then vol.showed = false; return true end
  return false
end

function C.app_brightness_isShowed() return bri.showed end
local function briShow() bri.time = C.get_time() + 2; bri.showed = true; return true end
function C.app_brightness_getCurrent() return C.settings.brightness end
function C.app_brightness_up()
  C.settings_setBrightness(C.getScreenBrightnessValidation(C.settings.brightness + 1)); return briShow()
end
function C.app_brightness_down() C.settings_setBrightness(C.settings.brightness - 1); return briShow() end
function C.app_brightness_checkDisplay()
  if bri.showed and bri.time <= C.get_time() then bri.showed = false; return true end
  return false
end

-- Verrouillage (app_lock) : MENU maintenu ----------------------------------------
local lock = { locked = false, recentlyUnlocked = false, timer = 0, changed = 0 }
function C.applock_isLocked() return lock.locked end
function C.applock_isRecentlyUnlocked() return lock.recentlyUnlocked end
function C.applock_isLockRecentlyChanged() return lock.changed > 0 end
function C.applock_isUnlocking() return lock.timer > 0 and lock.locked end
function C.applock_startTimer() lock.timer = C.get_time(); return lock.locked end
function C.applock_stopTimer() lock.timer = 0; return lock.locked end
local function applock_lock()
  C.applock_stopTimer(); lock.locked = true; lock.changed = C.get_time(); return true
end
local function applock_unlock()
  lock.locked = false; C.applock_stopTimer(); lock.recentlyUnlocked = true; lock.changed = C.get_time(); return true
end
function C.applock_checkLock()
  local t = C.get_time()
  if lock.changed > 0 and t - lock.changed > 2 then
    lock.changed = 0; lock.recentlyUnlocked = false
    return true
  end
  if lock.timer > 0 and t - lock.timer > 1 then
    if lock.locked then return applock_unlock() else return applock_lock() end
  end
  return false
end
-- « l'écran doit rester allumé » : verrou / volume / luminosité affichés
function C.overlayActive()
  return C.applock_isLockRecentlyChanged() or C.applock_isUnlocking() or vol.showed or bri.showed
end

-- Mise en veille automatique (app_autosleep) ----------------------------------------
local sleep = { locked = false, time = 0, on = 0, off = 0 }
function C.autosleep_keepAwake()
  if C.display_enabled then sleep.time = C.get_time() + sleep.on else sleep.time = C.get_time() + sleep.off end
end
function C.autosleep_isSleepingTime() return not sleep.locked and C.get_time() > sleep.time end
function C.autosleep_lock() sleep.locked = true end
function C.autosleep_unlock(on, off)
  sleep.on, sleep.off = on, off
  C.autosleep_keepAwake()
  sleep.locked = false
end

-- Batterie (app_battery) : relue toutes les 10 s ------------------------------------
local bat = { pct = 100, time = 0, dir = false }
local function readLine(p)
  local f = io.open(p, "r"); if not f then return nil end
  local l = f:read("*l"); f:close(); return l
end
local function batteryDir()
  if bat.dir ~= false then return bat.dir end
  bat.dir = nil
  if C.IS_WINDOWS then return nil end
  local p = io.popen("ls -1 /sys/class/power_supply 2>/dev/null")
  if p then
    for name in p:lines() do
      local base = "/sys/class/power_supply/" .. name
      if (readLine(base .. "/type") or ""):lower() == "battery" and readLine(base .. "/capacity") then
        bat.dir = base; break
      end
    end
    p:close()
  end
  return bat.dir
end
function C.battery_getPercentage()
  local t = C.get_time()
  if bat.time < t then
    bat.time = t + 10
    local dir = batteryDir()
    local v
    if dir then v = tonumber(readLine(dir .. "/capacity") or "") end
    if not v then
      local _, pct = love.system.getPowerInfo()
      v = pct
    end
    bat.pct = math.max(0, math.min(100, math.floor(v or 100)))
  end
  return bat.pct
end

-- Audio (mp3_reader) ---------------------------------------------------------------
local A = { src = nil, playing = false, paused = false, finished = true, duration = 0, pos = 0, cache = {} }
C.audio = A

local function closeSource()
  if A.src then
    A.src:stop()
    A.src:release()
  end
  if A.fd then A.fd:release() end -- fichier hors du dossier de l'appli, chargé en mémoire
  A.src, A.fd = nil, nil
  A.playing, A.paused, A.finished, A.pos = false, false, true, 0
end

function A.play_path(path, position, askDuration)
  closeSource()
  A.duration = 0
  if not position or position < 0 then position = 0 end
  local src, fd
  local r = rel(path)
  if r and love.filesystem.getInfo(r) then
    -- lecture en continu depuis la carte SD
    local ok, s = pcall(love.audio.newSource, r, "stream")
    if ok then src = s else print("[telmi] audio illisible : " .. path .. " (" .. tostring(s) .. ")") end
  else
    fd = C.fs.fileData(path)
    if fd then
      local ok, s = pcall(love.audio.newSource, fd, "stream")
      if ok then src = s else print("[telmi] audio illisible : " .. path .. " (" .. tostring(s) .. ")") end
    else
      print("[telmi] audio introuvable : " .. path)
    end
  end
  if not src then return end
  A.duration = -1
  if askDuration then
    local d = A.cache[path]
    if not d then
      local ok, v = pcall(src.getDuration, src, "seconds")
      d = (ok and v and v > 0) and v or -1
      if d > 0 then A.cache[path] = d end
    end
    A.duration = d
  end
  if A.duration > 0 and position > A.duration then position = A.duration end
  if position > 0 then pcall(src.seek, src, position, "seconds") end
  A.pos = position
  src:play()
  A.src, A.fd = src, fd
  A.playing, A.paused, A.finished = true, false, false
end

function A.play(dir, name, position, askDuration) A.play_path(dir .. name, position, askDuration) end

function A.update()
  if A.src and A.playing and not A.paused and not A.finished then
    if A.src:isPlaying() then
      A.pos = A.src:tell("seconds") or A.pos
    else
      A.finished, A.playing = true, false
    end
  end
end

function A.isFinished() return A.finished end
function A.isPlaying() return A.playing and not A.finished end
function A.isPaused() return A.paused end
function A.pause()
  if A.playing and not A.finished then
    A.pos = A.src:tell("seconds") or A.pos
    A.src:pause()
    A.paused = true
  end
end
function A.resume()
  A.paused = false
  if A.src and A.playing and not A.finished then A.src:play() end
end
function A.free_music() closeSource(); A.duration = 0 end
function A.getDuration() return A.duration end
function A.getPosition()
  if A.src and A.playing and not A.finished and not A.paused then
    A.pos = A.src:tell("seconds") or A.pos
  end
  return A.pos
end
function A.setPosition(position)
  if A.src and not A.finished then
    if position < 0 then position = 0 end
    if A.duration > 0 and position > A.duration then position = A.duration end
    pcall(A.src.seek, A.src, position, "seconds")
    A.pos = position
  end
end

-- Vidéo (sdl_helper) ---------------------------------------------------------------
local V = {}
C.video = V
V.ALIGN_LEFT, V.ALIGN_RIGHT, V.ALIGN_CENTER = 0, 1, 2
C.colorWhite = { 255 / 255, 255 / 255, 255 / 255 }
C.colorWhite60 = { 189 / 255, 186 / 255, 193 / 255 }
C.colorPurple = { 37 / 255, 16 / 255, 58 / 255 }
C.colorOrange = { 255 / 255, 181 / 255, 0 }
C.colorRed = { 238 / 255, 45 / 255, 0 }

-- cache LRU de 32 images (comme surfaceCache)
local cache, CACHE_SIZE = {}, 32
local function loadImage(path)
  for i, e in ipairs(cache) do
    if e.path == path then
      table.remove(cache, i); table.insert(cache, 1, e)
      return e.img
    end
  end
  local img
  local fd = C.fs.fileData(path)
  if fd then
    local ok, data = pcall(love.image.newImageData, fd)
    if ok then
      local ok2, im = pcall(lg.newImage, data)
      if ok2 then img = im; im:setFilter("linear", "linear") end
    end
  end
  if not img then return nil end
  table.insert(cache, 1, { path = path, img = img })
  if #cache > CACHE_SIZE then
    local old = table.remove(cache)
    old.img:release()
  end
  return img
end
V.loadImage = loadImage

function V.init()
  V.app = lg.newCanvas(640, 480)
  V.screen = lg.newCanvas(640, 480)
  V.app:setFilter("linear", "linear")
  V.screen:setFilter("linear", "linear")
  lg.setCanvas(V.app); lg.clear(0, 0, 0, 1)
  lg.setCanvas(V.screen); lg.clear(0, 0, 0, 1)
  lg.setCanvas()
  local reg, bold = "res/Exo2-Regular.ttf", "res/Exo2-Bold.ttf"
  local function font(path, size)
    local ok, f = pcall(lg.newFont, path, size)
    if ok then return f end
    print("[telmi] police introuvable : " .. path)
    return lg.newFont(size)
  end
  C.fontBold24 = font(bold, 24)
  C.fontBold20 = font(bold, 20)
  C.fontBold18 = font(bold, 18)
  C.fontRegular20 = font(reg, 20)
  C.fontRegular18 = font(reg, 18)
  C.fontRegular16 = font(reg, 16)
end

local function onApp(fn)
  lg.push("all")
  lg.setCanvas(V.app)
  lg.origin()
  lg.setBlendMode("alpha")
  fn()
  lg.pop()
end

function V.screenBlack()
  onApp(function() lg.clear(0, 0, 0, 1) end)
end

function V.drawRectangle(x, y, w, h, r, g, b)
  if w <= 0 or h <= 0 then return end
  onApp(function()
    lg.setColor(r / 255, g / 255, b / 255, 1)
    lg.rectangle("fill", x, y, w, h)
  end)
end

-- video_screenAddImage : image mise à la largeur demandée (proportions gardées)
function V.screenAddImage(dir, name, x, y, width)
  if not name then return end
  local img = loadImage(dir .. name)
  if not img then return end
  onApp(function()
    lg.setColor(1, 1, 1, 1)
    local s = width / img:getWidth()
    lg.draw(img, x, y, 0, s, s)
  end)
end

function V.screenWriteFont(text, font, color, x, y, align)
  if not text or text == "" then return end
  onApp(function()
    lg.setFont(font)
    lg.setColor(color[1], color[2], color[3], 1)
    local w = font:getWidth(text)
    local dx = 0
    if align == V.ALIGN_RIGHT then dx = w elseif align == V.ALIGN_CENTER then dx = math.floor(w / 2) end
    lg.print(text, x - dx, y)
  end)
end

local function showBattery()
  local p = C.battery_getPercentage()
  local color, img
  if p < 6 then color, img = C.colorRed, "storytellerBatteryEmpty.png"
  elseif p < 20 then color, img = C.colorOrange, "storytellerBatteryLow.png"
  elseif p < 60 then color, img = C.colorWhite60, "storytellerBatteryMedium.png"
  else color, img = C.colorWhite60, "storytellerBatteryFull.png" end
  V.screenAddImage(C.RES, img, 531, 2, 76)
  V.screenWriteFont(p .. "%", C.fontRegular16, color, 555, 2, V.ALIGN_CENTER)
end

local function showBar()
  local height, heightMax, image
  if bri.showed then
    height = math.floor(C.settings.brightness * 350 / C.getSystemScreenBrightnessMax())
    heightMax = math.floor(C.getScreenBrightnessMax() * 350 / C.getSystemScreenBrightnessMax())
    image = "storytellerBrightnessBar.png"
  elseif vol.showed then
    height = math.floor(C.settings.volume * 350 / C.getSystemAudioVolumeMax())
    heightMax = math.floor(C.getAudioVolumeMax() * 350 / C.getSystemAudioVolumeMax())
    image = "storyTellerVolumeBar.png"
  else
    return
  end
  lg.setColor(0, 0, 0, 1); lg.rectangle("fill", 19, 47, 26, 350)
  lg.setColor(1, 186 / 255, 0, 1); lg.rectangle("fill", 19, 397 - height, 26, height)
  if heightMax < 350 then
    lg.setColor(238 / 255, 45 / 255, 0, 1); lg.rectangle("fill", 19, 397 - heightMax, 26, 2)
  end
  local img = loadImage(C.RES .. image)
  if img then lg.setColor(1, 1, 1, 1); lg.draw(img, 0, 0) end
end

local function showAppLock()
  if not lock.locked and not lock.recentlyUnlocked then return end
  local img = loadImage(C.RES .. (lock.locked and "storytellerLock.png" or "storytellerUnlock.png"))
  if img then lg.setColor(1, 1, 1, 1); lg.draw(img, 0, 0) end
end

-- video_applyToVideo : batterie + image de l'appli + verrou + barre -> écran
function V.applyToVideo()
  showBattery()
  lg.push("all")
  lg.setCanvas(V.screen)
  lg.origin()
  lg.clear(0, 0, 0, 1)
  lg.setColor(1, 1, 1, 1)
  lg.setBlendMode("replace")
  lg.draw(V.app, 0, 0)
  lg.setBlendMode("alpha")
  showAppLock()
  showBar()
  lg.pop()
  C.dirty = true
end

function V.displayImage(dir, name)
  local img = loadImage(dir .. name)
  onApp(function()
    lg.clear(0, 0, 0, 1)
    if img then
      lg.setColor(1, 1, 1, 1)
      lg.draw(img, math.floor((640 - img:getWidth()) / 2), math.floor((480 - img:getHeight()) / 2))
    end
  end)
  V.applyToVideo()
end

function V.displayBlackScreen()
  V.screenBlack()
  V.applyToVideo()
end

-- Écriture des sauvegardes ------------------------------------------------------------
function C.file_save(path, s) return fs.write(path, s) end

return C
