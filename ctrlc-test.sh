#!/bin/bash
# Entry bash, started with a tty: a child sends Ctrl+C to the console. Expected: this shell's INT trap runs, the
# shell is still alive afterwards, and the container exits with this script's exit code (5), not the wrapper's.
trap 'echo "bash got SIGINT"' INT
read -r w < /proc/$$/winpid; read -r pp < /proc/$$/ppid; echo "bash winpid $w cygwin ppid $pp"
echo "before ctrl-c"
/c/samp/ctrlc.exe
sleep 2
echo "alive after ctrl-c"
exit 5
