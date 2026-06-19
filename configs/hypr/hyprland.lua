-- #######################################################################################
-- Hyprland config (Lua).
-- Converted from the legacy hyprland.conf (hyprlang). Since Hyprland 0.55, hyprlang is
-- deprecated in favor of Lua, and hyprland.lua takes precedence over hyprland.conf.
-- Docs: https://wiki.hypr.land/Configuring/Start/
-- #######################################################################################

local monitors = require("confs.monitors")
require("confs.keybinds")
require("confs.theme")

-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- exec_cmd spawns asynchronously, so no `& disown` is needed.
hl.on("hyprland.start", function()
    sync_dp1()  -- apply the right DP-1 profile for whatever mode it booted in
    hl.exec_cmd("waybar")  -- single, deterministic launch; the monitor path only RESTARTS it (see confs/monitors.lua)
    -- hl.exec_cmd("hyprpaper")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")

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
        accel_profile = "flat",

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

-- Bind workspaces to monitors. Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
for i, monitor in ipairs(monitors) do
    hl.workspace_rule({ workspace = tostring(i), monitor = monitor})
end

hl.exec_cmd(
    "notify-send -u low -a Hyprland -t 4000 -A hi -A a " ..
    "'hyprland.lua reloaded'")
