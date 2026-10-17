# Runs inside the container after the sampler: boot timeline from the System log, then what the filesystem says about
# the runtime, bash and one sampled copy from each placement.
$ErrorActionPreference = 'Continue'
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
"boot $boot  uptime now $([Environment]::TickCount / 1000)"
try {
  Get-WinEvent -LogName System -Oldest -ErrorAction Stop | Where-Object { $_.TimeCreated -ge $boot.AddSeconds(-2) } | Select-Object -First 300 |
    ForEach-Object { "{0,7:F1}s {1} {2}: {3}" -f ($_.TimeCreated - $boot).TotalSeconds, $_.ProviderName, $_.Id, (($_.Message -split "`r?`n")[0]) }
} catch { "events: $_" }
foreach ($f in 'C:\msys64\usr\bin\msys-2.0.dll', 'C:\msys64\usr\bin\bash.exe', 'C:\samp\lower\L01.dll', 'C:\samp\top\T01.dll', 'C:\samp\both\B01.dll', 'C:\samp\top\R01.dll') {
  "== $f  attributes: $((Get-Item $f -Force).Attributes)"
  fsutil reparsepoint query $f 2>&1 | Select-Object -First 4
  fsutil file queryfileid $f 2>&1
}
"== filters"; fltmc filters 2>&1
"== volumes"; fltmc volumes 2>&1
