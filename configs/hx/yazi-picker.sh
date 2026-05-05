#!/usr/bin/env bash

. "${BASH_SOURCE%/*}/popup.sh"

YAZI_CMD="$(which yazi)"
if [[ -n "$1" ]]; then
  YAZI_CMD+=" '$1'"
fi

yazi_fn() {
  printf "$YAZI_CMD --chooser-file '$1'"
}

popup yazi_fn
