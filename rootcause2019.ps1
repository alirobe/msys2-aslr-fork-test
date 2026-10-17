# Runs on a GitHub Actions Windows runner. Root-cause probe for the Server 2019 Hyper-V fork failure (msys2-runtime#381):
# bash as the container's entry process fails its first fork with "dll data read copy failed", bash under PowerShell passes.
# "dll data" is the runtime DLL's own .data section, so the question is where msys-2.0.dll loads in the entry bash, in a
# bash started by docker exec in the same container, and in their fork children, with and without the dynamicbase flag.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2019", [int]$Wait = 120,
      [string]$TodayPkgUrl = "https://repo.msys2.org/msys/x86_64/msys2-runtime-3.6.11-3-x86_64.pkg.tar.zst")
$ErrorActionPreference = "Continue"
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
"stage: downloads"
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2022-12-16/msys2-base-x86_64-20221216.sfx.exe" -OutFile "$root\base2022.sfx.exe"
& "$root\base2022.sfx.exe" -y -o"$root\c22" | Out-Null
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-20260927.sfx.exe" -OutFile "$root\base2026.sfx.exe"
& "$root\base2026.sfx.exe" -y -o"$root\c26" | Out-Null
Start-Sleep 5
Invoke-WebRequest -Uri $TodayPkgUrl -OutFile "$root\today.pkg.tar.zst"
$bash26 = "$root\c26\msys64\usr\bin\bash.exe"
$tu = & "$root\c26\msys64\usr\bin\cygpath.exe" -u $root
& $bash26 -lc "cd '$tu' && mkdir -p t && tar -xf today.pkg.tar.zst -C t usr/bin/msys-2.0.dll && cp t/usr/bin/msys-2.0.dll c26/msys-2.0.dll.now && cp t/usr/bin/msys-2.0.dll c22/msys-2.0.dll.now && rm -rf t"
foreach ($c in 'c22', 'c26') {
  (Get-Content "$root\probe-entry.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\$c\msys64\probe-entry.sh" -NoNewline
  Copy-Item "$root\probe-ps.ps1" "$root\$c\msys64\probe-ps.ps1"
}
function PeInfo($p) {
  $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $n = [BitConverter]::ToUInt16($b, $pe + 6)
  $opt = $pe + 24; $s = $opt + [BitConverter]::ToUInt16($b, $pe + 20)
  $secs = for ($i = 0; $i -lt $n; $i++) { $o = $s + 40 * $i; "{0}@0x{1:X}" -f [Text.Encoding]::ASCII.GetString($b, $o, 8).Trim([char]0), [BitConverter]::ToUInt32($b, $o + 12) }
  "{0}: ImageBase 0x{1:X} SizeOfImage 0x{2:X} DllCharacteristics 0x{3:X} sections {4}" -f $p.Replace($root, ''), [BitConverter]::ToUInt64($b, $opt + 24), [BitConverter]::ToUInt32($b, $opt + 56), [BitConverter]::ToUInt16($b, $opt + 70), ($secs -join ' ')
}
PeInfo "$root\c26\msys64\usr\bin\msys-2.0.dll"
PeInfo "$root\c26\msys-2.0.dll.now"
PeInfo "$root\c22\msys64\usr\bin\msys-2.0.dll"
"stage: docker build"
"FROM $Base`nCOPY msys64 C:/msys64" | Set-Content "$root\c26\Dockerfile.noflag"
"FROM rc-noflag26`nCOPY msys-2.0.dll.now C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$root\c26\Dockerfile.flag"
"FROM $Base`nCOPY msys64 C:/msys64`nCOPY msys-2.0.dll.now C:/msys64/usr/bin/msys-2.0.dll" | Set-Content "$root\c22\Dockerfile.flag"
docker build -t rc-noflag26 -f "$root\c26\Dockerfile.noflag" "$root\c26" | Select-Object -Last 1
docker build -t rc-flag26 -f "$root\c26\Dockerfile.flag" "$root\c26" | Select-Object -Last 1
docker build -t rc-flag22 -f "$root\c22\Dockerfile.flag" "$root\c22" | Select-Object -Last 1
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  base: $Base"
# docker exec under Hyper-V isolation can hang; run each with a cap and capture through files.
function Cap([string]$a, [int]$sec) {
  $o = "$root\cap.out"; $e = "$root\cap.err"
  $p = Start-Process docker -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($sec * 1000)) { "  (timed out after $sec s)"; try { $p.Kill() } catch {} ; Start-Sleep 2 }
  Get-Content $o, $e -ErrorAction SilentlyContinue
}
$bash = 'C:\msys64\usr\bin\bash.exe --norc --noprofile'
function Probe($image, $label, [string]$entry) {
  "################ $label  (${image}: $entry)"
  $id = "$(Invoke-Expression "docker run -d --isolation=hyperv --user ContainerAdministrator -e MSYSTEM=MSYS -e 'PATH=C:\msys64\usr\bin;C:\Windows\System32;C:\Windows' $image $entry" 2>&1 | Select-Object -Last 1)".Trim()
  if ($id -notmatch '^[0-9a-f]{12,}$') { "docker run failed: $id"; return }
  $deadline = (Get-Date).AddMinutes(6)
  do { Start-Sleep 3; $log = docker logs $id 2>&1 | Out-String; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($log -notmatch 'WAITING' -and $running -eq 'true' -and (Get-Date) -lt $deadline)
  if ($log -match 'WAITING') {
    "--- docker exec powershell: process tree, runtime bases, ASLR policy"
    Cap "exec $id powershell -NoProfile -ExecutionPolicy Bypass -File C:\msys64\probe-ps.ps1" 60
    "--- docker exec bash: a second root bash in the same container"
    Cap "exec $id $bash /probe-entry.sh exec-side 0" 90
  } else { "entry never reached WAITING" }
  $deadline = (Get-Date).AddMinutes(4)
  do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
  "--- entry log"
  docker logs $id 2>&1 | Where-Object { "$_" -notmatch 'fork: retry' } | ForEach-Object { "$_" }
  "exit code: $(docker inspect -f '{{.State.ExitCode}}' $id)"
  $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru; if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
}
Probe rc-flag26 'flagged runtime, bash as entry' "$bash /probe-entry.sh entry $Wait"
Probe rc-flag26 'flagged runtime, powershell entry' "powershell -NoProfile -Command `"& C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh ps $Wait`""
Probe rc-flag26 'flagged runtime, cmd entry' "cmd /c $bash /probe-entry.sh cmd $Wait"
Probe rc-flag26 'flagged runtime, bash entry that execs bash' "$bash -c `"exec /usr/bin/bash --norc --noprofile /probe-entry.sh exec $Wait`""
Probe rc-noflag26 'unflagged runtime (2026 base as shipped), bash as entry' "$bash /probe-entry.sh noflag $Wait"
Probe rc-flag22 'flagged runtime in the 2022 tree, bash as entry' "$bash /probe-entry.sh tree22 $Wait"
"done"
