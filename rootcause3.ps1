# Runs on a GitHub Actions Windows runner. Third root-cause pass on the Server 2019 Hyper-V fork failure: which copy of
# a file an image map gets over the container's first seconds, by layer placement and with a read first, plus the
# container's boot timeline and filter state; then bash started late, bash after a read, and a single-layer image.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2019",
      [string]$TodayPkgUrl = "https://repo.msys2.org/msys/x86_64/msys2-runtime-3.6.11-3-x86_64.pkg.tar.zst", [int]$N = 16,
      [int]$Round = 3, [string]$Isolation = 'hyperv', [switch]$Parallel,
      [string]$PatchedDllUrl = "https://github.com/alirobe/msys2-aslr-fork-test/releases/download/patched-3.6.11-attr-open/msys-2.0.dll",
      [string]$ReexecDllUrl = "https://github.com/alirobe/msys2-aslr-fork-test/releases/download/reexec2-3.6.11/msys-2.0.dll",
      [string]$BeforeDllUrl = "https://github.com/alirobe/msys2-aslr-fork-test/releases/download/reexec2-3.6.11/msys-2.0.dll")
$ErrorActionPreference = "Continue"
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
# Downloads are cached under cache\ by URL path, so a host that runs many rounds fetches each file once.
$cache = Join-Path $root 'cache'; New-Item -ItemType Directory -Path $cache -Force | Out-Null
function Fetch([string]$url, [string]$out) {
  if (Test-Path -LiteralPath $url) { Copy-Item $url $out -Force; return }   # a local file works in place of a URL
  $key = Join-Path $cache (($url -replace '^https?://', '') -replace '[\\/:*?"<>|]', '_')
  if (-not (Test-Path $key)) { Invoke-WebRequest -Uri $url -OutFile $key }
  Copy-Item $key $out -Force
}
"stage: downloads"
Fetch "https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-20260927.sfx.exe" "$root\base2026.sfx.exe"
if (Test-Path "$root\c26") { Remove-Item "$root\c26" -Recurse -Force }
& "$root\base2026.sfx.exe" -y -o"$root\c26" | Out-Null
Start-Sleep 5
Fetch $TodayPkgUrl "$root\today.pkg.tar.zst"
$tu = & "$root\c26\msys64\usr\bin\cygpath.exe" -u $root
& "$root\c26\msys64\usr\bin\bash.exe" -lc "cd '$tu' && mkdir -p t && tar -xf today.pkg.tar.zst -C t usr/bin/msys-2.0.dll && cp t/usr/bin/msys-2.0.dll flagged.dll && rm -rf t" | Out-Null
$flagged = "$root\flagged.dll"; $plain = "$root\c26\msys64\usr\bin\msys-2.0.dll"
"stage: layout"
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -out:"$root\sampler.exe" "$root\sampler.cs"
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -out:"$root\sampler2.exe" "$root\sampler2.cs"
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -out:"$root\loader.exe" "$root\loader.cs"
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -out:"$root\sampler3.exe" "$root\sampler3.cs"
(Get-Content "$root\probe-entry.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\c26\msys64\probe-entry.sh" -NoNewline
Copy-Item "$root\probe-ps.ps1" "$root\c26\msys64\"
foreach ($sh in 'scale.sh', 'later.sh', 'exit7.sh', 'edge.sh') { (Get-Content "$root\$sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\c26\msys64\$sh" -NoNewline }
# Lower layer: the tree, L* (flagged, only here) and B* (unflagged here, flagged copies on top).
$s = "$root\c26\samp"; New-Item -ItemType Directory "$s\lower", "$s\both" -Force | Out-Null
Copy-Item "$root\stdin.cmd", "$root\sampler.exe", "$root\sampler2.exe", "$root\sampler.cmd", "$root\timeline.ps1", "$root\late.cmd", "$root\readfirst.cmd", "$root\s1-access.cmd", "$root\s2-share.cmd", "$root\s3-strace.cmd", "$root\s4-etw.cmd", "$root\s5-nosysmain.cmd", "$root\loader.exe", "$root\s6-loader.cmd", "$root\sampler3.exe", "$root\s7-ops.cmd", "$root\readtrace.ps1", "$root\s8-bits.cmd", "$root\s9-evict.cmd", "$root\s10-pending.cmd" $s
# Top layer: the flagged runtime over the tree's own, T* and R* (only here) and the flagged B*.
$t = "$root\top"; New-Item -ItemType Directory "$t\samp\top", "$t\samp\both" -Force | Out-Null
Copy-Item $flagged "$t\msys-2.0.dll"
foreach ($k in 1..$N) {
  $id = '{0:00}' -f $k
  Copy-Item $flagged "$s\lower\L$id.dll"; Copy-Item $plain "$s\both\B$id.dll"
  Copy-Item $flagged "$t\samp\top\T$id.dll"; Copy-Item $flagged "$t\samp\top\R$id.dll"; Copy-Item $flagged "$t\samp\both\B$id.dll"
}
"stage: docker build"
"FROM $Base`nCOPY msys64 C:/msys64`nCOPY samp C:/samp" | Set-Content "$root\c26\Dockerfile.base"
"FROM rc3-base`nCOPY msys-2.0.dll C:/msys64/usr/bin/msys-2.0.dll`nCOPY samp C:/samp`nRUN mkdir C:\samp\plain && copy C:\Windows\System32\version.dll C:\samp\plain\P01.dll" | Set-Content "$t\Dockerfile.top"
docker build -t rc3-base -f "$root\c26\Dockerfile.base" "$root\c26" | Select-Object -Last 1
# The RUN step needs Hyper-V isolation: the 2019 image cannot run process-isolated on the 2022 host.
docker build --isolation=$Isolation -t rc3-top -f "$t\Dockerfile.top" $t 2>&1 | Select-Object -Last 3
# Single layer: the flagged runtime already in the tree when it is copied in, so no copy of it sits underneath.
Copy-Item $flagged $plain -Force
docker build -t rc3-single -f "$root\c26\Dockerfile.base" "$root\c26" | Select-Object -Last 1
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  base: $Base  isolation: $Isolation"
function Cap([string]$a, [int]$sec) {
  $o = "$root\cap.out"; $e = "$root\cap.err"
  $p = Start-Process docker -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($sec * 1000)) { "  (timed out after $sec s)"; try { $p.Kill() } catch {} ; Start-Sleep 2 }
  Get-Content $o, $e -ErrorAction SilentlyContinue
}
$bash = 'C:\msys64\usr\bin\bash.exe --norc --noprofile'
$ps = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$script:pending = @()
function Collect {
  # Parallel mode: wait for every queued container, then print each one's log in launch order.
  foreach ($q in $script:pending) {
    $deadline = (Get-Date).AddMinutes(10)
    do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $q.Id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
    "################ $($q.Label)  ($($q.Image): $($q.Entry))"
    if ($running -eq 'true') { "still running after 10 min; killing" }
    docker logs $q.Id 2>&1 | Where-Object { "$_" -notmatch 'fork: retry' } | ForEach-Object { "$_" }
    "exit code: $(docker inspect -f '{{.State.ExitCode}}' $q.Id)"
    $p = Start-Process docker -ArgumentList "rm -f $($q.Id)" -NoNewWindow -PassThru; if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
  }
  $script:pending = @()
}
function Probe($image, $label, [string]$entry, [string]$extra = '') {
  if (-not $Parallel) { "################ $label  (${image}: $entry)" }
  $id = "$(Invoke-Expression "docker run -d $extra --isolation=$Isolation --user ContainerAdministrator -e MSYSTEM=MSYS -e 'PATH=C:\msys64\usr\bin;C:\cygwin\bin;C:\Windows\System32;C:\Windows' $image $entry" 2>&1 | Select-Object -Last 1)".Trim()
  if ($id -notmatch '^[0-9a-f]{12,}$') { "################ $label  (${image}: $entry)"; "docker run failed: $id"; return }
  if ($Parallel) { "started $label -> $($id.Substring(0, 12))"; $script:pending += [pscustomobject]@{ Id = $id; Label = $label; Image = $image; Entry = $entry }; return }
  $deadline = (Get-Date).AddMinutes(6)
  do { Start-Sleep 3; $log = docker logs $id 2>&1 | Out-String; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($log -notmatch 'WAITING' -and $running -eq 'true' -and (Get-Date) -lt $deadline)
  if ($log -match 'WAITING') {
    "--- docker exec powershell: process tree, runtime bases, ASLR policy"
    Cap "exec $id $ps -NoProfile -ExecutionPolicy Bypass -File C:\msys64\probe-ps.ps1" 60
    "--- docker exec bash: a second root bash in the same container"
    Cap "exec $id $bash /probe-entry.sh exec-side 0" 90
  }
  $deadline = (Get-Date).AddMinutes(4)
  do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
  "--- entry log"
  docker logs $id 2>&1 | Where-Object { "$_" -notmatch 'fork: retry' } | ForEach-Object { "$_" }
  "exit code: $(docker inspect -f '{{.State.ExitCode}}' $id)"
  $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru; if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
}
if ($Round -eq 20) {
  # After the entry bash (build under test, all-flagged image from round 16) has started and swept: where does a fresh
  # native map of gmp, bash.exe and the runtime come from, and what do the live processes map?
  if (-not (docker image inspect rc3-all-after 2>$null)) { "rc3-all-after missing; run round 16 first"; return }
  "FROM rc3-all-after`nCOPY samp C:/samp`nCOPY msys64/probe-ps.ps1 C:/msys64/probe-ps.ps1" | Set-Content "$root\c26\Dockerfile.probe"
  docker build -t rc3-all-after-probe -f "$root\c26\Dockerfile.probe" "$root\c26" | Select-Object -Last 1
  $id = "$(Invoke-Expression "docker run -d --isolation=$Isolation --user ContainerAdministrator -e MSYSTEM=MSYS -e 'PATH=C:\msys64\usr\bin;C:\Windows\System32;C:\Windows' rc3-all-after-probe $bash /probe-entry.sh entry 90" 2>&1 | Select-Object -Last 1)".Trim()
  if ($id -notmatch '^[0-9a-f]{12,}$') { "docker run failed: $id"; return }
  $deadline = (Get-Date).AddMinutes(4)
  do { Start-Sleep 3; $log = docker logs $id 2>&1 | Out-String } while ($log -notmatch 'WAITING' -and (Get-Date) -lt $deadline)
  "--- fresh native maps while the entry bash waits"
  foreach ($f in 'C:\msys64\usr\bin\msys-gmp-10.dll', 'C:\msys64\usr\bin\msys-iconv-2.dll', 'C:\msys64\usr\bin\gawk.exe', 'C:\msys64\usr\bin\bash.exe', 'C:\msys64\usr\bin\msys-2.0.dll', 'C:\msys64\usr\lib\gawk\fork.dll') { Cap "exec $id C:\samp\sampler3.exe map $f" 60 }
  "--- live processes"
  Cap "exec $id C:\samp\sampler3.exe procs C:\" 60
  "--- gawk started by docker exec: its gmp, then gmp read, then its forks"
  Cap "exec $id C:\msys64\usr\bin\gawk.exe -v DLL=/usr/bin/msys-gmp-10.dll -f /gawk-later.awk" 120
  Cap "exec $id C:\samp\sampler3.exe map C:\msys64\usr\bin\msys-gmp-10.dll" 60
  $deadline = (Get-Date).AddMinutes(3)
  do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
  "--- entry log"; docker logs $id 2>&1 | Where-Object { "$_" -notmatch 'fork: retry' } | ForEach-Object { "$_" }
  $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru; if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
  "done"; return
}
if ($Round -eq 19) {
  Probe rc3-top 'is a swept file moved when the open returns: fresh maps at once and after 10 s; a read-open-only file mapped at once' "cmd /c C:\samp\s10-pending.cmd"
  Collect; "done"; return
}
if ($Round -eq 18) {
  # Seen from outside: which file the wrapper, the re-exec'd root and a fork child map the exe and the runtime from, in
  # the all-flagged image with the build under test (rc3-all-after, from round 16) and round 13's rc3-reexec.
  $Parallel = $false
  foreach ($img in 'rc3-all-after', 'rc3-reexec') {
    if (-not (docker image inspect $img 2>$null)) { "$img missing; run round 16 or 13 first"; continue }
    "FROM $img`nCOPY samp C:/samp" | Set-Content "$root\c26\Dockerfile.probe"
    docker build -t "$img-probe" -f "$root\c26\Dockerfile.probe" "$root\c26" | Select-Object -Last 1
    Probe "$img-probe" "${img}: entry bash waits 60 s under observation, then forks" "$bash /probe-entry.sh entry 60"
  }
  "done"; return
}
if ($Round -eq 17) {
  Probe rc3-top 'does a moved file stay moved: after a sweep of 400 other files, after 30 s, under a held map' "cmd /c C:\samp\s9-evict.cmd"
  Collect; "done"; return
}
if ($Round -eq 16) {
  # Every DLL and exe under usr\ flagged dynamicbase. gawk as the entry process (a linked DLL, then the dlopen'd fork
  # extension, each read later by another process), and gawk spawned by an entry bash that never loaded gawk's DLLs.
  # The re-exec runtime as reviewed (before) and this build (after).
  $a = "$root\allf"; if (Test-Path $a) { Remove-Item $a -Recurse -Force }
  New-Item -ItemType Directory $a | Out-Null
  Copy-Item "$root\c26\msys64" "$a\msys64" -Recurse
  $n = 0; Get-ChildItem "$a\msys64\usr" -Recurse -Include *.dll, *.exe | ForEach-Object { SetFlag $_.FullName; $n++ }; "flagged $n DLLs and exes under usr"
  foreach ($f in 'gawk-later.awk', 'bash-then-gawk.sh', 'probe-entry.sh', 'scale.sh') { (Get-Content "$root\$f" -Raw) -replace "`r`n", "`n" | Set-Content "$a\msys64\$f" -NoNewline }
  Fetch $BeforeDllUrl "$a\before.dll"; Fetch $ReexecDllUrl "$a\after.dll"
  & "$root\pe-flags.ps1" -Paths "$a\before.dll", "$a\after.dll", "$a\msys64\usr\bin\bash.exe", "$a\msys64\usr\bin\gawk.exe", "$a\msys64\usr\bin\msys-gmp-10.dll", "$a\msys64\usr\lib\gawk\fork.dll"
  "FROM $Base`nCOPY msys64 C:/msys64" | Set-Content "$a\Dockerfile.all"
  docker build -t rc3-all -f "$a\Dockerfile.all" $a | Select-Object -Last 1
  foreach ($v in 'before', 'after') { "FROM rc3-all`nCOPY $v.dll C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$a\Dockerfile.$v"; docker build -t "rc3-all-$v" -f "$a\Dockerfile.$v" $a | Select-Object -Last 1 }
  $gawk = 'C:\msys64\usr\bin\gawk.exe'
  $scale = 'uname -srv; /probe-entry.sh entry 0; /scale.sh 300 4 50; echo scale rc $?'
  foreach ($v in 'before', 'after') {
    Probe "rc3-all-$v" "${v}: bash as entry, all flagged" "$bash -c `"$scale`""
    Probe "rc3-all-$v" "${v}: gawk as entry, a linked DLL read later" "$gawk -v DLL=/usr/bin/msys-gmp-10.dll -f /gawk-later.awk"
    Probe "rc3-all-$v" "${v}: gawk as entry, the dlopen'd fork extension read later" "$gawk -v DLL=/usr/lib/gawk/fork.dll -f /gawk-later.awk"
    Probe "rc3-all-$v" "${v}: bash as entry, gawk spawned later, its linked DLL read" "$bash /bash-then-gawk.sh"
  }
  Collect; "done"; return
}
if ($Round -eq 15) {
  # Upstream Cygwin in the same container: cygwin1.dll has carried dynamicbase since 3.4.0 and the same
  # init_installation_root open, so bash as the entry process should fail the same way. Current Cygwin from its
  # setup program, installed on this host, copied in as a layer.
  $cyg = "$root\cyg"; New-Item -ItemType Directory "$cyg\rt" -Force | Out-Null
  Fetch "https://cygwin.com/setup-x86_64.exe" "$cyg\setup.exe"
  if (-not (Test-Path "$cyg\cygwin\bin\bash.exe")) {
    $p = Start-Process -FilePath "$cyg\setup.exe" -ArgumentList @('-q', '-B', '-n', '-N', '-d', '-O', '-W', '-X', '-s', 'https://mirrors.kernel.org/sourceware/cygwin/', '-R', "$cyg\cygwin", '-l', "$cyg\pkgs", '-P', 'bash,coreutils,sed,gawk,grep,util-linux') -PassThru -Wait
    "cygwin setup exit $($p.ExitCode)"
  }
  foreach ($sh in 'probe-entry.sh', 'scale.sh', 'later.sh') {
    (Get-Content "$root\$sh" -Raw) -replace "`r`n", "`n" -replace 'msys-2.0.dll', 'cygwin1.dll' -replace 'C:\\\\msys64\\\\usr\\\\bin\\\\msys-2.0.dll', 'C:\\cygwin\\bin\\cygwin1.dll' -replace '/usr/bin:', '/bin:/usr/bin:' | Set-Content "$cyg\cygwin\$sh" -NoNewline
  }
  & "$root\pe-flags.ps1" -Paths "$cyg\cygwin\bin\cygwin1.dll"
  "FROM $Base`nCOPY cygwin C:/cygwin" | Set-Content "$cyg\Dockerfile"
  docker build -t rc3-cygwin -f "$cyg\Dockerfile" $cyg | Select-Object -Last 1
  $cbash = 'C:\cygwin\bin\bash.exe --norc --noprofile'
  $cscale = 'uname -srv; /probe-entry.sh entry 0; /scale.sh 300 4 50; echo scale rc $?'
  Probe rc3-cygwin 'cygwin: bash as entry' "$cbash -c `"$cscale`""
  Probe rc3-cygwin 'cygwin: later read' "$cbash /later.sh"
  Probe rc3-cygwin 'cygwin: bash started from cmd' "cmd /c $cbash -c `"$cscale`""
  Collect; "done"; return
}
if ($Round -eq 14) {
  # Re-exec edge cases on the general predicate build, with the attribute-only build alongside for comparison.
  Fetch $ReexecDllUrl "$t\reexec.dll"; Fetch $PatchedDllUrl "$t\patched.dll"
  foreach ($v in 'reexec', 'patched') { "FROM rc3-base`nCOPY $v.dll C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$t\Dockerfile.$v"; docker build -t "rc3-$v" -f "$t\Dockerfile.$v" $t | Select-Object -Last 1 }
  foreach ($v in 'reexec', 'patched') {
    Probe "rc3-$v" "$v edge cases, no tty" "$bash /edge.sh one 'two words' three"
    Probe "rc3-$v" "$v edge cases, with a tty" "$bash /edge.sh one 'two words' three" '-t'
    Probe "rc3-$v" "$v stdin through a pipe" "cmd /c C:\samp\stdin.cmd"
    Probe "rc3-$v" "$v pacman as the entry process" "C:\msys64\usr\bin\pacman.exe -Qk"
  }
  Collect; "done"; return
}
if ($Round -eq 13) {
  # The general re-exec predicate: entry bash, the later-read case and exit code in containers (run once per
  # isolation), plus a no-false-positive check on the host itself: bash from the extracted tree with the re-exec DLL
  # must keep the pid it was started with.
  Fetch $ReexecDllUrl "$t\reexec.dll"
  & "$root\pe-flags.ps1" -Paths "$t\reexec.dll"
  "FROM rc3-base`nCOPY reexec.dll C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$t\Dockerfile.reexec"
  docker build -t rc3-reexec -f "$t\Dockerfile.reexec" $t | Select-Object -Last 1
  "################ host check: no re-exec outside a container"
  Copy-Item "$t\reexec.dll" "$root\c26\msys64\usr\bin\msys-2.0.dll" -Force
  $env:MSYSTEM = 'MSYS'
  $p = Start-Process "$root\c26\msys64\usr\bin\bash.exe" -ArgumentList '--norc', '--noprofile', '-c', '"read -r w < /proc/$$/winpid; read -r pp < /proc/$$/ppid; echo bash winpid $w cygwin-ppid $pp; (echo fork ok)"' -NoNewWindow -PassThru -RedirectStandardOutput "$root\hostcheck.out" -RedirectStandardError "$root\hostcheck.err"
  $p.WaitForExit(60000) | Out-Null
  "started pid $($p.Id); " + (Get-Content "$root\hostcheck.out" -Raw) + (Get-Content "$root\hostcheck.err" -Raw)
  "(same winpid as started pid means no re-exec)"
  $scale = 'uname -srv; /probe-entry.sh entry 0; /scale.sh 300 4 50; echo scale rc $?'
  Probe rc3-reexec 're-exec runtime, bash as entry' "$bash -c `"$scale`""
  Probe rc3-reexec 're-exec runtime, later read' "$bash /later.sh"
  Probe rc3-reexec 're-exec runtime, exit code (expect 7)' "$bash /exit7.sh"
  Probe rc3-top 'shipped runtime, bash as entry, for comparison' "$bash -c `"$scale`""
  Collect; "done"; return
}
if ($Round -eq 12) {
  # The three runtimes as the container's entry bash under the chosen isolation, plus the map-source sampler.
  foreach ($pair in @(@('reexec', $ReexecDllUrl), @('patched', $PatchedDllUrl))) {
    Fetch $pair[1] "$t\$($pair[0]).dll"
    "FROM rc3-base`nCOPY $($pair[0]).dll C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$t\Dockerfile.$($pair[0])"
    docker build -t "rc3-$($pair[0])" -f "$t\Dockerfile.$($pair[0])" $t | Select-Object -Last 1
  }
  $scale = 'uname -srv; /probe-entry.sh entry 0; /scale.sh 300 4 50; echo scale rc $?'
  foreach ($img in 'rc3-top', 'rc3-patched', 'rc3-reexec') { Probe $img "entry bash ($img)" "$bash -c `"$scale`"" }
  Probe rc3-top 'later read on the shipped runtime' "$bash /later.sh"
  Probe rc3-top 'sampler: map source per placement every 2 s, then timeline' "cmd /c C:\samp\sampler.cmd"
  Collect; "done"; return
}
if ($Round -eq 10) {
  # The re-exec runtime (root process re-execs once when its DLL is mapped from the layer) vs the attribute-only patch
  # vs shipped: bash as entry, then the later-read case (bash starts, a native process reads the DLL, bash forks), then
  # exit-code propagation through the re-exec.
  foreach ($pair in @(@('reexec', $ReexecDllUrl), @('patched', $PatchedDllUrl))) {
    Fetch $pair[1] "$t\$($pair[0]).dll"
    "FROM rc3-base`nCOPY $($pair[0]).dll C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$t\Dockerfile.$($pair[0])"
    docker build -t "rc3-$($pair[0])" -f "$t\Dockerfile.$($pair[0])" $t | Select-Object -Last 1
  }
  & "$root\pe-flags.ps1" -Paths "$t\reexec.dll", "$t\patched.dll", "$t\msys-2.0.dll"
  "reexec sha256 $((Get-FileHash "$t\reexec.dll").Hash.ToLower().Substring(0, 12))  patched $((Get-FileHash "$t\patched.dll").Hash.ToLower().Substring(0, 12))  shipped $((Get-FileHash "$t\msys-2.0.dll").Hash.ToLower().Substring(0, 12))"
  $scale = 'uname -srv; /probe-entry.sh entry 0; /scale.sh 300 4 50; echo scale rc $?'
  Probe rc3-reexec 're-exec runtime, bash as entry: two forks, then the scale test' "$bash -c `"$scale`""
  foreach ($img in 'rc3-reexec', 'rc3-patched', 'rc3-top') {
    Probe $img "later read: bash starts, a native process reads the DLL, bash forks ($img)" "$bash /later.sh"
  }
  Probe rc3-reexec 'exit code through the re-exec (expect 7)' "$bash /exit7.sh"
  Collect; "done"; return
}
if ($Round -eq 9) {
  # The patched runtime (installation root found with an attribute-only open) over the same tree, bash as entry.
  Fetch $PatchedDllUrl "$t\patched.dll"
  & "$root\pe-flags.ps1" -Paths "$t\patched.dll", "$t\msys-2.0.dll"
  "patched sha256 $((Get-FileHash "$t\patched.dll").Hash.ToLower().Substring(0, 12))  shipped 3.6.11-3 sha256 $((Get-FileHash "$t\msys-2.0.dll").Hash.ToLower().Substring(0, 12))"
  "FROM rc3-base`nCOPY patched.dll C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$t\Dockerfile.patched"
  docker build -t rc3-patched -f "$t\Dockerfile.patched" $t | Select-Object -Last 1
  $scale = 'uname -srv; /probe-entry.sh entry 0; /scale.sh 300 4 50; echo scale rc $?'
  Probe rc3-patched 'patched runtime, bash as entry: two forks, then 300 subshells, 4x50 parallel, timeouts and pipes' "$bash -c `"$scale`""
  Probe rc3-top 'shipped 3.6.11-3, same command, for comparison' "$bash -c `"$scale`""
  Collect; "done"; return
}
if ($Round -eq 8) {
  Probe rc3-top 'access rights in a read open, one at a time; full load of a plain DLL as control' "cmd /c C:\samp\s8-bits.cmd"
  Collect; "done"; return
}
if ($Round -eq 7) {
  Probe rc3-top 'handle operations before the first map; kernel file traces of bash with and without a fork' "cmd /c C:\samp\s7-ops.cmd"
  Collect; "done"; return
}
if ($Round -eq 6) {
  Probe rc3-top 'loader test: plain exe, parent maps, child maps; kernel trace' "cmd /c C:\samp\s6-loader.cmd"
  Collect; "done"; return
}
if ($Round -eq 5) {
  Probe rc3-top 'kernel file trace of a failing fork' "cmd /c C:\samp\s4-etw.cmd"
  Probe rc3-top 'SysMain stopped, then bash' "cmd /c C:\samp\s5-nosysmain.cmd"
  Collect; "done"; return
}
if ($Round -eq 4) {
  Probe rc3-top 'access: attribute open, open, one-byte read, before the first map' "cmd /c C:\samp\s1-access.cmd"
  Probe rc3-top 'sharing: a held map, then a touch, then a new process maps' "cmd /c C:\samp\s2-share.cmd"
  Probe rc3-top 'strace of bash forking once, as entry' "cmd /c C:\samp\s3-strace.cmd"
  Collect; "done"; return
}
Probe rc3-top 'sampler: a fresh image map per placement every 2 s from container start, then timeline' "cmd /c C:\samp\sampler.cmd"
Probe rc3-top 'control: bash as entry' "$bash /probe-entry.sh entry 30"
Probe rc3-top 'late only: nothing touches the runtime until bash at about 20 s' "cmd /c C:\samp\late.cmd"
Probe rc3-top 'read first: copy the runtime to nul, then bash at once' "cmd /c C:\samp\readfirst.cmd"
Probe rc3-single 'single layer: flagged runtime with no copy underneath, bash as entry' "$bash /probe-entry.sh single 30"
Collect
"done"
