@echo off
rem Timing probe: one bash at container start (forks after 60 s), then fresh bashes at about 20 s and 60 s.
start "" /b C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh early 60
ping -n 21 127.0.0.1 >nul
C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh late20 0
ping -n 41 127.0.0.1 >nul
C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh late60 0
