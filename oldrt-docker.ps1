# Runs on a GitHub Actions Windows runner. Reproduction attempt for the December 2022 report of pacman fork failures in
# Docker after the MSYS2 runtime gained dynamicbase. Puts the 2022-12-16 MSYS2 base in a container with three runtimes:
# msys2-runtime 3.4.3-1 as built on 2022-12-16 with dynamicbase (rebuilt from that PKGBUILD), the same with the bit
# cleared (what MSYS2 shipped the next day), and its own 3.3.6 (pre-ASLR) as the control. Exercises pacman without
# upgrading anything (keys, db sync, -Qk) and then the fork scale test. (Today's runtime in the 2022 base stalls in a
# pacman query, a 2022 userland on a 2026 runtime, so it is not run here; the 2026 base covers today's runtime.)
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2022", [string[]]$Isolations = @('process', 'hyperv'),
      [string]$OldRuntimePkg, [string]$OldRuntimeDll, [string]$OldRuntimeUrl)
$ErrorActionPreference = "Continue"
# windows-2025 runners sometimes come up without the Docker service running.
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2022-12-16/msys2-base-x86_64-20221216.sfx.exe" -OutFile "$root\base2022.sfx.exe"
& "$root\base2022.sfx.exe" -y -o"$root\ctx" | Out-Null
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-20260927.sfx.exe" -OutFile "$root\base2026.sfx.exe"
& "$root\base2026.sfx.exe" -y -o"$root\now" | Out-Null
Start-Sleep 5
New-Item -ItemType Directory "$root\ctx\rt" | Out-Null
Copy-Item "$root\ctx\msys64\usr\bin\msys-2.0.dll" "$root\ctx\rt\msys-2.0.dll.336"
Copy-Item "$root\now\msys64\usr\bin\msys-2.0.dll" "$root\ctx\rt\msys-2.0.dll.now"
if ($OldRuntimeUrl) { Invoke-WebRequest -Uri $OldRuntimeUrl -OutFile "$root\ctx\rt\msys-2.0.dll.343" }
elseif ($OldRuntimeDll) { Copy-Item $OldRuntimeDll "$root\ctx\rt\msys-2.0.dll.343" }
elseif ($OldRuntimePkg) { & "$root\now\msys64\usr\bin\bash.exe" -lc "tar -xf '$(& "$root\now\msys64\usr\bin\cygpath.exe" -u $OldRuntimePkg)' -C /tmp usr/bin/msys-2.0.dll && cp /tmp/usr/bin/msys-2.0.dll '$(& "$root\now\msys64\usr\bin\cygpath.exe" -u "$root\ctx\rt\msys-2.0.dll.343")'" }
Copy-Item "$root\oldrt-test.ps1" "$root\ctx\"
(Get-Content "$root\scale.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\ctx\msys64\scale.sh" -NoNewline
(Get-Content "$root\probe-exe.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\ctx\msys64\probe-exe.sh" -NoNewline
& "$root\pe-flags.ps1" -Paths (Get-ChildItem "$root\ctx\rt\*" | ForEach-Object FullName)
@"
FROM $Base
COPY msys64 C:/msys64
COPY rt C:/rt
COPY oldrt-test.ps1 C:/oldrt-test.ps1
"@ | Set-Content "$root\ctx\Dockerfile"
docker build -t oldrt-test -f "$root\ctx\Dockerfile" "$root\ctx" | Out-Null
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)  base: $Base"
docker info --format 'docker {{.ServerVersion}} isolation={{.Isolation}} kernel={{.KernelVersion}}'
# Detached run with a cap: the 2022 gnupg leaves gpg-agent behind, and an attached `docker run` of a Hyper-V container
# then never returns. docker logs has the script's output either way.
function RunContainer($image, $iso, $script, $variant, $minutes) {
  $id = "$(docker run -d --isolation=$iso $image powershell -ExecutionPolicy Bypass -File $script -Variant $variant 2>&1 | Select-Object -Last 1)".Trim()
  if ($id -notmatch '^[0-9a-f]{12,}$') { "docker run failed: $id"; return }
  $deadline = (Get-Date).AddMinutes($minutes)
  do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
  docker logs $id 2>&1 | ForEach-Object { "$_" }
  if ($running -eq 'true') { "container still running after $minutes min; killing it" }
  $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru
  if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
}$variants = @('336')
if (Test-Path "$root\ctx\rt\msys-2.0.dll.343") { $variants = @('343', '343-nodyn', '336') }
foreach ($iso in $Isolations) {
  foreach ($v in $variants) {
    "################ isolation=$iso runtime=$v"
    RunContainer 'oldrt-test' $iso 'C:\oldrt-test.ps1' $v 15
  }
}
"done"
