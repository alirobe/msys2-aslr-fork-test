// Sends Ctrl+C to every process on this console, as a user pressing it would. Run from inside the container, as a child
// of the entry bash, to see whether the re-exec wrapper survives the event and bash handles it.
using System;
using System.Runtime.InteropServices;
using System.Threading;

class CtrlC
{
    [DllImport("kernel32", SetLastError = true)] static extern bool GenerateConsoleCtrlEvent(uint type, uint group);
    [DllImport("kernel32")] static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);

    static void Main()
    {
        SetConsoleCtrlHandler(IntPtr.Zero, true); // ignore it ourselves
        bool ok = GenerateConsoleCtrlEvent(0, 0);  // CTRL_C_EVENT to all processes sharing the console
        Console.WriteLine("ctrl-c sent to the console: {0}{1}", ok, ok ? "" : " error " + Marshal.GetLastWin32Error());
        Thread.Sleep(500);
    }
}
