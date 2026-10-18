#!/bin/bash
# bash as the entry process, gawk spawned later: gawk's linked DLLs were never loaded by the root process.
uname -srv
( : ); echo "bash fork rc $?"
gawk -v DLL=/usr/bin/msys-gmp-10.dll -f /gawk-later.awk
echo "bash-then-gawk done"
