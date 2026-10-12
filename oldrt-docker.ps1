# Runs on a GitHub Actions Windows runner. Reproduction attempt for the December 2022 report of pacman fork failures in
# Docker after the MSYS2 runtime gained dynamicbase. Puts the 2022-12-16 MSYS2 base in a container with four runtimes:
# its own 3.3.6 (pre-ASLR), msys2-runtime 3.4.3-1 as built on 2022-12-16 with dynamicbase (rebuilt from that PKGBUILD),
# the same with the bit cleared (what MSYS2 shipped the next day), and today's runtime flagged. Exercises pacman without
# upgrading anything (keys, db sync, -Qk) and then the fork scale test.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2022", [string[]]$Isolations = @('process', 'hyperv'),
      [string]$OldRuntimePkg, [string]$OldRuntimeDll, [string]$OldRuntimeUrl)
$ErrorActionPreference = "Continue"
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
$variants = @('336', 'now')
if (Test-Path "$root\ctx\rt\msys-2.0.dll.343") { $variants = @('336', '343', '343-nodyn', 'now') }
foreach ($iso in $Isolations) {
  foreach ($v in $variants) {
    "################ isolation=$iso runtime=$v"
    docker run --rm --isolation=$iso oldrt-test powershell -ExecutionPolicy Bypass -File C:\oldrt-test.ps1 -Variant $v 2>&1
  }
}
"done"
