# Fork tests for a Git for Windows usr/bin copy. Run by bash --norc; PATH set first so externals resolve inside the copy.
export PATH=/usr/bin:$PATH
run() { local n=0 i=0; while [ $i -lt 50 ]; do i=$((i+1)); "$@" >/dev/null 2>&1 && n=$((n+1)); done; echo "$1: $n/50"; }
sub() { x=$(echo hi); }
pipe() { echo hi | sed s/h/H/ >/dev/null; }
to() { timeout 5 true; }
fx() { echo a | xargs true; }
run sub; run pipe; run to; run fx
