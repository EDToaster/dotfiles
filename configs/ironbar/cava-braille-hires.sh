#!/bin/bash
# Two-row ("hi-res") braille audio visualizer from CAVA for Ironbar's
# custom/cava Script module (watch mode).
#
# Ported from the Waybar cava-braille-hires.sh. The ONLY behavioural
# change is the output envelope: Waybar reads a JSON {"text":"…"} and
# the two rows ride inside the string as an escaped \n. Ironbar's
# Script module renders raw stdout straight onto a Pango label, so we
# drop the JSON and join the rows with the XML char-ref &#10; — Pango
# parses that as a newline inside the markup, giving two stacked rows
# in one physical stdout line (a literal newline would be read by
# Ironbar as two separate label updates).
#
# Stacking TWO braille rows turns the per-cell 2x4 dot grid into an
# effective 2x8 grid: each cava column is 0-8 dots tall, split across a
# top cell (levels 5-8) and a bottom cell (levels 1-4).

# Braille dot bits (added to U+2800), bars growing from the bottom up.
# Left column uses dots 7,3,2,1; right column uses dots 8,6,5,4.
#   level: 0    1     2     3     4
left_bits=(  0 0x40 0x44 0x46 0x47)
right_bits=( 0 0x80 0xA0 0xB0 0xB8)

# Precompute the 5x5 single-cell glyph table: braille[left*5 + right],
# where left/right are 0-4 dot heights. Each output column uses TWO of
# these cells stacked (top + bottom) to reach a 0-8 range.
braille=()
for (( l = 0; l < 5; l++ )); do
    for (( r = 0; r < 5; r++ )); do
        # \u in printf consumes hex digits from the format literal, so
        # format the codepoint to hex first, then expand it into \u….
        printf -v hex '%04x' $(( 0x2800 + left_bits[l] + right_bits[r] ))
        printf -v "braille[l*5+r]" "\u$hex"
    done
done

# Amplitude gradient: each column is tinted by its (taller) bar height.
# Raw cava levels run 0..8, so we precompute one color per level by
# interpolating across the stops below. Add/remove/recolor stops freely
# — they're spread evenly from quiet (first) to loud (last).
stops=(
    "137 220 235"   # #89dceb  teal    (quiet)
    "166 227 161"   # #a6e3a1  green
    "249 226 175"   # #f9e2af  yellow
    "255 155 113"   # #ff9b71  coral   (loud)
)
nlevels=9
nstops=${#stops[@]}
colors=()
for (( i = 0; i < nlevels; i++ )); do
    p=$(( i * 1000 / (nlevels - 1) ))                 # position along ramp, 0..1000
    seg=$(( p * (nstops - 1) / 1000 ))                # which pair of stops
    (( seg >= nstops - 1 )) && seg=$(( nstops - 2 ))  # clamp the top end
    seg_lo=$(( seg * 1000 / (nstops - 1) ))
    seg_hi=$(( (seg + 1) * 1000 / (nstops - 1) ))
    frac=$(( (p - seg_lo) * 1000 / (seg_hi - seg_lo) ))   # 0..1000 within segment
    read -r r0 g0 b0 <<< "${stops[seg]}"
    read -r r1 g1 b1 <<< "${stops[seg+1]}"
    r=$(( r0 + (r1 - r0) * frac / 1000 ))
    g=$(( g0 + (g1 - g0) * frac / 1000 ))
    b=$(( b0 + (b1 - b0) * frac / 1000 ))
    # Dim quiet levels: scale brightness from 50% (bottom) to 100% (top).
    lum=$(( 500 + 500 * i / (nlevels - 1) ))   # per-mille, 500..1000
    r=$(( r * lum / 1000 )); g=$(( g * lum / 1000 )); b=$(( b * lum / 1000 ))
    printf -v "colors[i]" '#%02x%02x%02x' "$r" "$g" "$b"
done

# Muted pipe that frames each row (matches the old format's |…| border).
frame="<span color='#313244'>|</span>"

# Pango line-height factor for the two stacked rows: <1 pulls them
# together (1.0 = font default). Needs Pango >= 1.50.
lh="0.65"

# Write a throwaway CAVA config that emits raw ascii to stdout. 60 bars
# (30 glyphs x 2 columns) at a 0-8 range, so each raw level IS the
# column's total dot height across the two stacked cells.
config_file="/tmp/ironbar_cava_braille_hires_config"
cat > "$config_file" <<EOF
[general]
bars = 60
framerate = 30
autosens = 1

[output]
channels = mono
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 8
EOF

# Run CAVA as a child we can read from and clean up after.
exec {cava_fd}< <(cava -p "$config_file")
cava_pid=$!

# Stop CAVA when this script ends, and bail out quietly on a closed
# pipe or a terminating signal. The signal traps call exit so the EXIT
# trap runs even when Ironbar SIGTERMs us (an untrapped fatal signal
# would skip EXIT and orphan the cava child, holding the pty).
cleanup() { kill "$cava_pid" 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP TERM INT

# Write a line to stdout; if the pipe is gone (Ironbar died), exit
# silently instead of spamming "write error: Broken pipe".
emit() { printf '%s\n' "$1" 2>/dev/null || exit 0; }

convert_to_braille() {
    IFS=';' read -ra nums <<< "$1"
    top=""
    bot=""
    for (( i = 0; i < ${#nums[@]}; i += 2 )); do
        lv=${nums[i]}
        rv=${nums[i+1]:-0}
        (( lv >= 0 && lv <= 8 )) || lv=0
        (( rv >= 0 && rv <= 8 )) || rv=0
        # Split each 0-8 column across two stacked cells: the bottom cell
        # holds the first 4 dots, the top cell the next 4.
        lb=$(( lv > 4 ? 4 : lv )); lt=$(( lv > 4 ? lv - 4 : 0 ))
        rb=$(( rv > 4 ? 4 : rv )); rt=$(( rv > 4 ? rv - 4 : 0 ))
        # Tint both rows of this column by its taller raw level (0..8).
        cv=$(( lv > rv ? lv : rv ))
        col="${colors[cv]}"
        top+="<span foreground='${col}'>${braille[lt*5+rt]}</span>"
        bot+="<span foreground='${col}'>${braille[lb*5+rb]}</span>"
    done
    # Frame each row with the muted pipe the old format drew around it.
    top="${frame}${top}${frame}"
    bot="${frame}${bot}${frame}"
    # One physical line: the two rows joined by the &#10; char-ref so
    # Pango renders them stacked, wrapped in a line-height span that
    # tightens the gap between them.
    emit "<span line_height='${lh}'>${top}&#10;${bot}</span>"
}

while IFS= read -r line <&"$cava_fd"; do
    convert_to_braille "$line"
done
