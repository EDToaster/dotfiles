#!/usr/bin/env bash

OUTPUT="/tmp/yazi-chooser-$$"
cleanup() { rm -f "$OUTPUT"; }
trap cleanup EXIT

YAZI_CMD="$(which yazi) --chooser-file '$OUTPUT'"

if [ -n "$1" ]; then
  YAZI_CMD+=" '$1'"
fi

if [ -n "$ZELLIJ" ]; then
  mkfifo "$OUTPUT"
  zellij run -n Yazi -ci -x 10% -y 10% --width 80% --height 80% -- bash -c "exec 3<> '$OUTPUT'; $YAZI_CMD; exec 3>&-"
elif [ -n "$CMUX_SOCKET_PATH" ]; then
  : > "$OUTPUT"
  cmux run --wait -- $YAZI_CMD
else
  exit 1
fi

if read -r line < "$OUTPUT"; then
  echo "$line"
else
  exit 1
fi
