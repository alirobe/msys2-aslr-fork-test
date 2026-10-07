# Fork test for the MSYS2 runtime. Run by bash --norc; builtins only until the fork attempts.
export PATH=/usr/bin:$PATH
while read -r l; do case "$l" in *msys-2.0.dll*) echo "dll base: ${l%%-*}"; break;; esac; done < /proc/self/maps
echo "fork attempt: $(echo ok)"
n=0; i=0
while [ $i -lt 50 ]; do i=$((i+1)); x=$(echo $i) && n=$((n+1)); done
echo "fork loop: $n/50 succeeded"
echo "external: $(uname -r)"
