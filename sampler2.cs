// Single-shot probe for the Server 2019 Hyper-V fork failure: one kind of access to one file, then (optionally) an image
// map of it, printing uptime, base and the file backing the mapping. Modes:
//   map FILE            image map only
//   attr FILE [map]     open with FILE_READ_ATTRIBUTES only (what the runtime does to DLLs before a fork), close
//   open FILE [map]     open with GENERIC_READ, read nothing, close
//   read1 FILE [map]    read one byte
//   hold FILE SECS      image map and keep it for SECS seconds
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

class Sampler2
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
    [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32")] static extern ulong GetTickCount64();
    [DllImport("psapi", CharSet = CharSet.Unicode)] static extern uint GetMappedFileNameW(IntPtr proc, IntPtr addr, StringBuilder sb, uint n);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string f, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);

    static double Up() { return GetTickCount64() / 1000.0; }

    static IntPtr MapPrint(string tag, string path)
    {
        IntPtr h = LoadLibraryExW(path, IntPtr.Zero, 0x1);
        if (h == IntPtr.Zero) { Console.WriteLine("t={0:F1} {1} load failed {2}", Up(), tag, Marshal.GetLastWin32Error()); return h; }
        var sb = new StringBuilder(1024);
        GetMappedFileNameW(new IntPtr(-1), h, sb, 1024);
        Console.WriteLine("t={0:F1} {1} 0x{2:X} {3}", Up(), tag, h.ToInt64(), sb);
        return h;
    }

    static void Open(string tag, string path, uint access, bool readOne)
    {
        using (var fh = CreateFileW(path, access, 7, IntPtr.Zero, 3, 0, IntPtr.Zero))
        {
            if (fh.IsInvalid) { Console.WriteLine("t={0:F1} {1} open failed {2}", Up(), tag, Marshal.GetLastWin32Error()); return; }
            if (readOne) using (var fs = new FileStream(fh, FileAccess.Read)) fs.ReadByte();
            Console.WriteLine("t={0:F1} {1} done", Up(), tag);
        }
    }

    static void Main(string[] a)
    {
        string mode = a[0], path = a[1]; bool map = a.Length > 2 && a[2] == "map";
        string tag = mode + " " + Path.GetFileName(path);
        switch (mode)
        {
            case "map": FreeLibrary(MapPrint(tag, path)); break;
            case "attr": Open(tag, path, 0x80, false); break;
            case "open": Open(tag, path, 0x80000000, false); break;
            case "read1": Open(tag, path, 0x80000000, true); break;
            case "hold": IntPtr h = MapPrint(tag, path); Thread.Sleep(int.Parse(a[2]) * 1000); FreeLibrary(h); Console.WriteLine("t={0:F1} {1} released", Up(), tag); return;
        }
        if (map && mode != "map") FreeLibrary(MapPrint(tag + " then map", path));
    }
}
