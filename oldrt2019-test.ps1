# Runs inside the container (Windows PowerShell 5.1). Puts the chosen runtime into the December 2022 MSYS2 base (or, for
# 'inplace', leaves the one pacman installed during the image build), then first launch, pacman steps and the fork scale
# test. Fork errors are counted from the runtime's own messages.
param([string]$Variant = '336')
$ErrorActionPreference = 'Continue'
$bin = 'C:\msys64\usr\bin'
$env:MSYSTEM = 'MSYS'; $env:CHERE_INVOKING = '1'
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function ClearBit($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -band (-bnot 0x40))), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
$src = switch ($Variant) { '336' { 'C:\rt\msys-2.0.dll.336' } '342' { 'C:\rt\msys-2.0.dll.342' } '342-nodyn' { 'C:\rt\msys-2.0.dll.342' } '343' { 'C:\rt\msys-2.0.dll.343' } 'now' { 'C:\rt\msys-2.0.dll.now' } 'inplace' { $null } }
if ($src) { Copy-Item $src "$bin\msys-2.0.dll" -Force }
if ($Variant -eq '342-nodyn') { ClearBit "$bin\msys-2.0.dll" }
"runtime: $Variant  dynamicbase: $(Flag "$bin\msys-2.0.dll")  size: $((Get-Item "$bin\msys-2.0.dll").Length)  sha256: $((Get-FileHash "$bin\msys-2.0.dll").Hash.ToLower().Substring(0,12))"
$total = 0
function Run($label, $cmd) {
  "--- $label"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  cmd /c "`"$bin\bash.exe`" -lc `"$cmd`" > C:\step.log 2>&1"
  $code = $LASTEXITCODE
  $log = Get-Content C:\step.log
  $errs = @($log | Where-Object { $_ -match 'dofork|child_copy|child_info_fork|fork: ' })
  $script:total += $errs.Count
  $log | Where-Object { $_ -notmatch 'dofork|fork: retry|child_copy' } | Select-Object -Last 6
  if ($errs.Count) { "first fork error: $($errs[0])" }
  "exit $code  fork errors: $($errs.Count)  $([int]$sw.Elapsed.TotalSeconds)s"
}
Run 'first launch (runs /etc/profile and post-install)' 'true'
Run 'uname and bases' 'uname -srv; bash /probe-exe.sh'
Run 'pacman-key --init and --populate' 'pacman-key --init && pacman-key --populate msys2'
Run 'pacman -Qk' 'pacman -Qk > /dev/null; pacman -Qk 2>&1 | tail -2'
Run 'scale: 1000 subshells, 8x100 parallel, 200 timeout, 200 pipe' '/scale.sh 1000 8 100'
"==== runtime=$Variant total fork errors: $total"
Get-Process gpg-agent, dirmngr, keyboxd, scdaemon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
