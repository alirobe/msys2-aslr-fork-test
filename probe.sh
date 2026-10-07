# Print the msys-2.0.dll base of this process (builtins only). Usage: bash --norc probe.sh LABEL
while read -r l; do case "$l" in *msys-2.0.dll*) echo "$1: ${l%%-*}"; break;; esac; done < /proc/self/maps
