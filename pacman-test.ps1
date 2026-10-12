# Runs inside the container (Windows PowerShell 5.1). Applies the variant's dynamicbase flags, then exercises pacman and forks.
# The flags are re-applied before every step because pacman -Syu replaces msys-2.0.dll and other DLLs with the repo's builds.
param([string]$Variant = 'stock')
$ErrorActionPreference = 'Continue'
$bin = 'C:\msys64\usr\bin'
$env:MSYSTEM = 'MSYS'; $env:CHERE_INVOKING = '1'
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); if (($c -band 0x40) -eq 0) { [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) } }
function Apply {
  switch ($Variant) { 'dyn' { SetFlag "$bin\msys-2.0.dll" } 'all' { Get-ChildItem "$bin\*.dll" | ForEach-Object { SetFlag $_.FullName } } }
  $dlls = Get-ChildItem "$bin\*.dll"
  "dynamicbase: $(@($dlls | Where-Object { Flag $_.FullName }).Count)/$($dlls.Count)  runtime flagged: $(Flag "$bin\msys-2.0.dll")"
}
$total = 0
function Run($label, $cmd) {
  Apply
  "--- $label"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  cmd /c "`"$bin\bash.exe`" -lc `"$cmd`" > C:\step.log 2>&1"
  $code = $LASTEXITCODE
  $log = Get-Content C:\step.log
  $errs = @($log | Where-Object { $_ -match 'dofork|child_copy|child_info_fork|fork: ' })
  $script:total += $errs.Count
  $log | Where-Object { $_ -notmatch 'dofork|fork: retry' } | Select-Object -Last 12
  if ($errs.Count) { "first fork error: $($errs[0])" }
  "exit $code  fork errors: $($errs.Count)  $([int]$sw.Elapsed.TotalSeconds)s"
}
Run 'first launch (runs /etc/post-install)' 'true'
Run 'pacman -Syu' 'pacman -Syu --noconfirm'
Run 'pacman -Su, second pass' 'pacman -Su --noconfirm'
Run 'pacman -S rhash tree make' 'pacman -S --noconfirm rhash tree make'
Run 'rhash and make run' 'rhash --sha256 /usr/bin/bash.exe && make --version | head -1'
Run 'pacman -Rns rhash tree make' 'pacman -Rns --noconfirm rhash tree make'
Run 'scale: 1000 subshells, 8x100 parallel, 200 timeout, 200 pipe' '/scale.sh 1000 8 100'
"==== variant=$Variant total fork errors: $total"
