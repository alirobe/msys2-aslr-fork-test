#!/bin/bash
# Re-exec edge cases, run as the container's entry bash with arguments.
printf 'argv:'; for a in "$@"; do printf ' [%s]' "$a"; done; echo
echo "marker in env: $(env | grep -c '^MSYS2_RUNTIME_REEXEC=')"
[ -t 0 ] && echo "stdin: tty" || echo "stdin: not a tty"
read -r pp < /proc/$$/ppid; echo "cygwin ppid: $pp"
bash -c 'bash -c "bash -c \"( : ); echo deep tree: fork ok at depth 3\""'
echo "pacman -Q count: $(pacman -Q | wc -l)"
pacman -Qk > /dev/null 2>&1; echo "pacman -Qk rc: $?"
bash -c 'exit 200'; echo "exit 200 seen as: $?"
bash -c 'kill -TERM $$'; echo "SIGTERM child seen as: $?"
echo "edge done"
