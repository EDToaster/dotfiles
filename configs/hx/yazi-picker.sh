#!/usr/bin/env bash

FIFO="/tmp/yazi-fifo-$$"
mkfifo "$FIFO"

zellij run -n Yazi -ci -x 10% -y 10% --width 80% --height 80% -- \
  bash -c "
    # Open FIFO for reading and writing
    exec 3<> '$FIFO'
    if [ -n '$1' ]; then
      yazi --chooser-file '$FIFO' '$1'
    else
      yazi --chooser-file '$FIFO'
    fi
    # Close the FIFO after yazi finishes
    exec 3>&-
  "

if read -r line < "$FIFO"; then
  echo "$line"
else
  exit 1
fi
