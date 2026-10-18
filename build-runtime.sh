#!/bin/bash
# Build msys2-runtime from the fork clone in the lab VM. Usage: build-runtime.sh BRANCH
# Incremental: configure runs once, make only rebuilds what changed. The DLL lands in /c/lab/built/<branch>-<sha>.dll.
set -e
branch=$1
cd /c/lab/src/msys2-runtime
git fetch -q origin
git checkout -q "$branch"
git reset -q --hard "origin/$branch"
sha=$(git rev-parse --short HEAD)
echo "building $branch @ $sha"
[ -f winsup/configure ] || (cd winsup && ./autogen.sh > /c/lab/build-autogen.log 2>&1)
[ -f Makefile ] || ./configure --disable-dependency-tracking --with-msys2-runtime-commit="$(git rev-parse HEAD)" > /c/lab/build-configure.log 2>&1
start=$(date +%s)
if ! make -j10 > /c/lab/build-make.log 2>&1; then echo "make failed"; grep -n -i 'error' /c/lab/build-make.log | head -20; exit 1; fi
rm -rf /c/lab/dest && make DESTDIR=/c/lab/dest install > /c/lab/build-install.log 2>&1
mkdir -p /c/lab/built
cp /c/lab/dest/usr/bin/msys-2.0.dll "/c/lab/built/$branch-$sha.dll"
echo "built in $(( $(date +%s) - start )) s: /c/lab/built/$branch-$sha.dll ($(stat -c %s "/c/lab/built/$branch-$sha.dll") bytes)"
