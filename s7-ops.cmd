@echo off
rem Which handle-level operation moves a layer file's image map to C:. Each T file untouched until its line; a fresh
rem process maps each afterwards. Then kernel file traces of a bash with no fork and a bash that forks, read properly.
set S=C:\samp\sampler3.exe
%S% fii C:\samp\top\T13.dll
%S% fid C:\samp\top\T14.dll
%S% vol C:\samp\top\T15.dll
%S% byid C:\samp\top\T16.dll
%S% attrs C:\samp\lower\L01.dll
%S% find C:\samp\lower\L02.dll
%S% loadlib C:\samp\lower\L03.dll
echo === second process maps each
for %%f in (top\T13 top\T14 top\T15 top\T16 lower\L01 lower\L02 lower\L03) do %S% map C:\samp\%%f.dll
echo === trace: bash with no fork
logman create trace kf1 -p Microsoft-Windows-Kernel-File 0xFFFFFFFF 0x5 -o C:\kf1.etl -ets >nul
C:\msys64\usr\bin\bash.exe --norc --noprofile -c "read -r w < /proc/$$/winpid; echo bash winpid $w; :"
logman stop kf1 -ets >nul
echo === trace: bash forking once
logman create trace kf2 -p Microsoft-Windows-Kernel-File 0xFFFFFFFF 0x5 -o C:\kf2.etl -ets >nul
C:\msys64\usr\bin\bash.exe --norc --noprofile -c "read -r w < /proc/$$/winpid; echo bash winpid $w; ( : ); echo fork rc $?"
logman stop kf2 -ets >nul
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\samp\readtrace.ps1
