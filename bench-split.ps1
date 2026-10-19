# Follow-up to bench-host.ps1 and bench-container.ps1: gawk on the host with a program the runtime cannot brace-expand,
# and the container first start split into re-exec and sweep by a third image whose runtime re-execs without sweeping.
param([Parameter(Mandatory)][string]$NoSweepDll, [string]$Label = 'nosweep', [switch]$SkipHost, [string]$Base = 'mcr.microsoft.com/windows/servercore:10.0.17763.9245',
      [string[]]$Isolations = @('hyperv', 'process'), [int]$Reps = 5, [int]$N = 2000, [string]$Root = 'C:\lab\bench')
$ErrorActionPreference = 'Continue'
$env:PATH += ';C:\Program Files\Docker'
$ProgressPreference = 'SilentlyContinue'
$b = "$Root\base\msys64\usr\bin"; $w = "$Root\new\msys64\usr\bin"
if (-not $SkipHost) {
"--- host: gawk -f /dev/null (exe, runtime and 6 linked msys DLLs)"
& "$Root\bench.exe" stats $N "base-gawk|$b\gawk.exe|-f /dev/null" "new-gawk|$w\gawk.exe|-f /dev/null"
"--- usr/bin: $(@(Get-ChildItem "$w\*.dll").Count) DLLs, $(@(Get-ChildItem "$w\*.exe").Count) exes, $([int]((Get-ChildItem "$w\*.dll", "$w\*.exe" | Measure-Object Length -Sum).Sum / 1MB)) MB"
}
$ctx = "$Root\ctx-$Label"
if (Test-Path $ctx) { Remove-Item $ctx -Recurse -Force }
Copy-Item "$Root\ctx-new" $ctx -Recurse
Copy-Item $NoSweepDll "$ctx\msys64\usr\bin\msys-2.0.dll" -Force
docker build -t "bench-$Label" -f "$ctx\Dockerfile" $ctx | Select-Object -Last 1
foreach ($iso in $Isolations) {
  foreach ($i in 1..$Reps) {
    foreach ($v in 'base', $Label, 'new') {
      $out = docker run --rm --isolation=$iso "bench-$v" cmd /c C:\bench\run.cmd 2>&1 | ForEach-Object { "$_" }
      "$iso $v #${i}: $(($out | Where-Object { $_ -match ' ms' }) -join '; ')"
    }
  }
}
"done"
