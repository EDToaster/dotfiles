
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
local DP2 = "DP-2"

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
    -- hl.notification.create({ text = body, timeout = 3000, icon = "ok"})
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
function sync_dp1(hotplug)
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
        -- Waybar is launched once at startup (hyprland.start, exec_cmd "waybar").
        -- It doesn't re-anchor when the output geometry changes underneath it (it
        -- floats mid-screen), so on a mode change we RESTART it here -- we never
        -- start a fresh one from scratch. The sleep lets the new mode settle before
        -- the new waybar reads the output layout. The relaunch_pending guard on the
        -- monitor.added handler ensures only one restart runs at a time, so this
        -- killall always catches the running bar (no duplicate).
        hl.exec_cmd("killall waybar; sleep 0.3; waybar")
    end
end

-- Fires once per monitor as it connects: at login that's BOTH DP-1 and DP-2,
-- plus the DP-1 mode button (which disconnect+reconnects). This handler ignores
-- which monitor fired -- sync_dp1 always targets DP-1 and always passes its own
-- serial guard, so every add would otherwise trigger a full waybar restart. With
-- two monitors enumerating at login that meant two concurrent
-- `killall waybar; sleep 0.3; waybar` sequences whose kills both landed during
-- the sleep, before either bar appeared -> two stacked bars. `relaunch_pending`
-- collapses any burst of adds into a SINGLE restart. The 300ms debounce also lets
-- the new mode finish negotiating before sync_dp1 reads it back from sysfs.
local relaunch_pending = false
hl.on("monitor.added", function()
    if relaunch_pending then return end
    relaunch_pending = true
    hl.timer(function()
        relaunch_pending = false
        sync_dp1(true)
    end, { timeout = 300, type = "oneshot" })
end)

-- Apply on every config load too. `hyprctl reload` re-runs this file but does
-- NOT re-fire monitor.added, so this top-level call keeps reloads correct.
-- (At first boot the monitor may not exist yet -> sync_dp1 no-ops and the
-- monitor.added handler above applies it once DP-1 appears.)
sync_dp1()

return {DP2, DP1}
