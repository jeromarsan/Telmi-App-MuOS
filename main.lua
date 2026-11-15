-- Telmi pour muOS (LÖVE 11.5) — portage fidèle de Telmi OS (storyTeller.c)
-- https://github.com/DantSu/Telmi-story-teller
local C = require("core")
local App = require("selector")
local V, audio = C.video, C.audio
local lg = love.graphics

-- Boucle principale (storyTeller.c) -----------------------------------------------
local isMenuPressed, menuPreventDefault = false, false
local pendingRefresh = false
local started, bootTime = false, 0
local lastTick = nil
local exitReason = nil

-- Empêche muOS d'assombrir l'écran / de mettre la console en veille :
-- Telmi gère lui-même l'écran et l'extinction (mêmes fichiers que les jeux).
local INHIBIT_FILES = { "/run/muos/idle_game_inhibit", "/run/muos/idle_sleep_inhibit" }
local inhibitPid = nil
local function setInhibit(on)
  if C.IS_WINDOWS then return end
  if not inhibitPid then
    local f = io.open("/proc/self/stat", "r")
    if not f then return end
    inhibitPid = (f:read("*l") or ""):match("^(%d+)")
    f:close()
    if not inhibitPid then return end
  end
  for _, path in ipairs(INHIBIT_FILES) do
    if on then
      local f = io.open(path, "w")
      if f then f:write(inhibitPid, "\n"); f:close() end
    else
      local f = io.open(path, "r")
      local cur = f and f:read("*l")
      if f then f:close() end
      if cur == inhibitPid then os.remove(path) end
    end
  end
end

local function exitLoop(reason)
  if exitReason then return end
  exitReason = reason
  love.event.quit()
end

-- Bouton appuyé (PRESSED)
local function press(btn)
  if not started then return end
  if btn == "menu" then
    isMenuPressed = true
    pendingRefresh = C.applock_startTimer() or pendingRefresh
    if C.applock_isLocked() then menuPreventDefault = true end
  elseif btn == "start" and isMenuPressed and not C.applock_isLocked() then
    -- MENU + START : quitter Telmi (retour à muOS)
    menuPreventDefault = true
    exitLoop("quit")
  end
end

-- Bouton relâché (RELEASED) : c'est là que Telmi agit
local function release(btn)
  if not started then return end
  if C.applock_isLocked() then
    if btn == "menu" then pendingRefresh = C.applock_stopTimer() or pendingRefresh end
    return
  end
  C.autosleep_keepAwake()

  if btn == "menu" then
    if not menuPreventDefault then App.menu() end
    isMenuPressed = false
    menuPreventDefault = false
    pendingRefresh = C.applock_stopTimer() or pendingRefresh
  elseif btn == "left" then if C.time_wait() then App.previous() end
  elseif btn == "right" then if C.time_wait() then App.next() end
  elseif btn == "up" then if C.time_wait() then App.up() end
  elseif btn == "down" then if C.time_wait() then App.down() end
  elseif btn == "start" or btn == "select" then
    if isMenuPressed then return end -- MENU + START = quitter
    if C.time_wait() then App.pause() end
  elseif btn == "a" or btn == "b" then if C.time_wait() then App.ok() end
  elseif btn == "x" or btn == "y" then if C.time_wait() then App.home() end
  end

  if isMenuPressed then
    if btn == "l2" or btn == "voldown" then
      pendingRefresh = C.app_brightness_down()
      C.applock_stopTimer()
      menuPreventDefault = true
    elseif btn == "r2" or btn == "volup" then
      pendingRefresh = C.app_brightness_up()
      C.applock_stopTimer()
      menuPreventDefault = true
    end
  else
    if btn == "voldown" then pendingRefresh = C.app_volume_down()
    elseif btn == "volup" then pendingRefresh = C.app_volume_up() end
  end
end

-- Démarrage ------------------------------------------------------------------------
function love.load()
  lg.setDefaultFilter("linear", "linear")
  love.math.setRandomSeed(os.time())
  love.keyboard.setKeyRepeat(false)
  print("[telmi] dossier appli : " .. C.SRC)
  print("[telmi] dossier donnees : " .. C.ROOT)

  V.init()
  C.parameters_init()
  C.settings_setVolume(C.getAudioVolumeStartup())
  C.settings_setBrightness(C.getScreenBrightnessStartup())
  C.autosleep_unlock(C.params.screenOnInactivityTime, C.params.screenOffInactivityTime)
  setInhibit(true)

  -- écran de démarrage Telmi pendant 1 s
  local boot = V.loadImage(C.RES .. "bootScreen.png")
  lg.push("all")
  lg.setCanvas(V.screen)
  lg.clear(0, 0, 0, 1)
  if boot then lg.draw(boot, 0, 0) end
  lg.pop()
  C.dirty = true
  bootTime = love.timer.getTime()
end

function love.update(dt)
  if not started then
    if love.timer.getTime() - bootTime >= 1.0 then
      started = true
      App.init()
    end
    return
  end

  -- après une mise en veille muOS (bouton power), l'horloge a sauté :
  -- on ne veut pas éteindre la console dès le réveil
  local now = os.time()
  if lastTick and now - lastTick > 5 then C.autosleep_keepAwake() end
  lastTick = now

  audio.update()

  if C.autosleep_isSleepingTime() then
    exitLoop("sleep")
    return
  end

  local force = pendingRefresh
  pendingRefresh = false
  force = C.applock_checkLock() or force
  force = C.app_volume_checkDisplay() or force
  force = C.app_brightness_checkDisplay() or force
  App.update()
  if force then App.forceRefreshScreen() end
end

function love.draw()
  local w, h = lg.getDimensions()
  lg.clear(0, 0, 0, 1)
  if not C.display_enabled then return end
  local s = math.min(w / 640, h / 480)
  lg.setColor(1, 1, 1, 1)
  lg.draw(V.screen, math.floor((w - 640 * s) / 2), math.floor((h - 480 * s) / 2), 0, s, s)
end

-- On ne redessine que lorsque l'image a changé (économie de batterie).
function love.run()
  love.load()
  love.timer.step()
  local sinceDraw = 0
  return function()
    love.event.pump()
    for name, a, b, c, d, e, f in love.event.poll() do
      if name == "quit" then
        if not love.quit or not love.quit() then return a or 0 end
      end
      love.handlers[name](a, b, c, d, e, f)
    end
    local dt = love.timer.step()
    love.update(dt)
    sinceDraw = sinceDraw + dt
    if lg.isActive() and (C.dirty or sinceDraw > 1) then
      C.dirty = false
      sinceDraw = 0
      lg.origin()
      love.draw()
      lg.present()
    else
      love.timer.sleep(0.012)
    end
  end
end

function love.quit()
  if started then App.save() end
  C.display_setScreen(true)
  C.quitScreen()
  setInhibit(false)
  if exitReason == "sleep" and not C.IS_WINDOWS then
    -- mise en veille automatique de Telmi = extinction de la console (fait par mux_launch.sh)
    local f = io.open("/tmp/telmi_poweroff", "w")
    if f then f:write("1\n"); f:close() end
  end
  print("[telmi] fin (" .. tostring(exitReason or "quit") .. ")")
  return false
end

-- Entrées --------------------------------------------------------------------------
local GAMEPAD = {
  a = "a", b = "b", x = "x", y = "y", start = "start", back = "select", guide = "menu",
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  -- L1 / R1 : volume (muOS garde pour lui les vraies touches de volume)
  leftshoulder = "voldown", rightshoulder = "volup",
}
local KEYS = {
  up = "up", down = "down", left = "left", right = "right",
  ["return"] = "a", space = "a", backspace = "x", x = "x", y = "y",
  s = "start", tab = "select", m = "menu", lctrl = "menu",
  ["-"] = "voldown", ["kp-"] = "voldown", ["="] = "volup", ["kp+"] = "volup",
  volumedown = "voldown", volumeup = "volup",
  ["["] = "l2", ["]"] = "r2",
}
-- manette sans mapping SDL : numéros de boutons habituels sous muOS
local RAWBTN = { [1] = "a", [0] = "b", [2] = "x", [3] = "y", [4] = "voldown", [5] = "volup", [6] = "select", [7] = "start", [8] = "menu" }

function love.gamepadpressed(js, button) local n = GAMEPAD[button]; if n then press(n) end end
function love.gamepadreleased(js, button) local n = GAMEPAD[button]; if n then release(n) end end

local trig = {}
function love.gamepadaxis(js, axis, value)
  local name = (axis == "triggerleft") and "l2" or (axis == "triggerright") and "r2" or nil
  if not name then return end
  if value > 0.5 and not trig[name] then trig[name] = true; press(name)
  elseif value < 0.3 and trig[name] then trig[name] = nil; release(name) end
end

function love.joystickpressed(js, button)
  if js:isGamepad() then return end
  local n = RAWBTN[button]; if n then press(n) end
end
function love.joystickreleased(js, button)
  if js:isGamepad() then return end
  local n = RAWBTN[button]; if n then release(n) end
end
local hatDown = nil
function love.joystickhat(js, hat, dir)
  if js:isGamepad() then return end
  local map = { u = "up", d = "down", l = "left", r = "right" }
  local n = map[dir]
  if hatDown and hatDown ~= n then release(hatDown); hatDown = nil end
  if n and hatDown ~= n then hatDown = n; press(n) end
end

function love.keypressed(key)
  if key == "escape" then exitLoop("quit"); return end
  local n = KEYS[key]; if n then press(n) end
end
function love.keyreleased(key)
  local n = KEYS[key]; if n then release(n) end
end

-- Tests automatiques sur PC (TELMI_TEST=1 + devtest.lua, absent de la version console)
if os.getenv("TELMI_TEST") then
  local ok, T = pcall(require, "devtest")
  if ok then
    T.init(press, release, V, C)
    local u = love.update
    love.update = function(dt) u(dt); T.update(dt) end
  end
end
