# Runs on a GitHub Actions Windows runner. Upstream Cygwin as it was on 20 December 2022 (cygwin 3.4.3-1, the first
# releases with dynamicbase on the DLL), installed from the Cygwin Time Machine snapshot, put in a Windows container and
# fork-tested three ways: 3.4.3 as shipped (dynamicbase), 3.4.3 with the bit cleared (Corinna's suggested workaround),
# and today's 3.6.11 DLL dropped into the same install.
param([string]$Base = "mcr.microsoft.com/windows/servercore:ltsc2022", [string[]]$Isolations = @('process', 'hyperv'))
$ErrorActionPreference = "Continue"
# windows-2025 runners sometimes come up without the Docker service running.
Start-Service docker -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 24 -and -not (docker info 2>$null); $i++) { Start-Sleep 5 }
$root = $PSScriptRoot
$ctm = "http://ctm.crouchingtigerhiddenfruitbat.org/pub/cygwin"
"stage: download setup.exe from the Time Machine"
Invoke-WebRequest -TimeoutSec 300 -UserAgent "Mozilla/5.0" -Uri "$ctm/setup/snapshots/setup-x86_64-2.924.exe" -OutFile "$root\setup.exe"
New-Item -ItemType Directory "$root\ctx" | Out-Null
"stage: run setup.exe"
$p = Start-Process -FilePath "$root\setup.exe" -ArgumentList @('-q','-B','-n','-N','-d','-O','-W','-X','-s',"$ctm/circa/64bit/2022/12/20/144651",'-R',"$root\ctx\cygwin",'-l',"$root\cygpkgs",'-P','bash,coreutils,sed,findutils,gnupg2,make,grep') -RedirectStandardOutput "$root\setup.log" -PassThru
if (-not $p.WaitForExit(900000)) { "setup.exe still running after 15 min; killing it"; $p.Kill() }
Get-Content "$root\setup.log" | Select-Object -Last 8
"stage: setup.exe finished, exit $($p.ExitCode)"
"stage: download cygwin 3.6.11"
# Invoke-WebRequest to mirrors.kernel.org never returns on windows-2022 runners; curl with a cap and fallbacks.
$rel = "x86_64/release/cygwin/cygwin-3.6.11-1-x86_64.tar.xz"
foreach ($m in "https://mirrors.kernel.org/sourceware/cygwin", "https://cygwin.mirror.constant.com", "https://mirror.clarkson.edu/cygwin", "https://ftp.fau.de/cygwin", "https://mirrors.sonic.net/cygwin") {
  "  trying $m"
  curl.exe -sSL --connect-timeout 20 --max-time 240 -o "$root\cygwin-3.6.11.tar.xz" "$m/$rel"
  if ($LASTEXITCODE -eq 0 -and (Get-Item "$root\cygwin-3.6.11.tar.xz" -ErrorAction SilentlyContinue).Length -gt 1000000) { break }
}
"stage: extract cygwin 3.6.11 ($((Get-Item "$root\cygwin-3.6.11.tar.xz").Length) bytes)"
New-Item -ItemType Directory "$root\now", "$root\ctx\rt" | Out-Null
# tar -xJf never finishes on windows-2022 runners; 7z is on every runner image.
& 7z.exe x "$root\cygwin-3.6.11.tar.xz" -o"$root\now" -y | Out-Null
& 7z.exe e "$root\now\cygwin-3.6.11.tar" -o"$root\now" -r cygwin1.dll -y | Out-Null
Copy-Item "$root\ctx\cygwin\bin\cygwin1.dll" "$root\ctx\rt\cygwin1.dll.343"
Copy-Item "$root\now\cygwin1.dll" "$root\ctx\rt\cygwin1.dll.3611"
Copy-Item "$root\cyg-test.ps1" "$root\ctx\"
(Get-Content "$root\scale.sh" -Raw) -replace "`r`n", "`n" -replace '/usr/bin:', '/bin:/usr/bin:' | Set-Content "$root\ctx\cygwin\scale.sh" -NoNewline
(Get-Content "$root\probe-exe.sh" -Raw) -replace "`r`n", "`n" -replace 'msys-2.0.dll', 'cygwin1.dll' -replace 'msys-iconv-2.dll', 'cygiconv-2.dll' | Set-Content "$root\ctx\cygwin\probe-exe.sh" -NoNewline
"installed: $(Get-ChildItem "$root\ctx\cygwin\bin\*.exe" | Measure-Object | ForEach-Object Count) exes, $(Get-ChildItem "$root\ctx\cygwin\bin\*.dll" | Measure-Object | ForEach-Object Count) dlls"
& "$root\pe-flags.ps1" -Paths (Get-ChildItem "$root\ctx\rt\*" | ForEach-Object FullName)
@"
FROM $Base
COPY cygwin C:/cygwin
COPY rt C:/rt
COPY cyg-test.ps1 C:/cyg-test.ps1
"@ | Set-Content "$root\ctx\Dockerfile"
"stage: docker build"
docker build -t cyg-test -f "$root\ctx\Dockerfile" "$root\ctx" | Out-Null
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)  base: $Base"
docker info --format 'docker {{.ServerVersion}} isolation={{.Isolation}} kernel={{.KernelVersion}}'
"stage: run containers"
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
}foreach ($iso in $Isolations) {
  foreach ($v in '343', '343-nodyn', '3611') {
    "################ isolation=$iso runtime=$v"
    RunContainer 'cyg-test' $iso 'C:\cyg-test.ps1' $v 15
  }
}
"done"
