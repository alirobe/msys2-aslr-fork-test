@echo off
rem Is a swept file's move complete when the sweep returns? Every DLL and exe in usr\bin opened for read, then a fresh
rem process maps msys-gmp-10.dll at once, again after 10 s, and T12 (read open only, no view) mapped at once and held while
rem another process maps it. T13: read open, then a data view (as the runtime's compare does), then map at once.
set S=C:\samp\sampler3.exe
%S% accdir C:\msys64\usr\bin
%S% map C:\msys64\usr\bin\msys-gmp-10.dll
%S% map C:\msys64\usr\bin\msys-iconv-2.dll
%S% map C:\msys64\usr\bin\bash.exe
ping -n 11 127.0.0.1 > nul
%S% map C:\msys64\usr\bin\msys-gmp-10.dll
%S% map C:\msys64\usr\bin\msys-iconv-2.dll
%S% map C:\msys64\usr\bin\bash.exe
echo === T12: read open only, map at once and hold, a fresh map 2 s later
%S% acc C:\samp\top\T12.dll 1
start /b C:\samp\sampler2.exe hold C:\samp\top\T12.dll 8
ping -n 3 127.0.0.1 > nul
%S% map C:\samp\top\T12.dll
ping -n 8 127.0.0.1 > nul
echo s10 done
