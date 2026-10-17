@echo off
rem The fork's shape: one process holds an image map, something else touches the file, a new process maps it.
set S=C:\samp\sampler2.exe
start "" /b %S% hold C:\samp\top\T05.dll 25
ping -n 3 127.0.0.1 >nul
%S% map C:\samp\top\T05.dll
start "" /b %S% hold C:\samp\top\T06.dll 20
ping -n 3 127.0.0.1 >nul
%S% attr C:\samp\top\T06.dll
%S% map C:\samp\top\T06.dll
start "" /b %S% hold C:\samp\top\T07.dll 15
ping -n 3 127.0.0.1 >nul
%S% read1 C:\samp\top\T07.dll
%S% map C:\samp\top\T07.dll
ping -n 20 127.0.0.1 >nul
