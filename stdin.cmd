@echo off
echo hello from a pipe | C:\msys64\usr\bin\bash.exe --norc --noprofile -c "read -r l; echo got: $l; (echo fork after stdin ok)"
echo pipe test rc %ERRORLEVEL%
