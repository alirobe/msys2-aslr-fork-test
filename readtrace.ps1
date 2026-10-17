# Convert the kernel file traces and print the events that name the runtime, with process IDs. tracerpt writes UTF-16,
# which is why findstr found nothing before.
foreach ($n in 'kf1', 'kf2') {
  tracerpt "C:\$n.etl" -o "C:\$n.csv" -of CSV -y | Out-Null
  $rows = Get-Content "C:\$n.csv"
  "=== $n : $($rows.Count) rows; header:"
  $rows[0]
  "--- rows naming msys-2.0.dll or bash.exe (first 80)"
  $rows | Select-String -SimpleMatch 'msys-2.0.dll', 'bash.exe' | Select-Object -First 80 | ForEach-Object { $_.Line }
}
