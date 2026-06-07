#!/bin/bash
# Reports download/upload throughput on the active default-route
# interface, using bc for the byte→Mbps conversion.

# Prefer a real (non-tunnel) interface on the default route.
INTERFACE=$(ip route | grep '^default' | awk '{print $5}' \
  | grep -vE '^(tun|tap|vpn|ppp|wg)' | head -n 1)

# Fall back to whatever the first default route uses.
if [[ -z "$INTERFACE" ]]; then
  INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
fi

# No usable interface → show zeros and bail.
if [[ -z "$INTERFACE" ]] || [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
  echo "⇣ 0.00 Mbps ⇡ 0.00 Mbps"
  exit 0
fi

RX="/sys/class/net/$INTERFACE/statistics/rx_bytes"
TX="/sys/class/net/$INTERFACE/statistics/tx_bytes"
if [[ ! -f "$RX" || ! -f "$TX" ]]; then
  echo "⇣ 0.00 Mbps ⇡ 0.00 Mbps"
  exit 0
fi

RX_PREV=$(cat "$RX")
TX_PREV=$(cat "$TX")
sleep 1
RX_CURR=$(cat "$RX")
TX_CURR=$(cat "$TX")

RX_DIFF=$((RX_CURR - RX_PREV))
TX_DIFF=$((TX_CURR - TX_PREV))

# bytes * 8 / 1_000_000 = Mbps (per 1s sample)
RX_Mbps=$(echo "scale=2; $RX_DIFF * 8 / 1000000" | bc)
TX_Mbps=$(echo "scale=2; $TX_DIFF * 8 / 1000000" | bc)

# bc prints ".50" rather than "0.50"; pad a leading zero for looks.
[[ "$RX_Mbps" == .* ]] && RX_Mbps="0$RX_Mbps"
[[ "$TX_Mbps" == .* ]] && TX_Mbps="0$TX_Mbps"

echo "⇣ ${RX_Mbps} Mbps ⇡ ${TX_Mbps} Mbps"
