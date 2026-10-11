# Runs on a GitHub Actions Windows runner. Builds three usr\bin variants of Portable Git: stock (as shipped),
# deps (every DLL except msys-2.0.dll gets dynamicbase), all (every DLL). Runs fork tests on the host with
# Mandatory ASLR off (the runner default), then turns Mandatory ASLR on system-wide and runs them again.
param([string]$GitTag = "v2.56.0.windows.2", [string]$GitAsset = "PortableGit-2.56.0.2-64-bit.7z.exe")
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/$GitTag/$GitAsset" -OutFile "$root\PortableGit.7z.exe"
& "$root\PortableGit.7z.exe" -o"$root\pg" -y | Out-Null
Start-Sleep 5
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
foreach ($v in 'stock', 'deps', 'all') {
    $d = "$root\$v"
    New-Item -ItemType Directory "$d\usr", "$d\tmp" | Out-Null
    Copy-Item "$root\pg\usr\bin" "$d\usr\bin" -Recurse
    Copy-Item "$root\test-deps.sh" "$d\test.sh"
    (Get-Content "$d\test.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$d\test.sh" -NoNewline
    if ($v -ne 'stock') { Get-ChildItem "$d\usr\bin\*.dll" | Where-Object { $v -eq 'all' -or $_.Name -ne 'msys-2.0.dll' } | ForEach-Object { SetFlag $_.FullName } }
}
function RunAll($label) {
    "########## $label  host: $((Get-CimInstance Win32_OperatingSystem).Version)  Mandatory ASLR: $((Get-ProcessMitigation -System).ASLR.ForceRelocateImages)"
    foreach ($v in 'stock', 'deps', 'all') {
        $d = "$root\$v"
        $dlls = Get-ChildItem "$d\usr\bin\*.dll"
        "===== $v  dynamicbase: $(@($dlls | Where-Object { Flag $_.FullName }).Count)/$($dlls.Count)  runtime flagged: $(Flag "$d\usr\bin\msys-2.0.dll")"
        cmd /c "`"$d\usr\bin\bash.exe`" --norc /test.sh > `"$root\$v.log`" 2>&1"
        "exit $LASTEXITCODE"
        Get-Content "$root\$v.log" | Where-Object { $_ -notmatch 'dofork|fork: retry' } | Select-Object -First 8
        "fork errors: $((Get-Content "$root\$v.log" | Where-Object { $_ -match 'dofork' }).Count)"
    }
}
RunAll "A. as the runner ships"
Set-ProcessMitigation -System -Enable ForceRelocateImages, BottomUp
RunAll "B. after Set-ProcessMitigation -System -Enable ForceRelocateImages (no reboot)"
"done"
