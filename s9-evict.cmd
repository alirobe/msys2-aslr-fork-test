@echo off
rem Does a moved file stay moved? T01: read open, then every DLL and exe in usr\bin opened for read, then a fresh process
rem maps T01. T02: read open, 30 s, map. T03: read open, map at once (control). Then a second sweep and the three mapped
rem again, and T01 mapped by a holding process and a fresh one at the same time.
set S=C:\samp\sampler3.exe
%S% acc C:\samp\top\T01.dll 1
%S% accdir C:\msys64\usr\bin
%S% map C:\samp\top\T01.dll
%S% acc C:\samp\top\T02.dll 1
ping -n 31 127.0.0.1 > nul
%S% map C:\samp\top\T02.dll
%S% acc C:\samp\top\T03.dll 1
%S% map C:\samp\top\T03.dll
echo === second sweep
%S% accdir C:\msys64\usr\bin
%S% map C:\samp\top\T01.dll
%S% map C:\samp\top\T02.dll
%S% map C:\samp\top\T03.dll
echo === held map and a fresh one together
start /b C:\samp\sampler2.exe hold C:\samp\top\T01.dll 12
ping -n 4 127.0.0.1 > nul
%S% map C:\samp\top\T01.dll
ping -n 12 127.0.0.1 > nul
echo s9 done
