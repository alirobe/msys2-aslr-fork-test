# Runs on a GitHub Actions Windows runner. Third root-cause pass on the Server 2019 Hyper-V fork failure: which copy of
# a file an image map gets over the container's first seconds, by layer placement and with a read first, plus the
# container's boot timeline and filter state; then bash started late, bash after a read, and a single-layer image.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2019",
      [string]$TodayPkgUrl = "https://repo.msys2.org/msys/x86_64/msys2-runtime-3.6.11-3-x86_64.pkg.tar.zst", [int]$N = 16,
      [int]$Round = 3)
$ErrorActionPreference = "Continue"
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
"stage: downloads"
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-20260927.sfx.exe" -OutFile "$root\base2026.sfx.exe"
& "$root\base2026.sfx.exe" -y -o"$root\c26" | Out-Null
Start-Sleep 5
Invoke-WebRequest -Uri $TodayPkgUrl -OutFile "$root\today.pkg.tar.zst"
$tu = & "$root\c26\msys64\usr\bin\cygpath.exe" -u $root
& "$root\c26\msys64\usr\bin\bash.exe" -lc "cd '$tu' && mkdir -p t && tar -xf today.pkg.tar.zst -C t usr/bin/msys-2.0.dll && cp t/usr/bin/msys-2.0.dll flagged.dll && rm -rf t" | Out-Null
$flagged = "$root\flagged.dll"; $plain = "$root\c26\msys64\usr\bin\msys-2.0.dll"
"stage: layout"
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -out:"$root\sampler.exe" "$root\sampler.cs"
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -out:"$root\sampler2.exe" "$root\sampler2.cs"
(Get-Content "$root\probe-entry.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\c26\msys64\probe-entry.sh" -NoNewline
Copy-Item "$root\probe-ps.ps1" "$root\c26\msys64\"
# Lower layer: the tree, L* (flagged, only here) and B* (unflagged here, flagged copies on top).
$s = "$root\c26\samp"; New-Item -ItemType Directory "$s\lower", "$s\both" -Force | Out-Null
Copy-Item "$root\sampler.exe", "$root\sampler2.exe", "$root\sampler.cmd", "$root\timeline.ps1", "$root\late.cmd", "$root\readfirst.cmd", "$root\s1-access.cmd", "$root\s2-share.cmd", "$root\s3-strace.cmd", "$root\s4-etw.cmd", "$root\s5-nosysmain.cmd" $s
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
"FROM rc3-base`nCOPY msys-2.0.dll C:/msys64/usr/bin/msys-2.0.dll`nCOPY samp C:/samp" | Set-Content "$t\Dockerfile.top"
docker build -t rc3-base -f "$root\c26\Dockerfile.base" "$root\c26" | Select-Object -Last 1
docker build -t rc3-top -f "$t\Dockerfile.top" $t | Select-Object -Last 1
# Single layer: the flagged runtime already in the tree when it is copied in, so no copy of it sits underneath.
Copy-Item $flagged $plain -Force
docker build -t rc3-single -f "$root\c26\Dockerfile.base" "$root\c26" | Select-Object -Last 1
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  base: $Base"
function Cap([string]$a, [int]$sec) {
  $o = "$root\cap.out"; $e = "$root\cap.err"
  $p = Start-Process docker -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($sec * 1000)) { "  (timed out after $sec s)"; try { $p.Kill() } catch {} ; Start-Sleep 2 }
  Get-Content $o, $e -ErrorAction SilentlyContinue
}
$bash = 'C:\msys64\usr\bin\bash.exe --norc --noprofile'
$ps = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
function Probe($image, $label, [string]$entry) {
  "################ $label  (${image}: $entry)"
  $id = "$(Invoke-Expression "docker run -d --isolation=hyperv --user ContainerAdministrator -e MSYSTEM=MSYS -e 'PATH=C:\msys64\usr\bin;C:\Windows\System32;C:\Windows' $image $entry" 2>&1 | Select-Object -Last 1)".Trim()
  if ($id -notmatch '^[0-9a-f]{12,}$') { "docker run failed: $id"; return }
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
if ($Round -eq 5) {
  Probe rc3-top 'kernel file trace of a failing fork' "cmd /c C:\samp\s4-etw.cmd"
  Probe rc3-top 'SysMain stopped, then bash' "cmd /c C:\samp\s5-nosysmain.cmd"
  "done"; return
}
if ($Round -eq 4) {
  Probe rc3-top 'access: attribute open, open, one-byte read, before the first map' "cmd /c C:\samp\s1-access.cmd"
  Probe rc3-top 'sharing: a held map, then a touch, then a new process maps' "cmd /c C:\samp\s2-share.cmd"
  Probe rc3-top 'strace of bash forking once, as entry' "cmd /c C:\samp\s3-strace.cmd"
  "done"; return
}
Probe rc3-top 'sampler: a fresh image map per placement every 2 s from container start, then timeline' "cmd /c C:\samp\sampler.cmd"
Probe rc3-top 'control: bash as entry' "$bash /probe-entry.sh entry 30"
Probe rc3-top 'late only: nothing touches the runtime until bash at about 20 s' "cmd /c C:\samp\late.cmd"
Probe rc3-top 'read first: copy the runtime to nul, then bash at once' "cmd /c C:\samp\readfirst.cmd"
Probe rc3-single 'single layer: flagged runtime with no copy underneath, bash as entry' "$bash /probe-entry.sh single 30"
"done"
