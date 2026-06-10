-- #######################################################################################
-- Hyprland config (Lua).
-- Converted from the legacy hyprland.conf (hyprlang). Since Hyprland 0.55, hyprlang is
-- deprecated in favor of Lua, and hyprland.lua takes precedence over hyprland.conf.
-- Docs: https://wiki.hypr.land/Configuring/Start/
-- #######################################################################################

------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

-- DP-2 (ASUS VG259QM) is fixed.
hl.monitor({ output = "DP-2", mode = "1920x1080@239.76", position = "-1120x384", scale = 1 })

-- DP-1 (LG UltraGear+) has a hardware button that toggles the panel between
-- 4K@165 and 1080p@330. Each toggle re-plugs the monitor (disconnect +
-- reconnect), so we detect the negotiated mode on `monitor.added` and apply
-- the matching profile. This replaces the two HyprMon profiles
-- (Main = 4K, Gaming = 1080p) with no external listener.
local DP1 = "DP-1"

-- Guard: only auto-switch *this* panel. Hyprland's Lua `description` field is
-- "<make> <model> <serial>", so matching the serial ignores any other monitor
-- that might ever land on the DP-1 connector.
local DP1_SERIAL = "509NTJJSE892"  -- LG UltraGear+

local function dp1_4k()
    hl.monitor({ output = DP1, mode = "3840x2160@165.06", position = "800x128", scale = 1.25 })
end

local function dp1_1080p()
    hl.monitor({ output = DP1, mode = "1920x1080@330.12", position = "800x384", scale = 1 })
end

-- Desktop notification via mako (notify-send -> org.freedesktop.Notifications).
-- The x-canonical-private-synchronous hint makes mako *replace* the previous
-- popup instead of stacking when you toggle modes back and forth.
local function notify_mode(is4k)
    local body = is4k and "DP-1: 3840x2160 @ 165 Hz" or "DP-1: 1920x1080 @ 330 Hz"
    hl.exec_cmd(
        "notify-send -a Hyprland -t 4000 " ..
        "-h string:x-canonical-private-synchronous:dp1-mode " ..
        "'Monitor mode switched' '" .. body .. "'")
end

-- True when DP-1 is on the 4K hardware setting. We read the kernel's current
-- EDID mode list from sysfs rather than the Lua monitor's width/height: those
-- just echo whatever mode we last *forced*, so once 4K is applied they stay
-- 2160 even after the panel drops to 1080p (the detection would be circular).
-- sysfs is the hardware truth -- in 1080p mode the panel stops advertising any
-- 3840x2160 mode. The glob covers card0/card1/etc. `cat` is safe to call here;
-- only `hyprctl` would deadlock (it needs the main thread this callback blocks).
local function dp1_is_4k()
    local h = io.popen("cat /sys/class/drm/*-DP-1/modes 2>/dev/null")
    if not h then return nil end
    local modes = h:read("*a") or ""
    h:close()
    if modes == "" then return nil end  -- couldn't read; signal "unknown"
    return modes:find("3840x2160", 1, true) ~= nil
end

-- Apply the profile matching DP-1's current hardware mode. `hotplug` is true
-- only when called from the monitor.added event (the actual button press);
-- reload and boot call sync_dp1() with no arg, so they re-apply silently.
local function sync_dp1(hotplug)
    local m = hl.get_monitor(DP1)
    if not m then return end
    -- Bail unless this really is our LG UltraGear+ (serial match).
    if not (m.description and m.description:find(DP1_SERIAL, 1, true)) then return end
    local is4k = dp1_is_4k()
    if is4k == nil then return end  -- detection failed; leave the monitor as-is
    if is4k then
        dp1_4k()
    else
        dp1_1080p()
    end
    if hotplug then
        notify_mode(is4k)
        -- waybar doesn't re-anchor when the output geometry changes underneath
        -- it (it floats mid-screen), so restart it. The sleep lets the new mode
        -- settle before the fresh waybar reads the output layout.
        hl.exec_cmd("killall waybar; sleep 0.3; waybar")
    end
end

-- Fires on every reconnect, including the monitor's mode button. Debounce so
-- the new mode has finished negotiating before we read it back.
hl.on("monitor.added", function()
    hl.timer(function() sync_dp1(true) end, { timeout = 300, type = "oneshot" })
end)

-- Apply on every config load too. `hyprctl reload` re-runs this file but does
-- NOT re-fire monitor.added, so this top-level call keeps reloads correct.
-- (At first boot the monitor may not exist yet -> sync_dp1 no-ops and the
-- monitor.added handler above applies it once DP-1 appears.)
sync_dp1()


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use. exec_cmd runs via `sh -c`, so `~` is expanded by the shell.
local terminal    = "~/.local/bin/toastty"
local fileManager = "dolphin"
local menu        = "hyprlauncher"


-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- exec_cmd spawns asynchronously, so no `& disown` is needed.
hl.on("hyprland.start", function()
    sync_dp1()  -- apply the right DP-1 profile for whatever mode it booted in
    hl.exec_cmd("waybar")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hyprlauncher -d")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = { top = 5, right = 5, bottom = 0, left = 5 },

        border_size = 2,

        col = {
            active_border   = { colors = { "rgba(FF9B71EE)", "rgba(E04848EE)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before turning this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 5,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true, -- You probably want this
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})

-- Frosted glass for hyprlauncher (it's a layer surface, namespace "hyprlauncher").
-- Layers are NOT blurred unless a layer rule says so, even with blur enabled above.
-- Paired with the translucent `background` in ~/.config/hypr/hyprtoolkit.conf.
hl.layer_rule({
    name  = "hyprlauncher-glass",
    match = { namespace = "^(hyprlauncher)$" },

    blur         = true,
    ignore_alpha = 0.2, -- don't blur the transparent rounded corners
    -- dim_around = true, -- optional: Raycast-style "spotlight" dim of everything behind
})

-- Default curves, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1} } })

-- Default animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

-- Bind workspaces to monitors. Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
hl.workspace_rule({ workspace = "1", monitor = "DP-2" })
hl.workspace_rule({ workspace = "2", monitor = "DP-1" })


---------------
---- INPUT ----
---------------

-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll       = true,
            scroll_factor        = 0.5,
            clickfinger_behavior = true,
            tap_to_click         = false,
        },
    },
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})


----------------
---- XWAYLAND --
----------------

hl.config({
    xwayland = {
        -- On fractional scaling, fix the text rendering
        force_zero_scaling = true,
    },
})


---------------------
---- KEYBINDINGS ----
---------------------

-- See https://wiki.hypr.land/Configuring/Basics/Binds/
local mainMod = "ALT" -- Sets main modifier

hl.bind(mainMod .. " + space",     hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("killall waybar; waybar"))

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())          -- dwindle
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("grimblast copysave area -n"))
hl.bind(mainMod .. " + SUPER + P", hl.dsp.exec_cmd("grimblast copysave output -n"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move active window to adjacent workspace
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

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


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Pavucontrol audio dropdown (toggled from waybar audio module)
hl.window_rule({
    name  = "pavucontrol-dropdown",
    match = { class = "^org\\.pulseaudio\\.pavucontrol$" },

    float = true,
    size  = { 460, 620 },
    move  = "monitor_w-472 50",
})

-- hyprmon: managed monitor profile include
-- require("hyprmon")
