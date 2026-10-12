# Scale fork test. N sequential subshells, P parallel loops of M subshells, then 200 each of timeout and a pipe to sed.
export PATH=/usr/bin:$PATH
N=${1:-2000}; P=${2:-8}; M=${3:-250}
n=0; i=0; while [ $i -lt $N ]; do i=$((i+1)); x=$(echo $i) && n=$((n+1)); done; echo "sequential subshell: $n/$N"
p=0; while [ $p -lt $P ]; do p=$((p+1)); ( n=0; i=0; while [ $i -lt $M ]; do i=$((i+1)); x=$(echo $i) && n=$((n+1)); done; echo "parallel loop $p: $n/$M" ) & done; wait
n=0; i=0; while [ $i -lt 200 ]; do i=$((i+1)); timeout 5 true && n=$((n+1)); done; echo "timeout: $n/200"
n=0; i=0; while [ $i -lt 200 ]; do i=$((i+1)); echo a | sed s/a/b/ >/dev/null && n=$((n+1)); done; echo "pipe to sed: $n/200"
