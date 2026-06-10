#!/bin/bash
# Waybar custom module: Arch update status.
#   green check  → system up to date (nothing pending)
#   orange       → updates pending (repo and/or AUR)
#   red          → updates pending AND no full upgrade in the last 2 weeks
#
# Emits Waybar JSON {"text","tooltip","class"}. The `class` drives the colour
# from style.css (.updated / .pending / .stale).

STALE_DAYS=14
LOG=/var/log/pacman.log

# ── Pending updates ──────────────────────────────────────────────────────
# checkupdates (pacman-contrib) diffs against a *temporary* copy of the sync
# DB, so it never runs `pacman -Sy` and can't trigger a partial upgrade.
repo=$(checkupdates 2>/dev/null | wc -l)
# AUR upgrades only.
aur=$(paru -Qua 2>/dev/null | wc -l)
total=$((repo + aur))

# ── Days since the last *full* system upgrade ────────────────────────────
# pacman logs this exact line whenever `-u` runs (incl. via paru).
last_line=$(grep -F 'starting full system upgrade' "$LOG" 2>/dev/null | tail -n1)
ts=${last_line%%]*}      # "[2026-06-07T22:24:39-0700"
ts=${ts#\[}              # "2026-06-07T22:24:39-0700"

if [[ -n $ts ]] && last_epoch=$(date -d "$ts" +%s 2>/dev/null); then
  last_human=$(date -d "$ts" '+%Y-%m-%d %H:%M')
else
  last_epoch=0
  last_human="unknown"
fi
age=$(( $(date +%s) - last_epoch ))

# ── State ────────────────────────────────────────────────────────────────
# Icons are Nerd Font glyphs written as explicit codepoints (\uXXXX) so they
# survive copy/paste, diffs, and editors that lack the font — never paste the
# raw Private Use Area glyph, it silently disappears.
if (( total == 0 )); then
  class="updated"; text=$'\ueab2'                # nf-fa-check
elif (( age > STALE_DAYS * 86400 )); then
  class="stale";   text=$'\uf019'" $repo + $aur"       # nf-fa-download + count
else
  class="pending"; text=$'\uf019'" $repo + $aur"       # nf-fa-download + count
fi

tooltip="$repo packages pending updates\\n$aur AUR packages pending updates\\nLast full upgrade: $last_human"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
