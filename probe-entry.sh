#!/bin/bash
# Fork root-cause probe. Everything before the fork test is a bash builtin, so nothing forks until then.
# Usage: probe-entry.sh TAG WAITSECONDS
tag=$1 wait=${2:-0}
read -r wp < /proc/$$/winpid
read -r pp < /proc/$$/ppid
read -r up _ < /proc/uptime
echo "[$tag] pid $$ winpid $wp ppid $pp uptime $up"
# First mapping of the exe and the runtime: base address and the file backing the image section.
maps() { local l; while IFS= read -r l; do case $l in *msys-2.0.dll*|*bash.exe*) [[ $l == *" 00000000 "* ]] && echo "  [$tag] $1 $l";; esac; done < /proc/$2/maps; }
maps parent $$
# Busy wait (no sleep, which would fork) so the host can look at this process from outside before any fork.
if (( wait > 0 )); then echo "[$tag] WAITING $wait s"; SECONDS=0; while (( SECONDS < wait )); do :; done; fi
echo "[$tag] FORKTEST"
for i in 1 2; do
  ( read -r cw < /proc/$BASHPID/winpid; echo "  [$tag] child $i pid $BASHPID winpid $cw"; maps child $BASHPID )
  echo "[$tag] fork $i rc $?"
done
echo "[$tag] done"
