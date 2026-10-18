// Which handle-level operations move a layer file's image map from VSMB to C:. Each mode does one thing to an untouched
// file, then maps it as an image and prints base and backing file; "child" maps it from a fresh process afterwards.
//   fii    NtOpenFile (FILE_READ_ATTRIBUTES|SYNCHRONIZE, as the runtime's ntopenfile) + FileInternalInformation
//   fid    the same open + FileIdInformation
//   vol    the same open + FileFsAttributeInformation on the handle
//   byid   open the volume, then the file by its ID with FILE_READ_ATTRIBUTES (the runtime's hardlink path)
//   attrs  GetFileAttributesW, no handle
//   find   FindFirstFileW on the file
//   loadlib normal LoadLibraryW (imports resolved), kept while the child maps
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

class Sampler3
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryW(string f);
    [DllImport("kernel32")] static extern ulong GetTickCount64();
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern uint GetFileAttributesW(string f);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr FindFirstFileW(string f, IntPtr data);
    [DllImport("kernel32")] static extern bool FindClose(IntPtr h);
    [DllImport("psapi", CharSet = CharSet.Unicode)] static extern uint GetMappedFileNameW(IntPtr proc, IntPtr addr, StringBuilder sb, uint n);
    [DllImport("psapi", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool EnumProcessModulesEx(IntPtr proc, [Out] IntPtr[] mods, uint cb, out uint needed, uint filter);
    [DllImport("psapi", CharSet = CharSet.Unicode)] static extern uint GetModuleBaseNameW(IntPtr proc, IntPtr mod, StringBuilder sb, uint n);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr proc, int cls, IntPtr buf, uint len, out uint ret);

    static long Ppid(int pid)
    {
        IntPtr hp = OpenProcess(0x0400, false, pid); if (hp == IntPtr.Zero) return -1;
        IntPtr buf = Marshal.AllocHGlobal(48); uint ret; int s = NtQueryInformationProcess(hp, 0, buf, 48, out ret); NtClose(hp);
        return s == 0 ? Marshal.ReadInt64(buf, 40) : -1; // PROCESS_BASIC_INFORMATION.InheritedFromUniqueProcessId
    }
    [DllImport("ntdll")] static extern int NtOpenFile(out IntPtr h, uint access, ref OBJECT_ATTRIBUTES oa, out IO_STATUS_BLOCK io, uint share, uint opts);
    [DllImport("ntdll")] static extern int NtQueryInformationFile(IntPtr h, out IO_STATUS_BLOCK io, IntPtr buf, uint len, int cls);
    [DllImport("ntdll")] static extern int NtQueryVolumeInformationFile(IntPtr h, out IO_STATUS_BLOCK io, IntPtr buf, uint len, int cls);
    [DllImport("ntdll")] static extern int NtClose(IntPtr h);
    [DllImport("ntdll")] static extern int NtQuerySecurityObject(IntPtr h, uint info, IntPtr sd, uint len, out uint need);
    [DllImport("ntdll")] static extern int NtQueryEaFile(IntPtr h, out IO_STATUS_BLOCK io, IntPtr buf, uint len, bool single, IntPtr list, uint listLen, IntPtr index, bool restart);

    [StructLayout(LayoutKind.Sequential)] struct UNICODE_STRING { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] struct OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes; public IntPtr Sd, Sqos; }
    [StructLayout(LayoutKind.Sequential)] struct IO_STATUS_BLOCK { public IntPtr Status, Information; }

    const uint READ_ATTR_SYNC = 0x80 | 0x100000, SHARE_ALL = 7, OPTS = 0x40 | 0x20; // FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT

    static double Up() { return GetTickCount64() / 1000.0; }

    static string Map(string path)
    {
        IntPtr h = LoadLibraryExW(path, IntPtr.Zero, 0x1);
        if (h == IntPtr.Zero) return "load failed " + Marshal.GetLastWin32Error();
        var sb = new StringBuilder(1024);
        GetMappedFileNameW(new IntPtr(-1), h, sb, 1024);
        return string.Format("0x{0:X} {1}", h.ToInt64(), sb);
    }

    static IntPtr Open(string ntname, IntPtr root, uint access, uint opts, out int status)
    {
        var us = new UNICODE_STRING { Length = (ushort)(ntname.Length * 2), MaximumLength = (ushort)(ntname.Length * 2 + 2), Buffer = Marshal.StringToHGlobalUni(ntname) };
        IntPtr pus = Marshal.AllocHGlobal(Marshal.SizeOf(us)); Marshal.StructureToPtr(us, pus, false);
        var oa = new OBJECT_ATTRIBUTES { Length = Marshal.SizeOf(typeof(OBJECT_ATTRIBUTES)), RootDirectory = root, ObjectName = pus, Attributes = 0x40 };
        IntPtr h; IO_STATUS_BLOCK io;
        status = NtOpenFile(out h, access, ref oa, out io, SHARE_ALL, opts);
        return status == 0 ? h : IntPtr.Zero;
    }

    static IntPtr OpenById(IntPtr vol, long id, out int status)
    {
        IntPtr pid = Marshal.AllocHGlobal(8); Marshal.WriteInt64(pid, id);
        var us = new UNICODE_STRING { Length = 8, MaximumLength = 8, Buffer = pid };
        IntPtr pus = Marshal.AllocHGlobal(Marshal.SizeOf(us)); Marshal.StructureToPtr(us, pus, false);
        var oa = new OBJECT_ATTRIBUTES { Length = Marshal.SizeOf(typeof(OBJECT_ATTRIBUTES)), RootDirectory = vol, ObjectName = pus, Attributes = 0x40 };
        IntPtr h; IO_STATUS_BLOCK io;
        status = NtOpenFile(out h, READ_ATTR_SYNC, ref oa, out io, SHARE_ALL, OPTS | 0x2000); // FILE_OPEN_BY_FILE_ID
        return status == 0 ? h : IntPtr.Zero;
    }

    static long Fii(IntPtr h)
    {
        IntPtr buf = Marshal.AllocHGlobal(8); IO_STATUS_BLOCK io;
        int s = NtQueryInformationFile(h, out io, buf, 8, 6); // FileInternalInformation
        return s == 0 ? Marshal.ReadInt64(buf) : -1;
    }

    static void Main(string[] a)
    {
        string mode = a[0], path = a[1]; string nt = @"\??\" + path; string tag = mode + " " + Path.GetFileName(path);
        int st; IntPtr h;
        switch (mode)
        {
            case "fii": h = Open(nt, IntPtr.Zero, READ_ATTR_SYNC, OPTS, out st); Console.WriteLine("t={0:F1} {1} open {2:X} id {3:X}", Up(), tag, st, Fii(h)); NtClose(h); break;
            case "fid": { h = Open(nt, IntPtr.Zero, READ_ATTR_SYNC, OPTS, out st); IntPtr buf = Marshal.AllocHGlobal(24); IO_STATUS_BLOCK io; int s = NtQueryInformationFile(h, out io, buf, 24, 59); Console.WriteLine("t={0:F1} {1} open {2:X} fid {3:X}", Up(), tag, st, s); NtClose(h); break; }
            case "vol": { h = Open(nt, IntPtr.Zero, READ_ATTR_SYNC, OPTS, out st); IntPtr buf = Marshal.AllocHGlobal(512); IO_STATUS_BLOCK io; int s = NtQueryVolumeInformationFile(h, out io, buf, 512, 5); Console.WriteLine("t={0:F1} {1} open {2:X} fsattr {3:X} flags {4:X}", Up(), tag, st, s, Marshal.ReadInt32(buf)); NtClose(h); break; }
            case "byid":
                {
                    h = Open(nt, IntPtr.Zero, READ_ATTR_SYNC, OPTS, out st); long id = Fii(h); NtClose(h);
                    IntPtr vol = Open(nt.Substring(0, 6), IntPtr.Zero, READ_ATTR_SYNC, 0, out st); // "\??\C:"
                    IntPtr fh = OpenById(vol, id, out st); Console.WriteLine("t={0:F1} {1} by-id open {2:X}", Up(), tag, st); if (fh != IntPtr.Zero) NtClose(fh); NtClose(vol); break;
                }
            case "acc": { uint acc = Convert.ToUInt32(a[2], 16); h = Open(nt, IntPtr.Zero, acc | 0x100000, OPTS, out st); Console.WriteLine("t={0:F1} {1} access {2:X} open {3:X}", Up(), tag, acc, st); if (h != IntPtr.Zero) NtClose(h); break; }
            case "procs":
                {
                    // Every bash, sh and gawk process: for the exe, the runtime and gmp, the base and the file the mapping is backed by.
                    foreach (var p in Process.GetProcesses())
                    {
                        if (!(p.ProcessName == "bash" || p.ProcessName == "sh" || p.ProcessName == "gawk")) continue;
                        IntPtr hp = OpenProcess(0x0400 | 0x0010, false, p.Id);
                        if (hp == IntPtr.Zero) { Console.WriteLine("pid {0} {1}: open failed {2}", p.Id, p.ProcessName, Marshal.GetLastWin32Error()); continue; }
                        IntPtr[] mods = new IntPtr[512]; uint needed;
                        if (!EnumProcessModulesEx(hp, mods, (uint)(mods.Length * IntPtr.Size), out needed, 0x3)) { Console.WriteLine("pid {0} {1}: enum failed {2}", p.Id, p.ProcessName, Marshal.GetLastWin32Error()); continue; }
                        Console.WriteLine("pid {0} ppid {1} {2}", p.Id, Ppid(p.Id), p.ProcessName);
                        for (int i = 0; i < needed / IntPtr.Size; i++)
                        {
                            var bn = new StringBuilder(260); GetModuleBaseNameW(hp, mods[i], bn, 260); string b = bn.ToString().ToLowerInvariant();
                            if (!(b == "msys-2.0.dll" || b.EndsWith(".exe") || b == "msys-gmp-10.dll" || b == "fork.dll")) continue;
                            var mf = new StringBuilder(1024); GetMappedFileNameW(hp, mods[i], mf, 1024);
                            Console.WriteLine("   0x{0:X} {1,-16} {2}", mods[i].ToInt64(), b, mf);
                        }
                        NtClose(hp);
                    }
                    return;
                }
            case "accdir":
                {
                    // Open every DLL and exe in a directory with FILE_READ_DATA and close it again, as a sweep would.
                    int n = 0, failed = 0;
                    foreach (string f in Directory.GetFiles(path)) { if (!f.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) && !f.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) continue; h = Open(@"\??\" + f, IntPtr.Zero, 0x1 | 0x100000, OPTS, out st); if (h != IntPtr.Zero) { NtClose(h); n++; } else failed++; }
                    Console.WriteLine("t={0:F1} accdir {1}: {2} files opened for read, {3} failed", Up(), path, n, failed); return;
                }
            case "sd": { h = Open(nt, IntPtr.Zero, 0x20000 | 0x100000, OPTS, out st); IntPtr buf = Marshal.AllocHGlobal(4096); uint need; int s = NtQuerySecurityObject(h, 0x7, buf, 4096, out need); Console.WriteLine("t={0:F1} {1} open {2:X} sd {3:X}", Up(), tag, st, s); NtClose(h); break; }
            case "ea": { h = Open(nt, IntPtr.Zero, 0x8 | 0x100000, OPTS, out st); IntPtr buf = Marshal.AllocHGlobal(4096); IO_STATUS_BLOCK io; int s = NtQueryEaFile(h, out io, buf, 4096, true, IntPtr.Zero, 0, IntPtr.Zero, true); Console.WriteLine("t={0:F1} {1} open {2:X} ea {3:X}", Up(), tag, st, s); NtClose(h); break; }
            case "attrs": Console.WriteLine("t={0:F1} {1} attrs {2:X}", Up(), tag, GetFileAttributesW(path)); break;
            case "find": { IntPtr d = Marshal.AllocHGlobal(1024); IntPtr fh = FindFirstFileW(path, d); Console.WriteLine("t={0:F1} {1} find {2}", Up(), tag, fh != new IntPtr(-1)); FindClose(fh); break; }
            case "loadlib":
                {
                    IntPtr lh = LoadLibraryW(path); var sb = new StringBuilder(1024); GetMappedFileNameW(new IntPtr(-1), lh, sb, 1024);
                    Console.WriteLine("t={0:F1} {1} 0x{2:X} {3}", Up(), tag, lh.ToInt64(), sb);
                    var p = Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, "map \"" + path + "\"") { UseShellExecute = false, RedirectStandardOutput = true });
                    Console.Write(p.StandardOutput.ReadToEnd()); p.WaitForExit(); return;
                }
            case "map": Console.WriteLine("t={0:F1} {1} {2}", Up(), tag, Map(path)); return;
        }
        Console.WriteLine("t={0:F1} {1} then map {2}", Up(), tag, Map(path));
    }
}
