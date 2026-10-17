// Container-start sampler for the Server 2019 Hyper-V fork failure. Every tick it maps, as an image, a copy of
// msys-2.0.dll that nothing has touched yet, from each placement (lower layer only, top layer only, in both layers, and
// top layer read in full first), and prints uptime, mapping base and the file backing the mapping. Each copy is mapped
// once, so one sample cannot influence the next.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

class Sampler
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
    [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32")] static extern ulong GetTickCount64();
    [DllImport("psapi", CharSet = CharSet.Unicode)] static extern uint GetMappedFileNameW(IntPtr proc, IntPtr addr, StringBuilder sb, uint n);

    static double Up() { return GetTickCount64() / 1000.0; }

    static string Map(string path)
    {
        if (!File.Exists(path)) return "missing";
        IntPtr h = LoadLibraryExW(path, IntPtr.Zero, 0x1); // DONT_RESOLVE_DLL_REFERENCES: the loader's own image section, no code run
        if (h == IntPtr.Zero) return "load failed " + Marshal.GetLastWin32Error();
        IntPtr b = new IntPtr(h.ToInt64() & ~3L);
        var sb = new StringBuilder(1024);
        GetMappedFileNameW(new IntPtr(-1), b, sb, 1024);
        FreeLibrary(h);
        return string.Format("0x{0:X} {1}", b.ToInt64(), sb);
    }

    static void Fltmc(string when)
    {
        try
        {
            var p = Process.Start(new ProcessStartInfo("fltmc", "instances") { UseShellExecute = false, RedirectStandardOutput = true });
            string o = p.StandardOutput.ReadToEnd(); p.WaitForExit();
            Console.WriteLine("fltmc instances at t={0:F1} ({1}):\n{2}", Up(), when, o.TrimEnd());
        }
        catch (Exception e) { Console.WriteLine("fltmc: " + e.Message); }
    }

    static void Main(string[] args)
    {
        int n = int.Parse(args[0]); int stepMs = int.Parse(args[1]); string root = args.Length > 2 ? args[2] : @"C:\samp";
        Console.WriteLine("sampler start t={0:F1}", Up());
        for (int k = 1; k <= n; k++)
        {
            string id = k.ToString("00");
            Console.WriteLine("t={0:F1} lower {1}", Up(), Map(root + @"\lower\L" + id + ".dll"));
            Console.WriteLine("t={0:F1} top   {1}", Up(), Map(root + @"\top\T" + id + ".dll"));
            Console.WriteLine("t={0:F1} both  {1}", Up(), Map(root + @"\both\B" + id + ".dll"));
            string r = root + @"\top\R" + id + ".dll";
            if (File.Exists(r)) File.ReadAllBytes(r);
            Console.WriteLine("t={0:F1} read  {1}", Up(), Map(r));
            if (k == 1 || k == n / 2) Fltmc("tick " + k);
            Thread.Sleep(stepMs);
        }
        Fltmc("end");
        Console.WriteLine("sampler end t={0:F1}", Up());
    }
}
