#!/usr/bin/env bash

CHOOSER="/tmp/yazi-chooser-$$"
cleanup() { rm -f "$CHOOSER"; }
trap cleanup EXIT

YAZI_CMD="$(which yazi) --chooser-file '$CHOOSER'"

if [ -n "$1" ]; then
  YAZI_CMD+=" '$1'"
fi

if [ -n "$CMUX_SOCKET_PATH" ]; then
  : > "$CHOOSER"
  cmux run --wait -- $YAZI_CMD
elif [ -n "$ZELLIJ" ]; then
  mkfifo "$CHOOSER"
  zellij run -n Yazi -ci -x 10% -y 10% --width 80% --height 80% -- bash -c "exec 3<> '$CHOOSER'; $YAZI_CMD; exec 3>&-"
else
  $YAZI_CMD
fi

if read -r line < "$CHOOSER"; then
  echo "$line"
else
  exit 1
fi
