@echo off
rem Which access right in a read open moves a layer file's image map to C:. Each file untouched until its line;
rem a fresh process maps each afterwards. P01 is Server 2019's own version.dll, a full load with no runtime init.
set S=C:\samp\sampler3.exe
%S% acc C:\samp\top\T01.dll 1
%S% acc C:\samp\top\T02.dll 8
%S% acc C:\samp\top\T03.dll 20000
%S% acc C:\samp\top\T04.dll 88
%S% acc C:\samp\top\T05.dll 20088
%S% sd C:\samp\top\T06.dll
%S% ea C:\samp\top\T07.dll
%S% loadlib C:\samp\plain\P01.dll
%S% loadlib C:\samp\top\T08.dll
echo === second process maps each
for %%f in (top\T01 top\T02 top\T03 top\T04 top\T05 top\T06 top\T07 plain\P01 top\T08) do %S% map C:\samp\%%f.dll
