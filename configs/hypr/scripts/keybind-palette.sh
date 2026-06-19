#!/usr/bin/env bash
#
# keybind-palette.sh — a rofi "command palette" of your Hyprland keybinds.
#
# How it works: instead of parsing keybinds.lua with regex (which would miss
# loop-generated binds like the workspace 1-10 block) or scraping `hyprctl
# binds` (whose Lua dispatchers show up as opaque "__lua N" with no labels),
# we *run* keybinds.lua under a stubbed `hl` global. The real Lua executes —
# so every bind, including loop-generated ones, is captured with a readable
# label AND an executable action. New binds you add later just appear; there
# is nothing to keep in sync.
#
# Each row carries a hidden action:
#   - exec_cmd binds   -> run the captured command directly via `sh -c`
#   - everything else  -> re-fire via `hyprctl dispatch 'hl.dsp.<...>'`
# (In this Lua-based Hyprland, `hyprctl dispatch X` evaluates X as Lua, i.e.
#  `hl.dispatch(X)`, so dispatching the original hl.dsp.* expression works.)
#
# Deps: lua, rofi, hyprctl, base64 (coreutils), notify-send. setsid optional.

set -euo pipefail

KB_FILE="${KB_FILE:-$HOME/.config/hypr/confs/keybinds.lua}"

if [ ! -r "$KB_FILE" ]; then
    notify-send "keybind palette" "cannot read $KB_FILE" 2>/dev/null || true
    exit 1
fi

# ---------------------------------------------------------------------------
# Generate records by sourcing keybinds.lua with a fake `hl`.
# Output: one record per line, tab-separated:  KEYS \t LABEL \t TYPE \t B64(payload)
# The payload (a shell command or a Lua expression) is base64-encoded so it can
# safely contain spaces, quotes and newlines (e.g. the multi-line terminal_here).
# ---------------------------------------------------------------------------
records="$(KB_FILE="$KB_FILE" lua - <<'LUA'
-- base64 encoder (classic pure-Lua implementation)
local B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64(data)
  return ((data:gsub('.', function(x)
    local r, c = '', x:byte()
    for i = 8, 1, -1 do r = r .. (c % 2 ^ i - c % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return B:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- serialize a Lua value back into canonical Lua source (for dispatch exprs)
local function serialize(v)
  local t = type(v)
  if t == 'string' then
    return string.format('%q', v)
  elseif t == 'number' or t == 'boolean' then
    return tostring(v)
  elseif t == 'table' then
    local n, isarr = 0, true
    for k in pairs(v) do
      n = n + 1
      if type(k) ~= 'number' then isarr = false end
    end
    local parts = {}
    if isarr and n == #v then
      for i = 1, #v do parts[i] = serialize(v[i]) end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        local ks = (type(k) == 'string' and k:match('^[%a_][%w_]*$'))
          and (k .. '=') or ('[' .. serialize(k) .. ']=')
        parts[#parts + 1] = ks .. serialize(v[k])
      end
    end
    return '{' .. table.concat(parts, ', ') .. '}'
  end
  return 'nil'
end

-- generic hl.dsp proxy: any access builds a dotted path; calling it records
-- the path + args and reconstructs the original hl.dsp.<path>(<args>) expr.
local function make_dsp(path)
  return setmetatable({}, {
    __index = function(_, k)
      return make_dsp(path == '' and k or (path .. '.' .. k))
    end,
    __call = function(_, ...)
      local args, n = { ... }, select('#', ...)
      local as = {}
      for i = 1, n do as[i] = serialize(args[i]) end
      return {
        __disp = true,
        path = path,
        args = args,
        nargs = n,
        expr = 'hl.dsp.' .. path .. '(' .. table.concat(as, ', ') .. ')',
      }
    end,
  })
end

local function tidy(s)
  s = tostring(s):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if #s > 64 then s = s:sub(1, 61) .. '...' end
  return s
end

-- human-readable label for a dispatcher
local function label_of(d)
  local p, a = d.path, d.args
  if p == 'exec_cmd' then
    local cmd = a[1] or ''
    if cmd:find('\n') then -- multi-line: prefer the trailing `exec <thing>`
      local tail = cmd:match('exec%s+([^\n]+)%s*$')
      return 'exec: ' .. tidy(tail or '«shell script»')
    end
    return 'exec: ' .. tidy(cmd)
  elseif p == 'window.close' then
    return 'close window'
  elseif p == 'window.pseudo' then
    return 'toggle pseudo'
  elseif p == 'window.float' then
    return 'toggle floating'
  elseif p == 'window.drag' then
    return 'drag window (mouse)'
  elseif p == 'window.resize' then
    return 'resize window (mouse)'
  elseif p == 'focus' and a[1] then
    if a[1].direction then return 'focus ' .. a[1].direction end
    if a[1].workspace then return 'go to workspace ' .. tostring(a[1].workspace) end
  elseif p == 'window.move' and a[1] and a[1].workspace then
    return 'move window \u{2192} workspace ' .. tostring(a[1].workspace)
  elseif p == 'workspace.toggle_special' then
    return 'toggle special workspace: ' .. tostring(a[1])
  end
  -- generic fallback: path(arg, arg, ...)
  local as = {}
  for i = 1, d.nargs do as[i] = serialize(d.args[i]) end
  return p .. '(' .. table.concat(as, ', ') .. ')'
end

local RECS = {}
hl = { dsp = make_dsp('') }
-- no-op stubs so requiring/sourcing never explodes if the file grows
hl.on = function() end
hl.env = function() end
hl.exec_cmd = function() end
hl.source = function() end
hl.set = function() end

function hl.bind(keys, disp, flags)
  flags = flags or {}
  local label, typ, payload
  if type(disp) == 'table' and disp.__disp then
    label = label_of(disp)
    if disp.path == 'exec_cmd' then
      typ, payload = 'exec', (disp.args[1] or '')
    elseif flags.mouse then
      typ, payload = 'none', '' -- mouse binds can't be triggered from a menu
    else
      typ, payload = 'dispatch', disp.expr
    end
  elseif type(disp) == 'function' then
    label, typ, payload = '(lua function)', 'none', ''
  else
    label, typ, payload = tostring(disp), 'none', ''
  end
  RECS[#RECS + 1] = { keys = keys, label = label, typ = typ, payload = payload or '' }
end

local chunk, err = loadfile(os.getenv('KB_FILE'))
if not chunk then
  io.stderr:write('keybind-palette: ' .. tostring(err) .. '\n')
  os.exit(1)
end
chunk()

for _, r in ipairs(RECS) do
  io.write(r.keys .. '\t' .. r.label .. '\t' .. r.typ .. '\t' .. b64(r.payload) .. '\n')
end
LUA
)"

if [ -z "$records" ]; then
    notify-send "keybind palette" "no keybinds found" 2>/dev/null || true
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse records into parallel arrays; build aligned display lines.
# ---------------------------------------------------------------------------
# NB: do not name the rows array DISPLAY — that collides with the X11 $DISPLAY
# env var, which bash would fold in as element [0] and offset every index.
declare -a ROWS TYP PAYLOAD
maxk=0
while IFS=$'\t' read -r keys _ _ _; do
    (( ${#keys} > maxk )) && maxk=${#keys}
done <<< "$records"

while IFS=$'\t' read -r keys label typ b64; do
    printf -v line '%-*s   %s' "$maxk" "$keys" "$label"
    ROWS+=("$line")
    TYP+=("$typ")
    PAYLOAD+=("$b64")
done <<< "$records"

# ---------------------------------------------------------------------------
# rofi theme — inline, mirrors the type-6 / style-4 palette (no extra file).
# ---------------------------------------------------------------------------
THEME='
* {
    font:            "JetBrains Mono Nerd Font 11";
    background:      #2D1B14;
    background-alt:  #462D23;
    foreground:      #FFFFFF;
    selected:        #E25F3E;
    muted:           #7B6C5B;
}
window   { width: 780px; border-radius: 15px; background-color: @background; }
mainbox  { padding: 16px; spacing: 12px; background-color: transparent;
           children: [ "inputbar", "listview" ]; }
inputbar { padding: 12px; border-radius: 10px; spacing: 10px;
           background-color: @background-alt; text-color: @foreground;
           children: [ "prompt", "entry" ]; }
prompt   { background-color: inherit; text-color: @selected; }
entry    { background-color: inherit; text-color: @foreground;
           placeholder: "search keybinds"; placeholder-color: @muted; }
listview { lines: 14; columns: 1; scrollbar: false; spacing: 4px;
           background-color: transparent; }
element  { padding: 8px 12px; border-radius: 8px;
           background-color: transparent; text-color: @foreground; }
element normal.normal    { background-color: transparent;  text-color: @foreground; }
element alternate.normal { background-color: #3A2018;       text-color: @foreground; }  /* subtle stripe between bg #2D1B14 and bg-alt #462D23 */
element selected.normal  { background-color: @selected;     text-color: @foreground; }
element-text { background-color: inherit; text-color: inherit; }
'

idx="$(printf '%s\n' "${ROWS[@]}" \
    | rofi -dmenu -i -p "keybinds" -format i -theme-str "$THEME")" || exit 0

# Esc, or a custom (non-list) entry, yields no valid index — just bail.
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0
(( idx >= 0 && idx < ${#TYP[@]} )) || exit 0

typ="${TYP[$idx]}"
payload="$(printf '%s' "${PAYLOAD[$idx]}" | base64 -d)"

case "$typ" in
    exec)
        # Run like Hyprland does (/bin/sh -c), detached so it outlives this script.
        if command -v setsid >/dev/null 2>&1; then
            setsid -f sh -c "$payload" >/dev/null 2>&1
        else
            sh -c "$payload" >/dev/null 2>&1 &
        fi
        ;;
    dispatch)
        hyprctl dispatch "$payload" >/dev/null
        ;;
    *)
        notify-send "keybind palette" "this bind can't be triggered from the palette" 2>/dev/null || true
        ;;
esac
