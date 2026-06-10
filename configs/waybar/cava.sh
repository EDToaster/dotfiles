#!/bin/bash
# Streams a unicode-bar audio visualizer from CAVA for the custom/cava
# module, and blanks the bar after ~2s of silence.
#
# Designed to die quietly when waybar exits: the read loop runs in the
# main shell (not a pipeline subshell), writes are guarded against a
# broken pipe, and the CAVA child is reaped on exit.

# Unicode bars (levels 0–8)
# bars=(" " ▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
# bars=(" " ⡀ ⢀ ⣀ ⣄ ⣠ ⣤ ⣦ ⣴ ⣶ ⣷ ⣾ ⣿)
bars=(" " ⡀ ⣀ ⣄ ⣤ ⣦ ⣶ ⣷ ⣿)

# Write a throwaway CAVA config that emits raw ascii to stdout.
config_file="/tmp/waybar_cava_config"
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
    # now=$(date +%s)

    # All-zero line == silence
    # if [[ "$line" =~ ^(0;?)+$ ]]; then
    #     (( pause_start == 0 )) && pause_start=$now

    #     # Hide after 2 seconds of continuous silence.
    #     if (( now - pause_start >= 2 )); then
    #         emit ""
    #     else
    #         convert_to_bars "$line"
    #     fi
    #     continue
    # fi

    # Audio is back — reset the silence timer and draw.
    # pause_start=0
    convert_to_bars "$line"
done
