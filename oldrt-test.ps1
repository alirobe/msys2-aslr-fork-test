# Runs inside the container (Windows PowerShell 5.1). Installs the chosen runtime into the 2022-12-16 MSYS2 base, then
# exercises pacman without upgrading (the 2022 report was pacman) and runs the fork scale test.
param([string]$Variant = '336')
$ErrorActionPreference = 'Continue'
$bin = 'C:\msys64\usr\bin'
$env:MSYSTEM = 'MSYS'; $env:CHERE_INVOKING = '1'
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function SetBit($p, $on) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); $n = if ($on) { $c -bor 0x40 } else { $c -band (-bnot 0x40) }; [Array]::Copy([BitConverter]::GetBytes([uint16]$n), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
$src = switch ($Variant) { '336' { 'C:\rt\msys-2.0.dll.336' } '343' { 'C:\rt\msys-2.0.dll.343' } '343-nodyn' { 'C:\rt\msys-2.0.dll.343' } 'now' { 'C:\rt\msys-2.0.dll.now' } }
Copy-Item $src "$bin\msys-2.0.dll" -Force
if ($Variant -eq '343-nodyn') { SetBit "$bin\msys-2.0.dll" $false }
if ($Variant -eq 'now') { SetBit "$bin\msys-2.0.dll" $true }
"runtime: $Variant  dynamicbase: $(Flag "$bin\msys-2.0.dll")  size: $((Get-Item "$bin\msys-2.0.dll").Length)"
$total = 0
function Run($label, $cmd) {
  "--- $label"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  cmd /c "`"$bin\bash.exe`" -lc `"$cmd`" > C:\step.log 2>&1"
  $code = $LASTEXITCODE
  $log = Get-Content C:\step.log
  $errs = @($log | Where-Object { $_ -match 'dofork|child_copy|child_info_fork|fork: ' })
  $script:total += $errs.Count
  $log | Where-Object { $_ -notmatch 'dofork|fork: retry|child_copy' } | Select-Object -Last 8
  if ($errs.Count) { "first fork error: $($errs[0])" }
  "exit $code  fork errors: $($errs.Count)  $([int]$sw.Elapsed.TotalSeconds)s"
}
Run 'uname and bases' 'uname -srv; bash /probe-exe.sh'
Run 'first launch (runs /etc/post-install)' 'true'
Run 'pacman-key --init' 'pacman-key --init'
Run 'pacman-key --populate msys2' 'pacman-key --populate msys2'
Run 'pacman -Sy' 'pacman -Sy --noconfirm'
Run 'pacman -Qk' 'pacman -Qk > /dev/null; pacman -Qk 2>&1 | tail -3'
Run 'pacman -Qi bash, -Ss make' 'pacman -Qi bash | head -3; pacman -Ss ^make$ | head -2'
Run 'makepkg --version, gpg --version' 'makepkg --version | head -1; gpg --version | head -1'
Run 'scale: 1000 subshells, 8x100 parallel, 200 timeout, 200 pipe' '/scale.sh 1000 8 100'
"==== runtime=$Variant total fork errors: $total"
# gpg-agent and friends outlive the script and keep the container's stdout open under Hyper-V isolation.
Get-Process gpg-agent, dirmngr, keyboxd, scdaemon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
