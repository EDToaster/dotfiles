#!/usr/bin/env bash
#
# reboot-windows.sh — reboot straight into Windows, once.
#
# Sets the UEFI one-shot BootNext variable to the "Windows Boot Manager" entry
# (bypassing Limine for this boot only), then reboots. The permanent BootOrder
# is untouched, so the following boot lands back in Limine as usual.
#
# Needs root for efibootmgr — elevated via pkexec (hyprpolkitagent prompts).

set -euo pipefail

entry=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? Windows Boot Manager.*/\1/p' | head -n1)

if [[ -z "$entry" ]]; then
  notify-send -u critical "Reboot to Windows" "No 'Windows Boot Manager' UEFI entry found."
  exit 1
fi

if ! err=$(pkexec efibootmgr --bootnext "$entry" 2>&1 >/dev/null); then
  notify-send -u critical "Reboot to Windows" "Failed to set BootNext: ${err:-auth cancelled?} (exit $?)"
  exit 1
fi

systemctl reboot
