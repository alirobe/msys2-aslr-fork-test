# A real git workflow through the install's own bash: hooks, a clone, an interactive rebase with editors, an alias.
export PATH=/mingw64/bin:/usr/bin:$PATH HOME=/tmp
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git config --global core.autocrlf false
rm -rf /tmp/w && mkdir -p /tmp/w && cd /tmp/w || exit 1
git init -q src && cd src || exit 1
printf '#!/bin/sh\necho hook ran >> ../hooklog\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
n=0; i=0; while [ $i -lt 50 ]; do i=$((i+1)); echo $i > f$i; git add f$i; git commit -q -m "c$i" && n=$((n+1)); done
echo "commits: $n/50  hook runs: $(grep -c hook ../hooklog 2>/dev/null)/50"
cd .. && git clone -q src clone && cd clone && echo "clone: $(git rev-list --count HEAD)/50 commits"
GIT_SEQUENCE_EDITOR='sed -i s/^pick/reword/' GIT_EDITOR='sed -i s/^c/r/' git rebase -i -q HEAD~5 >/dev/null 2>&1 && echo "rebase with editors: $(git log --format=%s -5 | grep -c ^r)/5 reworded" || echo "rebase with editors: failed"
git config alias.hi '!echo hi' && echo "shell alias: $(git hi)"
echo "log via pager pipe: $(git log --oneline | wc -l) lines"
