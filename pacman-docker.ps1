# Runs on a GitHub Actions Windows runner. Puts a full MSYS2 base install into a Windows container and exercises pacman
# (first launch, -Syu, install, remove) plus a fork scale test, with the runtime as shipped (stock), the runtime flagged
# dynamicbase (dyn) and every usr\bin DLL flagged (all). The 2022 report was pacman failing to fork inside Docker.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2022", [string[]]$Isolations = @('process', 'hyperv'),
      [string]$Release = "2026-09-27", [string]$Asset = "msys2-base-x86_64-20260927.sfx.exe")
$ErrorActionPreference = "Continue"
# windows-2025 runners sometimes come up without the Docker service running.
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/$Release/$Asset" -OutFile "$root\msys2-base.sfx.exe"
& "$root\msys2-base.sfx.exe" -y -o"$root\ctx" | Out-Null
Start-Sleep 5
Copy-Item "$root\pacman-test.ps1" "$root\ctx\"
(Get-Content "$root\scale.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\ctx\msys64\scale.sh" -NoNewline
@"
FROM $Base
COPY msys64 C:/msys64
COPY pacman-test.ps1 C:/pacman-test.ps1
"@ | Set-Content "$root\ctx\Dockerfile"
docker build -t pacman-test -f "$root\ctx\Dockerfile" "$root\ctx" | Out-Null
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)  base: $Base  msys2 base: $Release"
docker info --format 'docker {{.ServerVersion}} isolation={{.Isolation}} kernel={{.KernelVersion}}'
foreach ($iso in $Isolations) {
  foreach ($v in 'stock', 'dyn', 'all') {
    "################ isolation=$iso variant=$v"
    docker run --rm --isolation=$iso pacman-test powershell -ExecutionPolicy Bypass -File C:\pacman-test.ps1 -Variant $v 2>&1
  }
}
"done"
