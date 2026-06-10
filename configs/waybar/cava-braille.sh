#!/bin/bash
# Streams a braille-character audio visualizer from CAVA for the
# custom/cava module, and blanks the bar after ~2s of silence.
#
# Braille gives a "hi-res" display: each braille glyph is a 2x4 dot grid,
# so one cell packs TWO cava bars side by side (left column + right
# column), each 0-4 dots tall. We run cava with twice the bars and fold
# every adjacent pair into a single glyph.
#
# Designed to die quietly when waybar exits: the read loop runs in the
# main shell (not a pipeline subshell), writes are guarded against a
# broken pipe, and the CAVA child is reaped on exit.

# Braille dot bits (added to U+2800), bars growing from the bottom up.
# Left column uses dots 7,3,2,1; right column uses dots 8,6,5,4.
#   level: 0    1     2     3     4
left_bits=(  0 0x40 0x44 0x46 0x47)
right_bits=( 0 0x80 0xA0 0xB0 0xB8)

# Precompute the 5x5 glyph table: braille[left*5 + right].
braille=()
for (( l = 0; l < 5; l++ )); do
    for (( r = 0; r < 5; r++ )); do
        # \u in printf consumes hex digits from the format literal, so
        # format the codepoint to hex first, then expand it into \u….
        printf -v hex '%04x' $(( 0x2800 + left_bits[l] + right_bits[r] ))
        printf -v "braille[l*5+r]" "\u$hex"
    done
done

# Map each raw cava level (0..10) to a dot height (0..4):
#   0 -> 0, 1-2 -> 1, 3-4-5 -> 2, 6-7-8 -> 3, 9-10 -> 4
fold=(0 1 1 2 2 2 3 3 3 4 4)

# Amplitude gradient: each glyph is tinted by its (taller) bar height.
# Raw cava levels run 0..10, so we precompute one color per level by
# interpolating across the stops below. Add/remove/recolor stops freely
# — they're spread evenly from quiet (first) to loud (last).
stops=(
    "137 220 235"   # #89dceb  teal    (quiet)
    "166 227 161"   # #a6e3a1  green
    "249 226 175"   # #f9e2af  yellow
    "255 155 113"   # #ff9b71  coral   (loud)
)
nlevels=11
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

# Write a throwaway CAVA config that emits raw ascii to stdout. We ask
# for 30 bars (15 glyphs x 2 columns) and a 0-10 range, folding the raw
# level into each dot (4 dots per column -> see convert_to_braille).
config_file="/tmp/waybar_cava_braille_config"
cat > "$config_file" <<EOF
[general]
bars = 30
framerate = 30
autosens = 1

[output]
channels = mono
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 10
EOF

# Run CAVA as a child we can read from and clean up after.
exec {cava_fd}< <(cava -p "$config_file")
cava_pid=$!

# Stop CAVA when this script ends, and bail out quietly on a closed
# pipe or a terminating signal. The signal traps call exit so the EXIT
# trap runs even when waybar SIGHUPs/SIGTERMs us (an untrapped fatal
# signal would skip EXIT and orphan the cava child, holding the pty).
cleanup() { kill "$cava_pid" 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP TERM INT

# Write a line to stdout; if the pipe is gone (waybar died), exit
# silently instead of spamming "write error: Broken pipe".
emit() { printf '%s\n' "$1" 2>/dev/null || exit 0; }

pause_start=0

convert_to_braille() {
    IFS=';' read -ra nums <<< "$1"
    out=""
    for (( i = 0; i < ${#nums[@]}; i += 2 )); do
        lv=${nums[i]}
        rv=${nums[i+1]:-0}
        (( lv >= 0 && lv <= 10 )) || lv=0
        (( rv >= 0 && rv <= 10 )) || rv=0
        # Fold the raw cava level into a dot height via the table above:
        #   0 -> 0, 1-2 -> 1, 3-4-5 -> 2, 6-7-8 -> 3, 9-10 -> 4
        lh=${fold[lv]}
        rh=${fold[rv]}
        # Tint the glyph by its taller column's raw level (0..10).
        cv=$(( lv > rv ? lv : rv ))
        out+="<span foreground='${colors[cv]}'>${braille[lh*5+rh]}</span>"
    done
    emit "$out"
}

while IFS= read -r line <&"$cava_fd"; do
    # now=$(date +%s)

    # All-zero line == silence
    # if [[ "$line" =~ ^(0;?)+$ ]]; then
    #     (( pause_start == 0 )) && pause_start=$now

    #     # Hide after 2 seconds of continuous silence.
    #     if (( now - pause_start >= 2 )); then
    #         emit ""
    #     else
    #         convert_to_braille "$line"
    #     fi
    #     continue
    # fi

    # Audio is back — reset the silence timer and draw.
    # pause_start=0
    convert_to_braille "$line"
done
