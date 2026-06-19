#!/bin/bash
# Unicode-bar audio visualizer from CAVA for Ironbar's custom/cava
# Script module (watch mode).
#
# Ported from the Waybar cava.sh — that version already emits a single
# line of plain text (no JSON envelope), so the only change is the
# /tmp config path. Swap config.yaml's cava `cmd` to this file for a
# simple block-bar visualiser instead of the braille one.

# Unicode bars (levels 0–8)
bars=(" " ⡀ ⣀ ⣄ ⣤ ⣦ ⣶ ⣷ ⣿)

# Write a throwaway CAVA config that emits raw ascii to stdout.
config_file="/tmp/ironbar_cava_config"
cat > "$config_file" <<EOF
[general]
bars = 15
framerate = 30
autosens = 1

[output]
channels = mono
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = ${#bars[@]}
EOF

exec {cava_fd}< <(cava -p "$config_file")
cava_pid=$!

cleanup() { kill "$cava_pid" 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP TERM INT

emit() { printf '%s\n' "$1" 2>/dev/null || exit 0; }

convert_to_bars() {
    IFS=';' read -ra nums <<< "$1"
    out=""
    for n in "${nums[@]}"; do
        (( n >= 0 && n <= 7 )) || n=0
        out+="${bars[$n]}"
    done
    emit "$out"
}

while IFS= read -r line <&"$cava_fd"; do
    convert_to_bars "$line"
done
