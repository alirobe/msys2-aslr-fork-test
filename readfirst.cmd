@echo off
rem Read the runtime through C: before anything maps it, then start bash straight away.
copy /b C:\msys64\usr\bin\msys-2.0.dll nul >nul
C:\msys64\usr\bin\bash.exe --norc --noprofile /probe-entry.sh readfirst 0
