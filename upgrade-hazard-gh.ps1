# Runs on a GitHub Actions runner against the MSYS2 that setup-msys2 installed. Flags every usr\bin DLL and exe
# dynamicbase (as the rebuilt packages will ship), then runs the hazard twice: without /var/run/cygfork (Cygwin's
# hardlink retry off, the MSYS2 default) and with it. No MSYS2 process may be alive between the two, because the
# runtime caches whether the directory exists for as long as any MSYS2 process runs.
param([string]$Msys2 = 'D:\a\_temp\msys64')
$ErrorActionPreference = 'Continue'
if (-not (Test-Path "$Msys2\usr\bin\bash.exe")) { throw "no MSYS2 at '$Msys2'" }
"msys2 at $Msys2"
$m = (Get-ProcessMitigation -System).ASLR
"system ASLR: ForceRelocateImages=$($m.ForceRelocateImages) BottomUp=$($m.BottomUp)"
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); if (-not ($c -band 0x40)) { [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b); return 1 }; 0 }
$n = 0; Get-ChildItem "$Msys2\usr\bin\*.dll", "$Msys2\usr\bin\*.exe" | ForEach-Object { $n += SetFlag $_.FullName }
"flagged $n files in $Msys2\usr\bin"
(Get-Content "$PSScriptRoot\upgrade-hazard.sh" -Raw) -replace "`r`n", "`n" | Set-Content "$Msys2\upgrade-hazard.sh" -NoNewline
$env:MSYSTEM = 'MSYS'; $env:CHERE_INVOKING = '1'
function Kill-Msys { Get-Process | Where-Object { $_.Path -like "$Msys2\*" } | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
Kill-Msys
"################ without /var/run/cygfork"
Remove-Item "$Msys2\var\run\cygfork" -Recurse -Force -ErrorAction SilentlyContinue
& "$Msys2\usr\bin\bash.exe" -lc 'bash /upgrade-hazard.sh' 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'fork: retry' }
Kill-Msys
"################ with /var/run/cygfork"
New-Item -ItemType Directory "$Msys2\var\run\cygfork" -Force | Out-Null
& "$Msys2\usr\bin\bash.exe" -lc 'bash /upgrade-hazard.sh' 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'fork: retry' }
Kill-Msys
"done"
