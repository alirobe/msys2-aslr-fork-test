# Runs on a GitHub Actions Windows runner. Mandatory ASLR plus Bottom-up ASLR forced on EVERY executable of a Portable
# Git install (usr\bin and git.exe) through per-process mitigations (IFEO), the closest a runner gets to the system-wide
# setting with Bottom-up set to On. Two full copies of Portable Git: all (every usr\bin DLL flagged, no exe) and allexe
# (every DLL and exe). Each runs the probe, the 50-run tests, the fork scale test and a real git workflow, first with
# no mitigations as the control, then with both forced.
param([string]$GitTag = "v2.56.0.windows.2", [string]$GitAsset = "PortableGit-2.56.0.2-64-bit.7z.exe")
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/$GitTag/$GitAsset" -OutFile "$root\PortableGit.7z.exe"
& "$root\PortableGit.7z.exe" -o"$root\pg" -y | Out-Null
Start-Sleep 5
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
$variants = 'all', 'allexe'
foreach ($v in $variants) {
    $d = "$root\$v"
    Copy-Item "$root\pg" $d -Recurse
    New-Item -ItemType Directory "$d\tmp" -Force | Out-Null
    foreach ($f in 'test-deps.sh', 'scale.sh', 'probe-exe.sh', 'git-work.sh') { (Get-Content "$root\$f" -Raw) -replace "`r`n", "`n" | Set-Content "$d\$f" -NoNewline }
    Get-ChildItem "$d\usr\bin\*.dll" | ForEach-Object { SetFlag $_.FullName }
    if ($v -eq 'allexe') { Get-ChildItem "$d\usr\bin\*.exe" | ForEach-Object { SetFlag $_.FullName } }
}
$exes = @(Get-ChildItem "$root\pg\usr\bin\*.exe" | ForEach-Object Name) + 'git.exe'
function Run($v, $script, $label) {
    "--- $v`: $label"
    cmd /c "`"$root\$v\usr\bin\bash.exe`" --norc /$script > `"$root\run.log`" 2>&1"
    $code = $LASTEXITCODE
    $log = Get-Content "$root\run.log"
    $log | Where-Object { $_ -notmatch 'dofork|fork: retry|child_copy|child_info_fork' } | Select-Object -First 12
    "exit $code  fork errors: $(@($log | Where-Object { $_ -match 'dofork|child_info_fork|child_copy' }).Count)"
    $log | Where-Object { $_ -match 'child_copy|child_info_fork' } | Select-Object -First 1
}
function RunAll($label) {
    "########## $label"
    foreach ($v in $variants) {
        $d = "$root\$v"
        $dlls = Get-ChildItem "$d\usr\bin\*.dll"; $ex = Get-ChildItem "$d\usr\bin\*.exe"
        "===== $v  dll dynamicbase: $(@($dlls | Where-Object { Flag $_.FullName }).Count)/$($dlls.Count)  exe dynamicbase: $(@($ex | Where-Object { Flag $_.FullName }).Count)/$($ex.Count)"
        Run $v 'probe-exe.sh' 'parent and child addresses'
        Run $v 'test-deps.sh' '50 each: subshell, pipe, timeout, find | xargs'
        Run $v 'scale.sh 2000 8 250' 'scale: 2000 subshells, 8x250 parallel, 200 timeout, 200 pipe'
        Run $v 'git-work.sh' 'git: 50 commits with a hook, clone, rebase -i with editors, alias'
    }
}
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  system Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)  Bottom-up: $((Get-ProcessMitigation -System).ASLR.BottomUp)"
RunAll "A. no per-process mitigations"
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($e in $exes) { Set-ProcessMitigation -Name $e -Enable ForceRelocateImages, BottomUp }
"forced ForceRelocateImages + BottomUp on $($exes.Count) executables in $([int]$sw.Elapsed.TotalSeconds)s; bash.exe now: $((Get-ProcessMitigation -Name bash.exe).ASLR | Out-String)"
RunAll "C. Mandatory + Bottom-up ASLR forced on every executable"
"done"
