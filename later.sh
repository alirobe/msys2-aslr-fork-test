#!/bin/bash
# The later-read case: bash is up, then a native process reads the runtime DLL, then bash forks.
uname -srv
read -r w < /proc/$$/winpid; read -r pp < /proc/$$/ppid; echo "winpid $w ppid $pp"
/probe-entry.sh before 0
cmd //c "copy /b C:\\msys64\\usr\\bin\\msys-2.0.dll nul" > /dev/null; echo "read by another process done rc $?"
/probe-entry.sh afterread 0
/scale.sh 100 2 25; echo "scale rc $?"
