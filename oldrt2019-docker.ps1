# Runs on a GitHub Actions Windows runner. Re-runs dscho's reproduction of the December 2022 Docker fork failure
# (msys2-runtime#381, 16 October 2026) with this repo's harness: the December 2022 MSYS2 base in a Server 2019 container
# pinned to its December 2022 patch level (10.0.17763.3770) under Hyper-V isolation, with the runtime swapped five ways:
#   342        the genuine 16 December 2022 build from the msys2-archive (msys2-runtime-3.4 3.4.2-1, dynamicbase on)
#   342-nodyn  the same with the bit cleared (what MSYS2 shipped the next day)
#   343        msys2-runtime 3.4.3-1 rebuilt from that day's PKGBUILD
#   336        the base's own 3.3.6, as the control
#   now        today's msys2-runtime 3.6.11-3 as published (dynamicbase on)
# Each runtime is tested two ways: copied in at container start, and upgraded in place by pacman inside `docker build`,
# the way the 2022 image was made.
param([string]$Base = "mcr.microsoft.com/windows/servercore:10.0.17763.3770", [string[]]$Isolations = @('hyperv'),
      [string]$RebuiltDllUrl = "https://github.com/alirobe/msys2-aslr-fork-test/releases/download/rebuilt-3.4.3-dec2022/msys-2.0.dll",
      [string]$GenuinePkgUrl = "https://github.com/msys2/msys2-archive/releases/download/2022-12-16-msys-x86_64/msys2-runtime-3.4-3.4.2-1-x86_64.pkg.tar.zst",
      [string]$TodayPkgUrl = "https://repo.msys2.org/msys/x86_64/msys2-runtime-3.6.11-3-x86_64.pkg.tar.zst",
      [string[]]$Variants = @('342', '342-nodyn', '343', '336', 'now'), [int]$Minutes = 15, [switch]$SkipCopiedIn, [switch]$MirrorOnly,
      [string]$P386DllUrl = "https://github.com/alirobe/msys2-aslr-fork-test/releases/download/patched-3.6.11-attr-open/msys-2.0.dll",
      [string]$P387DllUrl = "https://github.com/alirobe/msys2-aslr-fork-test/releases/download/reexec2-3.6.11/msys-2.0.dll")
$ErrorActionPreference = "Continue"
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
"stage: downloads"
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2022-12-16/msys2-base-x86_64-20221216.sfx.exe" -OutFile "$root\base2022.sfx.exe"
& "$root\base2022.sfx.exe" -y -o"$root\ctx" | Out-Null
Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-20260927.sfx.exe" -OutFile "$root\base2026.sfx.exe"
& "$root\base2026.sfx.exe" -y -o"$root\now" | Out-Null
Start-Sleep 5
New-Item -ItemType Directory "$root\ctx\rt" | Out-Null
Invoke-WebRequest -Uri $RebuiltDllUrl -OutFile "$root\ctx\rt\msys-2.0.dll.343"
Invoke-WebRequest -Uri $GenuinePkgUrl -OutFile "$root\ctx\rt\genuine.pkg.tar.zst"
Invoke-WebRequest -Uri $TodayPkgUrl -OutFile "$root\ctx\rt\today.pkg.tar.zst"
# The runner's tar has no zstd; the 2026 base's does.
$bash26 = "$root\now\msys64\usr\bin\bash.exe"; $cyg = "$root\now\msys64\usr\bin\cygpath.exe"
$rtu = & $cyg -u "$root\ctx\rt"
& $bash26 -lc "cd '$rtu' && mkdir -p g t && tar -xf genuine.pkg.tar.zst -C g usr/bin/msys-2.0.dll && cp g/usr/bin/msys-2.0.dll msys-2.0.dll.342 && tar -xf today.pkg.tar.zst -C t usr/bin/msys-2.0.dll && cp t/usr/bin/msys-2.0.dll msys-2.0.dll.now && rm -rf g t"
# The archived package is named msys2-runtime-3.4 and conflicts with the installed msys2-runtime; repack it under the
# installed name, as dscho's reproducer does, so pacman -U treats it as an upgrade.
& $bash26 -lc "cd '$rtu' && rm -rf rp && mkdir rp && tar -xf genuine.pkg.tar.zst -C rp && sed -i -e 's/^pkgname = msys2-runtime-3.4$/pkgname = msys2-runtime/' -e 's/^pkgbase = msys2-runtime-3.4$/pkgbase = msys2-runtime/' -e '/^conflict = msys2-runtime$/d' -e '/^provides = msys2-runtime=/d' rp/.PKGINFO && grep -E '^(pkgname|pkgbase|conflict|provides)' rp/.PKGINFO && cd rp && tar --zstd -cf ../genuine.pkg.tar.zst .BUILDINFO .MTREE .PKGINFO usr && cd .. && rm -rf rp && ls -la genuine.pkg.tar.zst"
Copy-Item "$root\ctx\msys64\usr\bin\msys-2.0.dll" "$root\ctx\rt\msys-2.0.dll.336"
# The two fixed runtimes (#386 attribute-only open, #387 re-exec) as packages: today's package with the DLL swapped.
foreach ($pp in @(@('p386', $P386DllUrl), @('p387', $P387DllUrl))) {
  Invoke-WebRequest -Uri $pp[1] -OutFile "$root\ctx\rt\msys-2.0.dll.$($pp[0])"
  & $bash26 -lc "cd '$rtu' && rm -rf pk && mkdir pk && tar -xf today.pkg.tar.zst -C pk && cp msys-2.0.dll.$($pp[0]) pk/usr/bin/msys-2.0.dll && cd pk && tar --zstd -cf ../$($pp[0]).pkg.tar.zst .BUILDINFO .MTREE .PKGINFO usr && cd .. && rm -rf pk && ls -la $($pp[0]).pkg.tar.zst"
}
Copy-Item "$root\oldrt2019-test.ps1" "$root\ctx\"
(Get-Content "$root\scale.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\ctx\msys64\scale.sh" -NoNewline
(Get-Content "$root\probe-exe.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$root\ctx\msys64\probe-exe.sh" -NoNewline
# pacman inside the 2022 base must accept unsigned local packages for the in-place upgrade.
(Get-Content "$root\ctx\msys64\etc\pacman.conf" -Raw) -replace '(?m)^\s*SigLevel\s*=.*$', 'SigLevel = Never' | Set-Content "$root\ctx\msys64\etc\pacman-ci.conf" -NoNewline
& "$root\pe-flags.ps1" -Paths (Get-ChildItem "$root\ctx\rt\msys-2.0.dll.*" | ForEach-Object FullName)
Get-FileHash "$root\ctx\rt\msys-2.0.dll.342" -Algorithm SHA256 | ForEach-Object { "genuine 2022 DLL sha256 $($_.Hash.ToLower())  (dscho's: eda9f89e032b2d1486c2bb3a66b01c9bae30372a7ff7c3bf16b364ea93b17ef4)" }
"stage: docker build (base image)"
@"
FROM $Base
COPY msys64 C:/msys64
COPY rt C:/rt
COPY oldrt2019-test.ps1 C:/oldrt2019-test.ps1
"@ | Set-Content "$root\ctx\Dockerfile"
docker build -t oldrt-base -f "$root\ctx\Dockerfile" "$root\ctx" | Out-Null
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)  base: $Base"
docker info --format 'docker {{.ServerVersion}} isolation={{.Isolation}} kernel={{.KernelVersion}}'
# Detached run with a cap; docker logs has the script's output either way.
function RunContainer($image, $iso, $variant, $minutes) {
  $id = "$(docker run -d --isolation=$iso $image powershell -ExecutionPolicy Bypass -File C:\oldrt2019-test.ps1 -Variant $variant 2>&1 | Select-Object -Last 1)".Trim()
  if ($id -notmatch '^[0-9a-f]{12,}$') { "docker run failed: $id"; return }
  $deadline = (Get-Date).AddMinutes($minutes)
  do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
  docker logs $id 2>&1 | ForEach-Object { "$_" }
  if ($running -eq 'true') { "container still running after $minutes min; killing it" }
  $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru
  if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
}
foreach ($iso in $Isolations) {
  if (-not $SkipCopiedIn -and -not $MirrorOnly) { foreach ($v in $Variants) {
    "################ isolation=$iso runtime=$v mode=copied-in"
    RunContainer 'oldrt-base' $iso $v $Minutes
  } }
  # In-place upgrade inside docker build, as the 2022 image was made: pacman -U of the runtime package in a RUN layer.
  foreach ($v in $Variants) {
    $pkg = switch ($v) { '342' { 'genuine.pkg.tar.zst' } 'now' { 'today.pkg.tar.zst' } 'p386' { 'p386.pkg.tar.zst' } 'p387' { 'p387.pkg.tar.zst' } default { $null } }
    if (-not $pkg -or $MirrorOnly) { continue }
    "################ isolation=$iso runtime=$v mode=upgraded-in-build"
    # Each MSYS command in its own shell, as dscho's reproducer does: a shell that has just replaced its own runtime
    # cannot spawn programs on the new one.
    @"
`$ErrorActionPreference = 'Stop'
`$env:MSYSTEM = 'MSYS'
`$env:PATH = 'C:\msys64\usr\bin;C:\Windows\System32;C:\Windows'
function msys([string]`$cmd) { C:\msys64\usr\bin\bash.exe -lc `$cmd; if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE } }
msys 'uname -srv'
msys 'pacman --config /etc/pacman-ci.conf --noconfirm -Udd /c/rt/$pkg'
"after upgrade: " + (Get-FileHash C:\msys64\usr\bin\msys-2.0.dll).Hash.ToLower().Substring(0, 12)
Get-Process gpg-agent, dirmngr, keyboxd, scdaemon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
exit 0
"@ | Set-Content "$root\ctx\build-step.ps1"
    @"
FROM oldrt-base
COPY build-step.ps1 C:/build-step.ps1
RUN ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoProfile", "-File", "C:\\build-step.ps1"]
"@ | Set-Content "$root\ctx\Dockerfile.inplace"
    $bout = @(docker build --no-cache --isolation=$iso -t "oldrt-inplace-$v" -f "$root\ctx\Dockerfile.inplace" "$root\ctx" 2>&1 | ForEach-Object { "$_" })
    if (-not ($bout -match 'Successfully built')) { "docker build failed; last lines:"; $bout | Select-Object -Last 30 | ForEach-Object { "  $_" }; continue }
    $bout | Where-Object { $_ -match 'MSYS_NT|dofork|child_copy|child_info_fork|fork: |error|upgrading|after upgrade|Successfully built' }
    RunContainer "oldrt-inplace-$v" $iso "inplace" $Minutes
  }
  # Mirror of dscho's reproducer: tree extracted by tar inside the build step, runtime upgraded in a fresh shell,
  # another fresh shell afterwards, then docker run with bash -lc as the container's entry process.
  if (-not (Test-Path "$root\ctx\sdk-base.tar")) { & "$env:SystemRoot\System32\tar.exe" -cf "$root\ctx\sdk-base.tar" -C "$root\ctx" msys64 }
  foreach ($v in $Variants) {
    $pkg = switch ($v) { '342' { 'genuine.pkg.tar.zst' } 'now' { 'today.pkg.tar.zst' } 'p386' { 'p386.pkg.tar.zst' } 'p387' { 'p387.pkg.tar.zst' } default { $null } }
    if (-not $pkg) { continue }
    "################ isolation=$iso runtime=$v mode=mirror (tar-extracted tree, bash as entry process)"
    @"
`$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path C:\msys64 -Force > `$null
C:\Windows\System32\tar.exe -xf C:\packages\sdk-base.tar -C C:\
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
`$env:MSYSTEM = 'MSYS'
`$env:PATH = 'C:\msys64\usr\bin;C:\Windows\System32;C:\Windows'
function msys([string]`$cmd) { C:\msys64\usr\bin\bash.exe -lc `$cmd; if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE } }
msys 'uname -a'
msys 'pacman --config /etc/pacman-ci.conf --noconfirm -Udd /c/packages/$pkg'
"after upgrade: " + (Get-FileHash C:\msys64\usr\bin\msys-2.0.dll).Hash.ToLower().Substring(0, 12)
msys 'uname -a && pacman -Qk > /dev/null; echo "Qk exit `$?"'
Get-Process gpg-agent, dirmngr, keyboxd, scdaemon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'C:\`$Recycle.Bin' -Recurse -Force -ErrorAction SilentlyContinue
exit 0
"@ | Set-Content "$root\ctx\build-step-mirror.ps1"
    @"
FROM $Base
COPY sdk-base.tar rt/$pkg build-step-mirror.ps1 entry.sh C:/packages/
COPY msys64/scale.sh C:/packages/scale.sh
COPY oldrt2019-test.ps1 C:/oldrt2019-test.ps1
RUN ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoProfile", "-File", "C:\\packages\\build-step-mirror.ps1"]
"@ | Set-Content "$root\ctx\Dockerfile.mirror"
    $bout = @(docker build --no-cache --isolation=$iso -t "oldrt-mirror-$v" -f "$root\ctx\Dockerfile.mirror" "$root\ctx" 2>&1 | ForEach-Object { "$_" })
    if (-not ($bout -match 'Successfully built')) { "docker build failed; last lines:"; $bout | Select-Object -Last 30 | ForEach-Object { "  $_" }; continue }
    $bout | Where-Object { $_ -match 'MSYS_NT|dofork|child_copy|child_info_fork|fork: |error|upgrading|after upgrade|Qk exit|Successfully built' }
    # The entry command lives in a file inside the image: Windows PowerShell 5.1 splits a native argument that
    # contains double quotes, so an inline command reaches bash truncated.
    "uname -a && for i in 1 2 3 4 5; do x=`$(echo `$i) && echo `"fork `$i ok`"; done; cp /c/packages/scale.sh /scale.sh && /scale.sh 300 4 50; echo `"scale exit `$?`"; pacman -Qk > /dev/null; echo `"Qk exit `$?`"`n" -replace "`r`n", "`n" | Set-Content "$root\ctx\entry.sh" -NoNewline
    $cmd = 'bash /c/packages/entry.sh'
    $id = "$(docker run -d --isolation=$iso --user ContainerAdministrator -e MSYSTEM=MSYS -e 'PATH=C:\msys64\usr\bin;C:\Windows\System32;C:\Windows' "oldrt-mirror-$v" C:\msys64\usr\bin\bash.exe -lc $cmd 2>&1 | Select-Object -Last 1)".Trim()
    if ($id -notmatch '^[0-9a-f]{12,}$') { "docker run failed: $id"; continue }
    $deadline = (Get-Date).AddMinutes($Minutes)
    do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
    $out = @(docker logs $id 2>&1 | ForEach-Object { "$_" })
    $out | Where-Object { $_ -notmatch 'fork: retry' } | Select-Object -First 40
    "fork errors: $(@($out | Where-Object { $_ -match 'dofork|child_copy|child_info_fork' }).Count)  exit code: $(docker inspect -f '{{.State.ExitCode}}' $id)"
    $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru; if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
    # Isolate the trigger: the same tar-extracted image entered through powershell (our usual path) ...
    "################ isolation=$iso runtime=$v mode=mirror-tree, powershell entry"
    RunContainer "oldrt-mirror-$v" $iso "inplace" $Minutes
    # ... and the COPY-layer image (built in the upgraded-in-build leg) entered with bash directly.
    if (-not $MirrorOnly -and (docker image inspect "oldrt-inplace-$v" 2>$null)) {
      "################ isolation=$iso runtime=$v mode=copy-tree, bash entry"
      $id = "$(docker run -d --isolation=$iso --user ContainerAdministrator -e MSYSTEM=MSYS -e 'PATH=C:\msys64\usr\bin;C:\Windows\System32;C:\Windows' "oldrt-inplace-$v" C:\msys64\usr\bin\bash.exe -lc $cmd 2>&1 | Select-Object -Last 1)".Trim()
      if ($id -match '^[0-9a-f]{12,}$') {
        $deadline = (Get-Date).AddMinutes($Minutes)
        do { Start-Sleep 5; $running = "$(docker inspect -f '{{.State.Running}}' $id 2>$null)".Trim() } while ($running -eq 'true' -and (Get-Date) -lt $deadline)
        $out = @(docker logs $id 2>&1 | ForEach-Object { "$_" })
        $out | Where-Object { $_ -notmatch 'fork: retry' } | Select-Object -First 12
        "fork errors: $(@($out | Where-Object { $_ -match 'dofork|child_copy|child_info_fork' }).Count)  exit code: $(docker inspect -f '{{.State.ExitCode}}' $id)"
        $p = Start-Process docker -ArgumentList "rm -f $id" -NoNewWindow -PassThru; if (-not $p.WaitForExit(120000)) { "docker rm did not return in 2 min; moving on" }
      } else { "docker run failed: $id" }
    }
  }
}
"done"
