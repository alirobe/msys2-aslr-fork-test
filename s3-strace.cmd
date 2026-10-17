@echo off
rem What the runtime itself does to msys-2.0.dll around a fork, from its own debug trace.
C:\msys64\usr\bin\strace.exe -o C:\st.txt C:\msys64\usr\bin\bash.exe --norc --noprofile -c "( : ); echo rc $?"
echo === trace lines naming the runtime, process creation and the copy
findstr /i /c:"msys-2.0.dll" /c:"CreateProcessW" /c:"child_copy" C:\st.txt
