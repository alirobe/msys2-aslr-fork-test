# gawk as the container's entry process, or spawned later by bash: forks (the fork extension, a dlopen'd DLL), then
# another process reads the DLL named by -v DLL=..., then forks again. Every DLL is dynamicbase in the test image, so a
# mapping that moved shows as a failed fork. DLL is /usr/bin/msys-gmp-10.dll (linked) or /usr/lib/gawk/fork.dll (dlopen'd).
@load "fork"
function forks(label,  i, ok, pid) {
  ok = 0; fflush()
  for (i = 1; i <= 5; i++) {
    pid = fork()
    if (pid == 0) exit 0
    if (pid < 0) { print "  fork failed, errno " ERRNO; continue }
    waitpid(pid); ok++
  }
  print label ": " ok "/5 forks ok"
}
BEGIN {
  print "gawk " PROCINFO["version"] " pid " PROCINFO["pid"]; fflush()
  forks("before read")
  system("cat " DLL " > /dev/null"); print DLL " read by another process"; fflush()
  forks("after read")
  print "gawk-later done"
}
