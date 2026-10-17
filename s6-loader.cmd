@echo off
rem Loader test with a plain Windows exe, each DLL untouched until its scenario; then the same under a kernel file trace.
set L=C:\samp\loader.exe
echo === parent maps, child maps, parent maps again
%L% parent-child C:\samp\top\T08.dll
echo === parent maps twice, no child
%L% parent-twice C:\samp\top\T09.dll
echo === parent maps, child read-opens then maps
%L% parent-child-read C:\samp\top\T10.dll
echo === no parent map, two bare children
%L% nomap-child C:\samp\top\T11.dll
echo === traced: parent maps, child maps
logman start "NT Kernel Logger" -p "Windows Kernel Trace" (process,thread,img,file,fileio,fileiocompletion) -o C:\nt.etl -ets >nul
%L% parent-child C:\samp\top\T12.dll
logman stop "NT Kernel Logger" -ets >nul
tracerpt C:\nt.etl -o C:\nt.csv -of CSV -y >nul
echo --- trace lines naming T12
findstr /i "T12.dll" C:\nt.csv
echo --- trace line count
find /c /v "" C:\nt.csv
