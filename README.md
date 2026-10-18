# msys2-aslr-fork-test

Reproducible tests behind the MSYS2 and Cygwin fork-under-ASLR work of October 2026
([msys2-runtime#381](https://github.com/msys2/msys2-runtime/pull/381),
[#386](https://github.com/msys2/msys2-runtime/pull/386), [#387](https://github.com/msys2/msys2-runtime/pull/387),
[MSYS2-packages#6789](https://github.com/msys2/MSYS2-packages/pull/6789)). The workflows under `.github/workflows/`
run most scripts on GitHub Actions Windows runners, and most also run on a Windows Server host with Docker;
`sysaslr-*.ps1` runs only on a host.
Run links in the PR comments point at these workflows.

## Root cause of the Server 2019 container fork failure

`rootcause3.ps1` is the harness; `-Round N` picks the experiment, `-Isolation process|hyperv` the container isolation,
`-Parallel` starts every container in a round at once, `-Base` the Windows image. Rounds, in the order they were run:

| Round | Question | Answer |
|---|---|---|
| 3 | Where does an image map of an untouched layer file come from, over the container's first 35 s, by layer placement? | Always the layer store, unless the file was read first; then the container volume |
| 4 | Which access makes a later map come from the volume? | An open with read access, even with nothing read; attribute-only opens don't |
| 5 | Is it the prefetcher? | No, same with SysMain stopped |
| 6 | Is it the loader? | No, a plain parent and child share one layer-store map |
| 7 | The runtime's own handle work (attribute open, file ID, by-ID open)? | None of it; a full load of the runtime DLL does, via its init |
| 8 | Which access rights? | FILE_READ_DATA and READ_CONTROL move the file; FILE_READ_ATTRIBUTES and FILE_READ_EA don't; a plain DLL's full load doesn't |
| 9 | Does opening for attributes only (#386) fix it? | Yes, as the entry bash, with the fork scale test |
| 10 | Does a re-exec of the root process fix it, and survive a later read by another process? | Yes to both; #386 fails after the later read |
| 12 | Process isolation on a Server 2019 host? | Same mechanism; #386 passes; the first #387 (VSMB prefix check) does not fire |
| 13 | The general re-exec predicate (mapping vs path) in both isolation modes, and no re-exec on a host? | Passes everywhere; no re-exec outside a container |
| 14 | Re-exec edge cases: argv, env marker, tty, piped stdin, exit codes, deep tree, pacman as entry | All pass; #386 fails its fork after `pacman -Qk` |
| 15 | Upstream Cygwin in the same containers? | Fails the same way, both isolation modes |

The cause: in a Windows Server 2019 container, a file from the image layers is mapped as an image straight from the
layer store until some process opens it with read access through the container volume; from then on new mappings come
from the volume at a different ASLR base. `init_installation_root` in the runtime does that open on its own DLL, so the
forked children of the first process load it elsewhere. The sampler programs (`sampler*.cs`, `loader.cs`) are the
instruments; `probe-entry.sh` prints each process's mappings from `/proc`.

## Other tests

- `oldrt2019-docker.ps1`: the December 2022 reproducer shape (Server 2019 image at its 2022 patch level under Hyper-V,
  the genuine 2022 runtime package and today's), copied in and upgraded in place by pacman.
- `cyg2022-docker.ps1`: upstream Cygwin as of December 2022 in Windows containers.
- `pacman-docker.ps1`, `oldrt-docker.ps1`, `run-tests.ps1`: full MSYS2 installs in containers, fork scale tests.
- `ifeo-all.ps1`, `deps-first.ps1`: Mandatory and Bottom-up ASLR forced per program on a runner, Portable Git with its
  DLLs and executables flagged in stages.
- `sysaslr-*.ps1`: the same with the policy set system-wide on a host (needs a reboot, so not a runner).
- `upgrade-hazard.sh`, `upgrade-hazard-gh.ps1`: a forking perl while one of its DLLs is replaced by an identical copy,
  without and with `/var/run/cygfork` (Cygwin's hard-link retry).
- `build-runtime.sh`: builds msys2-runtime from a fork clone on a lab host.

Prepared with Claude; the judgement calls were Ali Robertson's.
