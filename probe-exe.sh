# Print where this process and a forked child have bash.exe and two DLLs mapped.
show() { while read -r l; do case "$l" in *"$1"*) echo "$2 $1 ${l%%-*}"; break;; esac; done < /proc/self/maps; }
for f in bash.exe msys-2.0.dll msys-iconv-2.dll; do show $f parent; done
( for f in bash.exe msys-2.0.dll; do show $f child; done )
