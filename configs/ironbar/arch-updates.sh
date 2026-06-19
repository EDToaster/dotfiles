#!/bin/bash
# Ironbar custom module: Arch update status. Ported from the Waybar
# arch-updates.sh.
#
# Waybar emitted {"text","tooltip","class"} and let CSS colour the
# text via the class. Ironbar's Script module renders stdout straight
# onto a Pango label and can't set a CSS class from output, so the
# state colour is baked into a <span foreground> instead:
#   muted check  → system up to date
#   fg count     → updates pending (repo and/or AUR)
#   accent count → pending AND no full upgrade in the last 2 weeks
#
# Called with `tooltip` as $1 it prints the multi-line tooltip
# (config.yaml wires this to the module's tooltip).

STALE_DAYS=14
LOG=/var/log/pacman.log

FG="#cdd6f4"      # default text
ACCENT="#ff9b71"  # coral accent (stale)
MUTED="#313244"   # muted (up to date)

# Nerd-font glyphs as explicit codepoints (never paste the raw PUA
# glyph — it silently disappears in editors that lack the font).
CHECK=$''   # nf-fa-check
DL=$''      # nf-fa-download

# ── Pending updates ──────────────────────────────────────────────────────
# checkupdates (pacman-contrib) diffs against a *temporary* copy of the sync
# DB, so it never runs `pacman -Sy` and can't trigger a partial upgrade.
repo=$(checkupdates 2>/dev/null | wc -l)
aur=$(paru -Qua 2>/dev/null | wc -l)
total=$((repo + aur))

# ── Days since the last *full* system upgrade ────────────────────────────
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

# ── Tooltip branch ───────────────────────────────────────────────────────
if [[ "$1" == tooltip ]]; then
  printf '%s packages pending updates\n%s AUR packages pending updates\nLast full upgrade: %s\n' \
    "$repo" "$aur" "$last_human"
  exit 0
fi

# ── Bar text (Pango-coloured) ────────────────────────────────────────────
if (( total == 0 )); then
  printf "<span foreground='%s'>%s</span>\n" "$MUTED" "$CHECK"
elif (( age > STALE_DAYS * 86400 )); then
  printf "<span foreground='%s'>%s %s + %s</span>\n" "$ACCENT" "$DL" "$repo" "$aur"
else
  printf "<span foreground='%s'>%s %s + %s</span>\n" "$FG" "$DL" "$repo" "$aur"
fi
