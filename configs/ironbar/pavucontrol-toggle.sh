#!/usr/bin/env bash
#
# pavucontrol-toggle.sh — open pavucontrol from Waybar. It ends up *unfocused*,
# and closes itself once you focus it and then move focus away again (Hyprland).
#
# Waybar has no notion of window focus, so this listens to Hyprland's event
# socket (.socket2.sock).
#
# Note: Hyprland's `noinitialfocus` rule does NOT keep pavucontrol unfocused on
# this setup (it grabs focus on map regardless, even with the cursor nowhere
# near it). So instead we let it open, wait until it actually has focus, then
# hand focus back to whatever you had — that bounce is stable. Only after that
# do we start watching, so the launch/bounce focus events aren't counted; we
# then "arm" the first time you genuinely focus pavucontrol and close it the
# next time focus leaves it.
#
# Wired into Waybar's pulseaudio module via "on-click".
# Needs: socat, jq, hyprctl (Hyprland).

# Already open? Treat the click as a toggle-off.
if pgrep -x pavucontrol >/dev/null; then
    pkill -x pavucontrol
    exit 0
fi

sock="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"

# Outside Hyprland (no event socket) there's no unfocused-start / auto-close to
# do, so just open pavucontrol normally and stop.
if [ ! -S "$sock" ] || ! command -v hyprctl >/dev/null; then
    pavucontrol &
    exit 0
fi

focused_class() { hyprctl activewindow -j | jq -r '.class // ""'; }
is_pavucontrol() { [[ "${1,,}" == *pavucontrol* ]]; }

# The window we'll hand focus back to, so pavucontrol ends up unfocused.
prev=$(hyprctl activewindow -j | jq -r '.address // empty')

pavucontrol &

# Wait until pavucontrol actually has focus (it grabs it on map), polling fast
# to keep the flicker short. Bail out early if it never opened.
for ((i = 0; i < 40; i++)); do
    is_pavucontrol "$(focused_class)" && break
    pgrep -x pavucontrol >/dev/null || exit 0
    sleep 0.05
done

# Bounce focus back to where you were. Hyprland warps the cursor to the focused
# window by default (cursor:no_warps=false), which would yank your pointer, so
# suppress that just for this focus change and restore your setting. Then let
# it settle: because we only connect to the event socket *after* this, the
# launch + bounce focus events are already in the past and won't be mistaken
# for "you focused it" below.
if [ -n "$prev" ]; then
    warp=$(hyprctl getoption cursor:no_warps -j | jq -r '.int')
    orig=$([ "$warp" = 1 ] && echo true || echo false)
    hyprctl --batch \
        "keyword cursor:no_warps true ; dispatch focuswindow address:$prev ; keyword cursor:no_warps $orig" \
        >/dev/null
fi
sleep 0.4

# Steady state: arm the first time pavucontrol gains focus, then close it the
# first time focus moves to another window.
armed=0
while read -r line; do
    # pavucontrol gone already (closed manually / toggled off)? stop watching.
    pgrep -x pavucontrol >/dev/null || exit 0

    case "$line" in
    "activewindow>>"*)
        class=${line#activewindow>>} # "CLASS,TITLE"
        class=${class%%,*}           # "CLASS"
        if is_pavucontrol "$class"; then
            armed=1
        elif ((armed)); then
            pkill -x pavucontrol
            exit 0
        fi
        ;;
    esac
done < <(socat -U - "UNIX-CONNECT:${sock}")
