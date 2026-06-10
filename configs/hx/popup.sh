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
    # yazi ran nested inside helix's alternate screen and emitted its own
    # `CSI ?1049l` on exit, flipping the terminal back to the primary screen
    # while helix is still alive on the alt screen. Helix's `:redraw` then
    # paints onto the primary buffer and never gets cleared when helix quits.
    # Re-enter the alt screen here (to the tty, not stdout — stdout is the
    # chosen-file path helix reads) so `:redraw` lands back on the alt screen.
    #
    # yazi also emitted crossterm's `DisableMouseCapture`
    # (`CSI ?1006l ?1015l ?1003l ?1002l ?1000l`) on exit, turning off the mouse
    # tracking modes helix enabled at startup. Helix never re-enables them, so
    # the mouse goes dead. Re-emit crossterm's `EnableMouseCapture` sequences so
    # mouse reporting is restored for helix.
    printf '\e[?1049h\e[?1000h\e[?1002h\e[?1003h\e[?1015h\e[?1006h' > /dev/tty
  fi
  
  if read -r line < "$output" || [ -n "$line" ]; then
    echo "$line"
  else
    return 2
  fi

  return 0
}
