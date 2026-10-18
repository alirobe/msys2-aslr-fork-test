# Runs on the lab VM host against C:\msys64 (the MSYS2 install there). Flags every DLL and exe in usr\bin dynamicbase
# first, the way the rebuilt packages will ship, then runs upgrade-hazard.sh. Reports system ASLR for context.
$ErrorActionPreference = 'Continue'
$m = (Get-ProcessMitigation -System).ASLR
"system ASLR: ForceRelocateImages=$($m.ForceRelocateImages) BottomUp=$($m.BottomUp)"
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); if (-not ($c -band 0x40)) { [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b); return 1 }; 0 }
$n = 0; Get-ChildItem 'C:\msys64\usr\bin\*.dll', 'C:\msys64\usr\bin\*.exe' | ForEach-Object { $n += SetFlag $_.FullName }
"flagged $n files in C:\msys64\usr\bin"
(Get-Content 'C:\lab\fork-test\upgrade-hazard.sh' -Raw) -replace "`r`n", "`n" | Set-Content 'C:\msys64\upgrade-hazard.sh' -NoNewline
$env:MSYSTEM = 'MSYS'; $env:CHERE_INVOKING = '1'
& C:\msys64\usr\bin\bash.exe -lc 'bash /upgrade-hazard.sh' 2>&1 | ForEach-Object { "$_" }
