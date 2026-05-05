#!/usr/bin/env bash

popup() {
  local fn="$1"

  if [[ -z "$fn" ]]; then
    echo "Error: expected 1 argument to function popup" >&2
    return 1
  fi
  
  local output="/tmp/yazi-chooser-$$"
  trap "rm -f $output" RETURN

  local cmd=$("$fn" "$output")

  if [ -n "$ZELLIJ" ]; then
    mkfifo "$output"
    # redirect zellij stdout as it prints the terminal ID
    zellij run -n Yazi -ci -- bash -c "exec 3<> '$output'; $cmd; exec 3>&-" >/dev/null 2>&1
  elif [ -n "$CMUX_SOCKET_PATH" ]; then
    : > "$output"
    cmux run --wait -- $cmd
  else
    : > "$output"
    eval "$cmd"
  fi
  
  if read -r line < "$output" || [ -n "$line" ]; then
    echo "$line"
  else
    return 2
  fi

  return 0
}
