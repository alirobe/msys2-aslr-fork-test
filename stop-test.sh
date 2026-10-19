#!/bin/bash
# Entry bash for a docker stop test: traps HUP and TERM, then waits. Shows whether a stop reaches the shell as a
# signal and what exit code the container reports, for the shipped runtime and the re-exec one alike.
trap 'echo "bash got a signal"; exit 42' HUP TERM INT
read -r w < /proc/$$/winpid; read -r pp < /proc/$$/ppid; echo "bash winpid $w cygwin ppid $pp"
echo "WAITING for docker stop"
for i in $(seq 1 120); do sleep 1; done
echo "no stop arrived"
exit 7
