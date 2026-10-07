# Does the MSYS2 runtime fork() with ASLR enabled inside Windows containers?

Reproduction for the Docker-only fork failures that led MSYS2 to revert
"Cygwin: Enable dynamicbase on the Cygwin DLL by default" in December 2022
(https://cygwin.com/pipermail/cygwin/2022-December/252711.html).

The workflow downloads Portable Git, sets only the dynamicbase bit on its
msys-2.0.dll (no rebuild), builds Windows container images with the stock and
the flagged DLL, and runs fork tests under process and Hyper-V isolation.
