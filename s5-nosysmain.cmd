@echo off
rem The failing shape with SysMain (the prefetcher's service) stopped first.
sc stop SysMain >nul
ping -n 4 127.0.0.1 >nul
sc query SysMain | findstr STATE
C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh nosysmain 0
