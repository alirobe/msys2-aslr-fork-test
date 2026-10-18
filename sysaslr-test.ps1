# Runs on the lab VM host. For each Portable Git copy: parent/child addresses, the 50-run fork tests, and the git
# workflow with its editor probes (the exit-127 question). Reports the system ASLR policy in force.
param([string]$Lab = 'C:\lab\sysaslr', [string[]]$Variants = @('stock', 'allexe'))
$ErrorActionPreference = 'Continue'
$m = (Get-ProcessMitigation -System).ASLR
"########## system ASLR: ForceRelocateImages=$($m.ForceRelocateImages) BottomUp=$($m.BottomUp) HighEntropy=$($m.HighEntropy)  uptime min $([int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes)"
function Run($v, $script, $label) {
  "--- $v`: $label"
  $log = "$Lab\run-$v.log"
  cmd /c "`"$Lab\$v\usr\bin\bash.exe`" --norc /$script > `"$log`" 2>&1"
  $code = $LASTEXITCODE
  $out = Get-Content $log
  $out | Where-Object { $_ -notmatch 'dofork|fork: retry|child_copy|child_info_fork' } | Select-Object -First 60
  "exit $code  fork errors: $(@($out | Where-Object { $_ -match 'dofork|child_info_fork|child_copy' }).Count)"
  $out | Where-Object { $_ -match 'child_copy|child_info_fork' } | Select-Object -First 1
}
foreach ($v in $Variants) {
  "===== $v"
  Run $v 'probe-exe.sh' 'parent and child addresses'
  Run $v 'test-deps.sh' '50 each: subshell, pipe, timeout, find | xargs'
  Run $v 'git-work.sh' 'git workflow with editor probes'
}
