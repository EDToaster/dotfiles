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
  elif [ -n "$HERDR_ENV" ]; then
    mkfifo "$output"
    # herdr has no CLI popup for arbitrary commands (popup placement is
    # plugin-only), so open a pane, zoom it to a full-screen overlay, run the
    # command there, and let the pane close itself once the command exits. The
    # fifo (held open via fd 3) both unblocks the read below and lets an
    # unpicked exit report EOF instead of hanging.
    local pane_id
    pane_id=$(herdr pane split --current --direction down --focus 2>/dev/null \
      | grep -oE '"pane_id":"[^"]+"' | head -1 | cut -d'"' -f4)
    if [ -n "$pane_id" ]; then
      herdr pane zoom "$pane_id" --on >/dev/null 2>&1
      herdr pane run "$pane_id" \
        "bash -c \"exec 3<> '$output'; $cmd; exec 3>&-; herdr pane close '$pane_id'\"" \
        >/dev/null 2>&1
    else
      # split failed: unblock the read below with EOF so we don't hang forever
      echo "Error: herdr pane split failed" >&2
      exec 3<> "$output"; exec 3>&-
    fi
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
