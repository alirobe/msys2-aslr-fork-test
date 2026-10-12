# Runs on a GitHub Actions Windows runner. Per-process mitigations (IFEO) apply to new processes without a reboot, unlike
# the system-wide setting, so this is how a runner can test Mandatory ASLR. Four usr\bin variants of Portable Git:
# stock, deps (every DLL but the runtime flagged), all (every DLL), allexe (every DLL and exe). Two passes: Mandatory ASLR
# forced on the test exes, then Mandatory plus Bottom-up ASLR. Bottom-up matters because a force-relocated exe is only
# randomised when bottom-up randomisation is on; otherwise it lands at the same low address in every process.
param([string]$GitTag = "v2.56.0.windows.2", [string]$GitAsset = "PortableGit-2.56.0.2-64-bit.7z.exe")
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/$GitTag/$GitAsset" -OutFile "$root\PortableGit.7z.exe"
& "$root\PortableGit.7z.exe" -o"$root\pg" -y | Out-Null
Start-Sleep 5
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
$variants = 'stock', 'deps', 'all', 'allexe'
foreach ($v in $variants) {
    $d = "$root\$v"
    New-Item -ItemType Directory "$d\usr", "$d\tmp" | Out-Null
    Copy-Item "$root\pg\usr\bin" "$d\usr\bin" -Recurse
    foreach ($f in 'test-deps.sh', 'scale.sh', 'probe-exe.sh') { (Get-Content "$root\$f" -Raw) -replace "`r`n", "`n" | Set-Content "$d\$f" -NoNewline }
    if ($v -ne 'stock') { Get-ChildItem "$d\usr\bin\*.dll" | Where-Object { $v -ne 'deps' -or $_.Name -ne 'msys-2.0.dll' } | ForEach-Object { SetFlag $_.FullName } }
    if ($v -eq 'allexe') { Get-ChildItem "$d\usr\bin\*.exe" | ForEach-Object { SetFlag $_.FullName } }
}
$exes = 'bash.exe', 'timeout.exe', 'true.exe', 'sed.exe', 'xargs.exe', 'echo.exe'
function RunAll($label) {
    "########## $label"
    foreach ($v in $variants) {
        $d = "$root\$v"
        $dlls = Get-ChildItem "$d\usr\bin\*.dll"; $ex = Get-ChildItem "$d\usr\bin\*.exe"
        "===== $v  dll dynamicbase: $(@($dlls | Where-Object { Flag $_.FullName }).Count)/$($dlls.Count)  exe dynamicbase: $(@($ex | Where-Object { Flag $_.FullName }).Count)/$($ex.Count)"
        cmd /c "`"$d\usr\bin\bash.exe`" --norc /probe-exe.sh > `"$root\probe.log`" 2>&1"
        Get-Content "$root\probe.log" | Where-Object { $_ -notmatch 'dofork|fork: retry' }
        cmd /c "`"$d\usr\bin\bash.exe`" --norc /test-deps.sh > `"$root\$v.log`" 2>&1"
        "exit $LASTEXITCODE"
        Get-Content "$root\$v.log" | Where-Object { $_ -notmatch 'dofork|fork: retry' } | Select-Object -First 8
        "fork errors: $((Get-Content "$root\$v.log" | Where-Object { $_ -match 'dofork|child_info_fork|child_copy' }).Count)"
    }
}
"host: $((Get-CimInstance Win32_OperatingSystem).Version)  system Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)  Bottom-up: $((Get-ProcessMitigation -System).ASLR.BottomUp)"
RunAll "A. no per-process mitigations"
foreach ($e in $exes) { Set-ProcessMitigation -Name $e -Enable ForceRelocateImages }
"bash.exe mitigations now: $((Get-ProcessMitigation -Name bash.exe).ASLR | Out-String)"
RunAll "B. IFEO ForceRelocateImages on the test exes"
foreach ($e in $exes) { Set-ProcessMitigation -Name $e -Enable ForceRelocateImages, BottomUp, HighEntropy }
"bash.exe mitigations now: $((Get-ProcessMitigation -Name bash.exe).ASLR | Out-String)"
RunAll "C. IFEO ForceRelocateImages + BottomUp + HighEntropy on the test exes"
"--- scale on the allexe variant under C"
cmd /c "`"$root\allexe\usr\bin\bash.exe`" --norc /scale.sh 2000 8 250 > `"$root\scale.log`" 2>&1"
Get-Content "$root\scale.log" | Where-Object { $_ -notmatch 'dofork|fork: retry' }
"fork errors: $((Get-Content "$root\scale.log" | Where-Object { $_ -match 'dofork|child_info_fork|child_copy' }).Count)"
"done"
