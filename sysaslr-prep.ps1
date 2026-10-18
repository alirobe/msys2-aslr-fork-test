# Runs on the lab VM host (not in a container). Portable Git 2.56.0.2 twice: as shipped, and with every usr\bin DLL
# and exe flagged dynamicbase. Copies the test scripts in. Prints the current system ASLR policy.
param([string]$Lab = 'C:\lab\sysaslr')
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Path $Lab, 'C:\lab\dl' -Force | Out-Null
$pg7z = 'C:\lab\dl\PortableGit-2.56.0.2-64-bit.7z.exe'
if (-not (Test-Path $pg7z)) { Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/PortableGit-2.56.0.2-64-bit.7z.exe' -OutFile $pg7z }
function Flag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); ([BitConverter]::ToUInt16($b, $pe + 94) -band 0x40) -ne 0 }
function SetFlag($p) { $b = [IO.File]::ReadAllBytes($p); $pe = [BitConverter]::ToInt32($b, 0x3c); $c = [BitConverter]::ToUInt16($b, $pe + 94); [Array]::Copy([BitConverter]::GetBytes([uint16]($c -bor 0x40)), 0, $b, $pe + 94, 2); [IO.File]::WriteAllBytes($p, $b) }
foreach ($v in 'stock', 'allexe') {
  $d = "$Lab\$v"
  if (-not (Test-Path "$d\usr\bin\bash.exe")) {
    & $pg7z -o"$d" -y | Out-Null; Start-Sleep 5
    if ($v -eq 'allexe') { Get-ChildItem "$d\usr\bin\*.dll", "$d\usr\bin\*.exe", "$d\cmd\git.exe", "$d\mingw64\bin\*.exe", "$d\mingw64\bin\*.dll" | ForEach-Object { SetFlag $_.FullName } }
  }
  New-Item -ItemType Directory "$d\tmp" -Force | Out-Null
  foreach ($f in 'test-deps.sh', 'scale.sh', 'probe-exe.sh', 'git-work.sh') { (Get-Content "C:\lab\fork-test\$f" -Raw) -replace "`r`n", "`n" | Set-Content "$d\$f" -NoNewline }
  $dlls = Get-ChildItem "$d\usr\bin\*.dll"; $ex = Get-ChildItem "$d\usr\bin\*.exe"
  "$v  dll dynamicbase: $(@($dlls | Where-Object { Flag $_.FullName }).Count)/$($dlls.Count)  exe dynamicbase: $(@($ex | Where-Object { Flag $_.FullName }).Count)/$($ex.Count)  git.exe: $(Flag "$d\cmd\git.exe")"
}
$m = (Get-ProcessMitigation -System).ASLR
"system ASLR now: ForceRelocateImages=$($m.ForceRelocateImages) BottomUp=$($m.BottomUp) HighEntropy=$($m.HighEntropy)"
