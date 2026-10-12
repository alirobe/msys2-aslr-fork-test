# Runs inside the GitHub Actions Windows runner. Builds two images (stock DLL, dynamicbase DLL) and runs fork tests in both isolation modes available.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2022", [string]$GitTag = "v2.56.0.windows.2", [string]$GitAsset = "PortableGit-2.56.0.2-64-bit.7z.exe")
$ErrorActionPreference = "Continue"
# windows-2025 runners sometimes come up without the Docker service running.
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/$GitTag/$GitAsset" -OutFile "$root\PortableGit.7z.exe"
& "$root\PortableGit.7z.exe" -o"$root\pg" -y | Out-Null
Start-Sleep 5
Copy-Item "$root\pg\usr\bin\msys-2.0.dll" "$root\pg\usr\bin\msys-2.0.dll.stock"
& "$root\pe-flags.ps1" -Paths "$root\pg\usr\bin\msys-2.0.dll" -SetDynamicBaseCopyTo "$root\pg\usr\bin\msys-2.0.dll.dyn"
Copy-Item "$root\test.sh", "$root\probe.sh" "$root\pg\"
(Get-Content "$root\pg\test.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\pg\test.sh" -NoNewline
(Get-Content "$root\pg\probe.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\pg\probe.sh" -NoNewline
@"
FROM $Base
COPY pg C:/pg
"@ | Set-Content "$root\Dockerfile"
docker build -t fork-test:stock -f "$root\Dockerfile" $root | Out-Null
@"
FROM fork-test:stock
COPY pg/usr/bin/msys-2.0.dll.dyn C:/pg/usr/bin/msys-2.0.dll
"@ | Set-Content "$root\Dockerfile.dyn"
docker build -t fork-test:dyn -f "$root\Dockerfile.dyn" $root | Out-Null
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)"
docker info --format 'docker {{.ServerVersion}} isolation={{.Isolation}} kernel={{.KernelVersion}}'
foreach ($iso in 'process', 'hyperv') {
  foreach ($v in 'stock', 'dyn') {
    "===== isolation=$iso variant=$v ====="
    "--- A. bash direct ---"
    docker run --rm --isolation=$iso fork-test:$v C:\pg\usr\bin\bash.exe --norc /c/pg/test.sh 2>&1
    "--- B. via cmd, then a second launch in the same container ---"
    docker run --rm --isolation=$iso fork-test:$v cmd /c "C:\pg\usr\bin\bash.exe --norc /c/pg/test.sh & C:\pg\usr\bin\bash.exe --norc /c/pg/probe.sh second-launch & echo errorlevel=%errorlevel%" 2>&1
    "--- C. DLL re-copied into the writable layer first ---"
    docker run --rm --isolation=$iso fork-test:$v cmd /c "copy /y C:\pg\usr\bin\msys-2.0.dll.$v C:\pg\usr\bin\msys-2.0.dll >nul & C:\pg\usr\bin\bash.exe --norc /c/pg/test.sh & echo errorlevel=%errorlevel%" 2>&1
  }
}
"done"
