#!/bin/bash
# Stromeko's report: everything dynamicbase "works almost too good", then forks fail until a hard rebase or a reboot.
# Hypothesis: a package upgrade replaces a DLL file that a running process has loaded; new processes map the new
# file at a new base, so the running process's forked children load it elsewhere. Cygwin's forkables (hard links of
# the loaded DLLs under /var/run/cygfork) are meant to cover exactly that. Here: perl forks in a loop while
# msys-perl5_42.dll is replaced by a byte-identical copy (new file identity), then by the original name again.
set -u
dll=$(ls /usr/bin/msys-perl5_*.dll | head -1); echo "dll under test: $dll"
echo "forkables dir: $(ls -d /var/run/cygfork 2>/dev/null || echo none)"
perl -e '
  $| = 1; my $n = 0;
  while (1) {
    my $p = fork;
    if (!defined $p) { print "fork FAILED: $!\n"; }
    elsif ($p == 0) { exit 0 }
    else { waitpid $p, 0; $n++; print "fork ok $n\n" if $n % 5 == 0; }
    sleep 1;
    open my $f, "<", "/tmp/stop" and last;
  }
  print "perl done after $n forks\n";
' 2>&1 | sed 's/^/  [perl] /' &
sleep 6
echo "replacing $dll with an identical copy (new file identity)"
cp "$dll" "$dll.new" && mv -f "$dll.new" "$dll"; echo "replace rc $?"
sleep 8
echo "and once more"
cp "$dll" "$dll.new" && mv -f "$dll.new" "$dll"; echo "replace rc $?"
sleep 8
touch /tmp/stop; wait
rm -f /tmp/stop
echo "forkables now: $(ls -R /var/run/cygfork 2>/dev/null | head -5 | tr '\n' ' ')"
echo "a fresh perl fork afterwards: $(perl -e 'my $p=fork; if($p==0){exit 0} waitpid $p,0; print "ok"')"
