@echo off
rem Who opens msys-2.0.dll around a failing fork: kernel file-create events with process IDs.
logman create trace kf -p Microsoft-Windows-Kernel-File 0x190 0x5 -o C:\kf.etl -ets >nul
echo trace started
C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh etw 0
logman stop kf -ets >nul
tracerpt C:\kf.etl -o C:\kf.csv -of CSV -y >nul
echo === file events naming the runtime
findstr /i /c:"msys-2.0.dll" C:\kf.csv
echo === processes and services
tasklist /svc
echo === prefetch
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
dir /b C:\Windows\Prefetch | findstr /i "bash cmd"
