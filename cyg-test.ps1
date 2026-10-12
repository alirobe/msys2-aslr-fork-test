# Runs inside the container (Windows PowerShell 5.1). Installs the chosen cygwin1.dll into the December 2022 Cygwin
# install, then runs fork-heavy things: the probe, gpg and make, and the fork scale test.
param([string]$Variant = '343')
$ErrorActionPreference = 'Continue'
$bin = 'C:\cygwin\bin'
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function ClearBit($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -band (-bnot 0x40))), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
$src = switch ($Variant) { '343' { 'C:\rt\cygwin1.dll.343' } '343-nodyn' { 'C:\rt\cygwin1.dll.343' } '3611' { 'C:\rt\cygwin1.dll.3611' } }
Copy-Item $src "$bin\cygwin1.dll" -Force
if ($Variant -eq '343-nodyn') { ClearBit "$bin\cygwin1.dll" }
"runtime: $Variant  dynamicbase: $(Flag "$bin\cygwin1.dll")  size: $((Get-Item "$bin\cygwin1.dll").Length)"
$total = 0
function Run($label, $cmd) {
  "--- $label"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  cmd /c "`"$bin\bash.exe`" --norc -c `"$cmd`" > C:\step.log 2>&1"
  $code = $LASTEXITCODE
  $log = Get-Content C:\step.log
  $errs = @($log | Where-Object { $_ -match 'dofork|child_copy|child_info_fork|fork: ' })
  $script:total += $errs.Count
  $log | Where-Object { $_ -notmatch 'dofork|fork: retry|child_copy' } | Select-Object -Last 8
  if ($errs.Count) { "first fork error: $($errs[0])" }
  "exit $code  fork errors: $($errs.Count)  $([int]$sw.Elapsed.TotalSeconds)s"
}
Run 'uname and bases' 'export PATH=/bin:$PATH; uname -srv; bash /probe-exe.sh'
Run 'gpg --version, make --version, find | xargs' 'export PATH=/bin:$PATH; gpg --version | head -1; make --version | head -1; find /bin -name *.exe | head -50 | xargs -n 10 echo | wc -l'
Run 'gpg key generation (forks and pipes)' 'export PATH=/bin:$PATH HOME=/tmp; mkdir -p /tmp; timeout 120 gpg --batch --pinentry-mode loopback --passphrase "" --quick-gen-key test@example.com default default never 2>&1 | tail -2; gpg --list-keys | grep -c pub'
Run 'scale: 1000 subshells, 8x100 parallel, 200 timeout, 200 pipe' '/scale.sh 1000 8 100'
"==== runtime=$Variant total fork errors: $total"
