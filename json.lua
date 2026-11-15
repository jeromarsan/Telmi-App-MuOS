-- Petit décodeur JSON (équivalent de cJSON pour Telmi).
-- Les tableaux JSON deviennent des tables Lua indexées à partir de 1,
-- `null` devient json.null (pour distinguer « absent » de « null »).
local json = {}
json.null = setmetatable({}, { __tostring = function() return "null" end })

local byte, sub, char, find = string.byte, string.sub, string.char, string.find
local tonumber, concat = tonumber, table.concat

local function utf8char(c)
  if c < 0x80 then return char(c)
  elseif c < 0x800 then return char(0xC0 + math.floor(c / 0x40), 0x80 + c % 0x40)
  elseif c < 0x10000 then
    return char(0xE0 + math.floor(c / 0x1000), 0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
  else
    return char(0xF0 + math.floor(c / 0x40000), 0x80 + math.floor(c / 0x1000) % 0x40,
      0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
  end
end

local ESC = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local parse

local function skip(s, i)
  local _, e = find(s, "^[ \n\r\t]*", i)
  return e + 1
end

local function parseString(s, i)
  -- i pointe sur le guillemet ouvrant
  local parts, n = {}, 0
  local j = i + 1
  while true do
    local a, b = find(s, '["\\]', j)
    if not a then error("chaine JSON non terminee") end
    n = n + 1; parts[n] = sub(s, j, a - 1)
    if byte(s, a) == 34 then return concat(parts), a + 1 end
    local e = sub(s, a + 1, a + 1)
    if e == "u" then
      local cp = tonumber(sub(s, a + 2, a + 5), 16) or 63
      local nx = a + 6
      if cp >= 0xD800 and cp <= 0xDBFF and sub(s, nx, nx + 1) == "\\u" then
        local lo = tonumber(sub(s, nx + 2, nx + 5), 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          nx = nx + 6
        end
      end
      n = n + 1; parts[n] = utf8char(cp)
      j = nx
    else
      n = n + 1; parts[n] = ESC[e] or e
      j = a + 2
    end
  end
end

parse = function(s, i)
  i = skip(s, i)
  local c = byte(s, i)
  if c == 123 then -- {
    local obj = {}
    i = skip(s, i + 1)
    if byte(s, i) == 125 then return obj, i + 1 end
    while true do
      i = skip(s, i)
      if byte(s, i) ~= 34 then error("cle JSON attendue en " .. i) end
      local k
      k, i = parseString(s, i)
      i = skip(s, i)
      if byte(s, i) ~= 58 then error("':' attendu en " .. i) end
      local v
      v, i = parse(s, i + 1)
      obj[k] = v
      i = skip(s, i)
      c = byte(s, i)
      if c == 125 then return obj, i + 1 end
      if c ~= 44 then error("',' attendu en " .. i) end
      i = i + 1
    end
  elseif c == 91 then -- [
    local arr, n = {}, 0
    i = skip(s, i + 1)
    if byte(s, i) == 93 then return arr, i + 1 end
    while true do
      local v
      v, i = parse(s, i)
      n = n + 1; arr[n] = v
      i = skip(s, i)
      c = byte(s, i)
      if c == 93 then arr.n = n; return arr, i + 1 end
      if c ~= 44 then error("',' attendu en " .. i) end
      i = i + 1
    end
  elseif c == 34 then
    return parseString(s, i)
  elseif sub(s, i, i + 3) == "true" then return true, i + 4
  elseif sub(s, i, i + 4) == "false" then return false, i + 5
  elseif sub(s, i, i + 3) == "null" then return json.null, i + 4
  else
    local a, b = find(s, "^-?[%d%.eE+-]+", i)
    if not a then error("valeur JSON invalide en " .. i) end
    return tonumber(sub(s, a, b)), b + 1
  end
end

function json.decode(s)
  if type(s) ~= "string" then return nil end
  if sub(s, 1, 3) == "\239\187\191" then s = sub(s, 4) end -- BOM
  local ok, v = pcall(parse, s, 1)
  if ok then return v end
  print("[telmi] JSON invalide : " .. tostring(v))
  return nil
end

-- Échappement d'une chaîne pour l'écriture des sauvegardes.
function json.str(s)
  s = tostring(s or "")
  s = s:gsub('[%c"\\]', function(ch)
    if ch == '"' then return '\\"' elseif ch == "\\" then return "\\\\" end
    return string.format("\\u%04x", byte(ch))
  end)
  return s
end

-- Petits équivalents des helpers cJSON de Telmi ------------------------
function json.isArray(v) return type(v) == "table" and v ~= json.null and (v.n ~= nil or v[1] ~= nil or next(v) == nil) end
function json.size(v)
  if type(v) ~= "table" or v == json.null then return 0 end
  return v.n or #v
end
-- élément d'indice C (0 = premier)
function json.at(v, i)
  if type(v) ~= "table" or v == json.null then return nil end
  local x = v[i + 1]
  if x == json.null then return nil end
  return x
end
function json.get(obj, key)
  if type(obj) ~= "table" or obj == json.null then return nil end
  local v = obj[key]
  if v == json.null then return nil end
  return v
end
-- Comme json_getInt de Telmi : vrai dès que la clé existe (même null -> 0)
function json.getInt(obj, key)
  if type(obj) ~= "table" or obj == json.null then return nil end
  local v = obj[key]
  if v == nil then return nil end
  if type(v) == "number" then
    if v >= 0 then return math.floor(v) else return math.ceil(v) end
  end
  return 0
end
function json.getNumber(obj, key)
  if type(obj) ~= "table" or obj == json.null then return nil end
  local v = obj[key]
  if v == nil then return nil end
  if type(v) == "number" then return v end
  return 0
end
-- cJSON_GetNumberValue d'un champ absent vaut NaN en C ; ici 0
function json.num(obj, key)
  local v = json.getInt(obj, key)
  return v or 0
end
function json.getString(obj, key)
  local v = json.get(obj, key)
  if type(v) == "string" then return v end
  return nil
end
function json.getBool(obj, key)
  if type(obj) ~= "table" or obj == json.null then return nil end
  local v = obj[key]
  if v == nil then return nil end
  return v == true
end
function json.isTrue(v) return v == true end

return json
