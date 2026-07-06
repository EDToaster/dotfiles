local terminal    = "~/.local/bin/toastty"
local fileManager = "dolphin"
local menu        = "~/.config/rofi/launchers/type-6/launcher.sh || pkill rofi"
local browser     = "firefox"

-- Launch a terminal in the CWD of the focused toastty's shell (else $HOME).
local terminal_here = [[
pid=$(hyprctl activewindow -j | jq -r '.pid // empty')
exe=$(readlink "/proc/$pid/exe" 2>/dev/null)
dir=$HOME
if [ "${exe##*/}" = toastty ]; then
  while child=$(pgrep -nP "$pid"); do pid=$child; done   # descend to the foreground process
  cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
  [ -n "$cwd" ] && dir=$cwd
fi
exec ]] .. terminal .. " -d \"$dir\""

---------------------
---- KEYBINDINGS ----
---------------------

-- See https://wiki.hypr.land/Configuring/Basics/Binds/
local mainMod = "SUPER" -- Sets main modifier, used for workspace-related actions
local altMod  = "ALT"    -- Sets alt modifier, used for common stuff


hl.bind(altMod .. " + SPACE" , hl.dsp.exec_cmd(menu))
hl.bind(altMod .. " + K"     , hl.dsp.exec_cmd("~/.config/hypr/scripts/menu.sh -t"))
hl.bind(altMod .. " + Q"     , hl.dsp.window.close())

-- Move focus with mainMod + arrow keys
hl.bind(altMod .. " + LEFT",  hl.dsp.focus({ direction = "left" }))
hl.bind(altMod .. " + RIGHT", hl.dsp.focus({ direction = "right" }))
hl.bind(altMod .. " + UP",    hl.dsp.focus({ direction = "up" }))
hl.bind(altMod .. " + DOWN",  hl.dsp.focus({ direction = "down" }))

-- Command palette of these keybinds (rofi). See scripts/keybind-palette.sh
hl.bind(mainMod .. " + T"     , hl.dsp.exec_cmd(terminal_here))
hl.bind(mainMod .. " + E"     , hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V"     , hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + O"     , hl.dsp.window.pseudo())          -- dwindle
hl.bind(mainMod .. " + D"     , hl.dsp.exec_cmd(terminal .. " --working-directory ~/.config"))
hl.bind(mainMod .. " + F"     , hl.dsp.exec_cmd(browser))

-- Scary Stuff
-- hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("killall waybar; waybar"))
-- hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

-- Utilities
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("grimblast copysave area -n"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("grimblast copysave output -n"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a -n"))


-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(altMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(altMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(altMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(altMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move active window to adjacent workspace
hl.bind(altMod .. " + SHIFT + RIGHT", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(altMod .. " + SHIFT + LEFT",  hl.dsp.window.move({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(altMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(altMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

