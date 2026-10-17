@echo off
rem Nothing touches the runtime until bash starts about 20 s in.
ping -n 21 127.0.0.1 >nul
C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh late 0
