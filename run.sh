#!/usr/bin/env bash
#
# Runs a float's command. init.lua starts it in the float's terminal, in the
# directory the float opens in:
#
#   run.sh HOLD NAME COMMAND [ARG...]
#
# The float closes when this script exits. HOLD keeps it open until a key is
# pressed, so the command's last output can be read: "error" when the command
# fails, "always", or "never". Ctrl-C (status 130) is not a failure. NAME is
# the float's name, for the messages.
#
# Kept to bash 3.2, the one macOS ships.

set -u

wait_key() { printf '\n\033[2mpress any key to close\033[0m'; read -rsn1; }

if [[ $# -lt 3 ]]; then
  printf '\033[31m%s\033[0m\n' "usage: run.sh HOLD NAME COMMAND [ARG...]"
  wait_key
  exit 2
fi

hold=$1 name=$2
shift 2

# Job control runs the command in its own process group, in the foreground.
# Ctrl-C then stops only the command, and this script stays to hold the float
# open. Without it, bash also exits on the Ctrl-C.
set -m

"$@"
status=$?

case $hold in
  always) ;;
  error)  [[ $status -eq 0 || $status -eq 130 ]] && exit "$status" ;;
  *)      exit "$status" ;;
esac

if [[ $status -eq 0 ]]; then
  printf '\n\033[2m%s: done\033[0m' "$name"
else
  printf '\n\033[31m%s: exited with status %d\033[0m' "$name" "$status"
  [[ $status -eq 127 ]] && printf '\n\033[31m%s\033[0m' "The command was not found. Check its name and your PATH."
fi
wait_key
exit "$status"
