@echo off
rem Which kind of access, before the first image map, decides where the map comes from. Each file is untouched until here.
set S=C:\samp\sampler2.exe
%S% map C:\samp\top\T01.dll
%S% attr C:\samp\top\T02.dll map
%S% open C:\samp\top\T03.dll map
%S% read1 C:\samp\top\T04.dll map
rem And what a second process gets for each afterwards.
%S% map C:\samp\top\T01.dll
%S% map C:\samp\top\T02.dll
%S% map C:\samp\top\T03.dll
%S% map C:\samp\top\T04.dll
