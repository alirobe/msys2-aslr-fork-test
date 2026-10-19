// Process start-to-exit timer. Each spec is label|exe|args.
//   bench.exe stats N spec...   N timed runs of each spec, interleaved (order reversed on odd rounds), after 20 warm-ups;
//                               prints mean, median, p95 and min in ms, and how many runs exited non-zero.
//   bench.exe once spec...      one run of each spec in order, no warm-up; prints each time in ms.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

class Bench
{
    static int failures;

    static double Time(string exe, string args)
    {
        var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false };
        var sw = Stopwatch.StartNew();
        using (var p = Process.Start(psi)) { p.WaitForExit(); if (p.ExitCode != 0) failures++; }
        return sw.Elapsed.TotalMilliseconds;
    }

    static void Main(string[] a)
    {
        bool once = a[0] == "once";
        var specs = a.Skip(once ? 1 : 2).Select(s => s.Split('|')).ToList();
        if (once)
        {
            foreach (var s in specs) { failures = 0; double t = Time(s[1], s[2]); Console.WriteLine("{0}: {1:F1} ms{2}", s[0], t, failures > 0 ? " (non-zero exit)" : ""); }
            return;
        }
        int n = int.Parse(a[1]);
        var times = specs.Select(_ => new List<double>()).ToList();
        var fails = new int[specs.Count];
        for (int w = 0; w < 20; w++) foreach (var s in specs) Time(s[1], s[2]);
        for (int i = 0; i < n; i++)
            for (int j = 0; j < specs.Count; j++)
            {
                int k = i % 2 == 0 ? j : specs.Count - 1 - j;
                failures = 0; times[k].Add(Time(specs[k][1], specs[k][2])); fails[k] += failures;
            }
        for (int k = 0; k < specs.Count; k++)
        {
            var t = times[k].OrderBy(x => x).ToList();
            Console.WriteLine("{0,-12} n={1} mean {2:F2} ms  median {3:F2}  p95 {4:F2}  min {5:F2}  non-zero exits {6}",
                specs[k][0], t.Count, t.Average(), t[t.Count / 2], t[(int)(t.Count * 0.95)], t[0], fails[k]);
        }
    }
}
