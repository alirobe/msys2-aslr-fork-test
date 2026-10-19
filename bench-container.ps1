# One-off cost of the #387 re-exec and sweep in a Server 2019 container. Uses the two trees bench-host.ps1 set up
# (baseline and PR runtime, otherwise identical), each copied into its own image as one layer. Each fresh container
# times, from inside, three bash starts in a row and then a gawk start: with the PR runtime the first one is the
# process that finds its modules moved, re-execs and sweeps; the later ones find nothing moved. Run in the lab VM.
param([string]$Base = 'mcr.microsoft.com/windows/servercore:10.0.17763.9245', [string[]]$Isolations = @('hyperv', 'process'),
      [int]$Reps = 5, [string]$Root = 'C:\lab\bench')
$ErrorActionPreference = 'Continue'
$env:PATH += ';C:\Program Files\Docker'
$ProgressPreference = 'SilentlyContinue'
$bash = 'C:\msys64\usr\bin\bash.exe|--norc --noprofile -c true'
$run = "@echo off`r`nC:\bench\bench.exe once `"bash 1st|$bash`" `"bash 2nd|$bash`" `"bash 3rd|$bash`" `"gawk 1st|C:\msys64\usr\bin\gawk.exe|BEGIN{}`"`r`n"
foreach ($v in 'base', 'new') {
  $ctx = "$Root\ctx-$v"
  if (Test-Path $ctx) { Remove-Item $ctx -Recurse -Force }
  New-Item -ItemType Directory "$ctx\bench" | Out-Null
  Copy-Item "$Root\$v\msys64" "$ctx\msys64" -Recurse
  Copy-Item "$Root\bench.exe" "$ctx\bench\"
  [IO.File]::WriteAllText("$ctx\bench\run.cmd", $run)
  "FROM $Base`nCOPY msys64 C:/msys64`nCOPY bench C:/bench" | Set-Content "$ctx\Dockerfile"
  docker build -t "bench-$v" -f "$ctx\Dockerfile" $ctx | Select-Object -Last 1
}
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  base image: $Base"
foreach ($iso in $Isolations) {
  foreach ($i in 1..$Reps) {
    foreach ($v in 'base', 'new') {
      $out = docker run --rm --isolation=$iso "bench-$v" cmd /c C:\bench\run.cmd 2>&1 | ForEach-Object { "$_" }
      "$iso $v #${i}: $(($out | Where-Object { $_ -match ' ms' }) -join '; ')"
    }
  }
}
"done"
