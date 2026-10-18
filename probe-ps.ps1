# Runs inside the container via docker exec: the process tree, and for each bash its runtime base and ASLR policy.
$ErrorActionPreference = 'Continue'
Get-CimInstance Win32_Process | Sort-Object ProcessId | ForEach-Object { "{0,6} ppid {1,6} s{2} {3} | {4}" -f $_.ProcessId, $_.ParentProcessId, $_.SessionId, $_.Name, $_.CommandLine }
foreach ($p in Get-Process bash -ErrorAction SilentlyContinue) {
  "bash winpid $($p.Id) path $($p.Path)"
  try { $p.Modules | Where-Object { $_.ModuleName -match 'msys-2\.0|bash|ntdll|kernel32' } | ForEach-Object { "  {0} base 0x{1:X} size 0x{2:X} {3}" -f $_.ModuleName, $_.BaseAddress.ToInt64(), $_.ModuleMemorySize, $_.FileName } } catch { "  modules: $_" }
  try { $m = Get-ProcessMitigation -Id $p.Id; "  ASLR force=$($m.ASLR.ForceRelocateImages) bottomup=$($m.ASLR.BottomUp) heva=$($m.ASLR.HighEntropy) requireinfo=$($m.ASLR.RequireInfo)" } catch { "  mitigation: $_" }
}
if (Test-Path C:\samp\sampler3.exe) { "--- mappings per process (sampler3 procs)"; & C:\samp\sampler3.exe procs C:\ }
