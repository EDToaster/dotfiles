#!/usr/bin/env bash
# Ironbar weather module. Ported from the Waybar custom/weather, which
# fed wttrbar's {"text","tooltip"} JSON straight to Waybar.
#
# Ironbar's Script module renders raw stdout, not that JSON envelope,
# so we run wttrbar once and unwrap one field with jq:
#   (no arg)  → .text     (bar label, nerd-font icon + temp)
#   tooltip   → .tooltip  (multi-line forecast, shown on hover)
#
# Needs: wttrbar, jq.

out=$(wttrbar --nerd 2>/dev/null)

if [[ "$1" == tooltip ]]; then
  jq -r '.tooltip // empty' <<<"$out"
else
  jq -r '.text // empty' <<<"$out"
fi
