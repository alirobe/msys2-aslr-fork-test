# Startup cost of the #387 check on a normal host (no container). Two identical MSYS2 base trees, one with the baseline
# runtime (the PR's parent commit) and one with the PR's runtime, built the same way. Each root process is timed from
# CreateProcess to exit by bench.exe, interleaved, after warm-ups. Run in the lab VM.
param([Parameter(Mandatory)][string]$BaseDll, [Parameter(Mandatory)][string]$NewDll, [int]$N = 2000,
      [string]$Sfx = 'C:\lab\fork-test\base2026.sfx.exe', [string]$Root = 'C:\lab\bench')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory $Root -Force | Out-Null
foreach ($v in 'base', 'new') {
  if (Test-Path "$Root\$v") { Remove-Item "$Root\$v" -Recurse -Force }
  & $Sfx -y -o"$Root\$v" | Out-Null
}
Start-Sleep 5
Copy-Item $BaseDll "$Root\base\msys64\usr\bin\msys-2.0.dll" -Force
Copy-Item $NewDll "$Root\new\msys64\usr\bin\msys-2.0.dll" -Force
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -nologo -optimize -out:"$Root\bench.exe" C:\lab\fork-test\bench.cs
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  CPUs: $((Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum)"
try { $mp = Get-MpComputerStatus; "Defender real-time protection: $($mp.RealTimeProtectionEnabled)  exclusions: $(@((Get-MpPreference).ExclusionPath) -join ', ')" } catch { "Defender status: $_" }
foreach ($v in 'base', 'new') { "$v runtime sha256 $((Get-FileHash "$Root\$v\msys64\usr\bin\msys-2.0.dll").Hash.ToLower().Substring(0, 12))" }
$b = "$Root\base\msys64\usr\bin"; $w = "$Root\new\msys64\usr\bin"
"--- bash --norc --noprofile -c true (exe and runtime: 2 modules outside the Windows directory)"
& "$Root\bench.exe" stats $N "base-bash|$b\bash.exe|--norc --noprofile -c true" "new-bash|$w\bash.exe|--norc --noprofile -c true"
"--- gawk BEGIN{} (exe, runtime and 6 linked msys DLLs)"
& "$Root\bench.exe" stats $N "base-gawk|$b\gawk.exe|BEGIN{}" "new-gawk|$w\gawk.exe|BEGIN{}"
"--- the same pair again, to show run-to-run spread"
& "$Root\bench.exe" stats $N "base-bash|$b\bash.exe|--norc --noprofile -c true" "new-bash|$w\bash.exe|--norc --noprofile -c true"
"done"
