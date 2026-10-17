// Loader test, no MSYS2 involved. Parent maps an untouched DLL as an image, then starts a child of itself that maps the
// same DLL; both print base and backing file. If the child's map comes from C: at another base while the parent's is
// from VSMB, the child's own loader open is what moves the file. Variants: a second map in the parent, a child that
// read-opens before mapping, and a child started while the parent holds no map.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

class Loader
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
    [DllImport("kernel32")] static extern ulong GetTickCount64();
    [DllImport("psapi", CharSet = CharSet.Unicode)] static extern uint GetMappedFileNameW(IntPtr proc, IntPtr addr, StringBuilder sb, uint n);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string f, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);

    static double Up() { return GetTickCount64() / 1000.0; }

    static string Map(string path)
    {
        IntPtr h = LoadLibraryExW(path, IntPtr.Zero, 0x1);
        if (h == IntPtr.Zero) return "load failed " + Marshal.GetLastWin32Error();
        var sb = new StringBuilder(1024);
        GetMappedFileNameW(new IntPtr(-1), h, sb, 1024);
        return string.Format("0x{0:X} {1}", h.ToInt64(), sb);
    }

    static string Child(string args)
    {
        var p = Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, args) { UseShellExecute = false, RedirectStandardOutput = true });
        string o = p.StandardOutput.ReadToEnd().TrimEnd(); p.WaitForExit(); return o;
    }

    static void Main(string[] a)
    {
        string mode = a[0], dll = a[1];
        switch (mode)
        {
            case "child":
                Console.WriteLine("t={0:F1}   child map       {1}", Up(), Map(dll)); break;
            case "child-read":
                using (var fh = CreateFileW(dll, 0x80000000, 7, IntPtr.Zero, 3, 0, IntPtr.Zero)) { }
                Console.WriteLine("t={0:F1}   child read+map  {1}", Up(), Map(dll)); break;
            case "parent-child":           // the fork's shape
                Console.WriteLine("t={0:F1} parent map        {1}", Up(), Map(dll));
                Console.WriteLine(Child("child \"" + dll + "\""));
                Console.WriteLine("t={0:F1} parent map again  {1}", Up(), Map(dll)); break;
            case "parent-twice":           // same process, two maps, no child
                Console.WriteLine("t={0:F1} parent map        {1}", Up(), Map(dll));
                Console.WriteLine("t={0:F1} parent map again  {1}", Up(), Map(dll)); break;
            case "parent-child-read":      // child read-opens first
                Console.WriteLine("t={0:F1} parent map        {1}", Up(), Map(dll));
                Console.WriteLine(Child("child-read \"" + dll + "\"")); break;
            case "nomap-child":            // parent never maps; does a bare child map come from VSMB?
                Console.WriteLine(Child("child \"" + dll + "\""));
                Console.WriteLine(Child("child \"" + dll + "\"")); break;
        }
    }
}
