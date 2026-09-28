using System;
using Kisappear;

namespace Kisappear.Tests
{
    internal static class LineMathTests
    {
        private static int _failed;
        private static readonly System.Collections.Generic.List<string> _failures = new System.Collections.Generic.List<string>();

        private static void Eq(object actual, object expected, string name)
        {
            if (!Equals(actual, expected))
            {
                _failed++;
                _failures.Add(name + " -> expected [" + expected + "] got [" + actual + "]");
            }
        }

        internal static int Main()
        {
            LineBounds();
            CrlfHandling();
            WideChars();
            ColumnRoundTrip();
            VerticalNavigation();
            EdgeCases();

            if (_failed == 0)
            {
                Console.WriteLine("PASS  6/6 LineMath test groups");
                return 0;
            }
            Console.WriteLine("FAIL  " + _failed + " assertion(s)");
            foreach (var f in _failures) Console.WriteLine("  - " + f);
            return 1;
        }

        private static void LineBounds()
        {
            string t = "one\ntwo\nthree";
            Eq(LineMath.LineStart(t, 0), 0, "line start of 0");
            Eq(LineMath.LineStart(t, 5), 4, "line start mid second line");
            Eq(LineMath.LineEnd(t, 5), 7, "line end second line");
            Eq(LineMath.LineEnd(t, 12), 13, "line end last line");
            Eq(LineMath.LineIndexOf(t, 12), 2, "line index of last");
            Eq(LineMath.LineCount(t), 3, "line count");
        }

        private static void CrlfHandling()
        {
            string t = "ab\r\ncd";
            Eq(LineMath.LineEnd(t, 0), 2, "line end stops at \\n index");
            Eq(LineMath.VisualColumn(t, 2), 2, "crlf: column at \\r is 2");
            Eq(LineMath.VisualColumn(t, 5), 1, "crlf: column of second char in second line");
            Eq(LineMath.LineIndexOf(t, 5), 1, "crlf: second line index");
        }

        private static void WideChars()
        {
            string t = "中文ab";
            Eq(LineMath.VisualColumn(t, 0), 0, "wide: start col 0");
            Eq(LineMath.VisualColumn(t, 1), 2, "wide: after 中 col 2");
            Eq(LineMath.VisualColumn(t, 2), 4, "wide: after 中文 col 4");
            Eq(LineMath.VisualColumn(t, 4), 6, "wide: mixed ascii adds 1 each");
        }

        private static void ColumnRoundTrip()
        {
            string t = "中文ab";
            Eq(LineMath.IndexFromColumn(t, 0, 0), 0, "col 0 -> idx 0");
            Eq(LineMath.IndexFromColumn(t, 0, 2), 1, "col 2 -> idx 1");
            Eq(LineMath.IndexFromColumn(t, 0, 4), 2, "col 4 -> idx 2");
            Eq(LineMath.IndexFromColumn(t, 0, 6), 4, "col 6 -> idx 4");
            Eq(LineMath.IndexFromColumn(t, 0, 99), 4, "col beyond line clamps to line end");
            Eq(LineMath.IndexFromColumn(t, 0, 3), 2, "odd column inside a wide char snaps to next index");

            for (int i = 0; i <= t.Length; i++)
                Eq(LineMath.VisualColumn(t, LineMath.IndexFromColumn(t, 0, LineMath.VisualColumn(t, i))),
                   LineMath.VisualColumn(t, i), "roundtrip from " + i);
        }

        private static void VerticalNavigation()
        {
            string t = "abcdef\nghi\njk";
            Eq(LineMath.UpColumn(t, 9), 2, "up from line2 keeps visual column");
            Eq(LineMath.UpColumn(t, 0), -1, "up from first line");
            Eq(LineMath.DownColumn(t, 0), 7, "down keeps column");
            Eq(LineMath.DownColumn(t, 12), -1, "down from last line");
            Eq(LineMath.UpColumn(t, 12), 8, "up clamps to shorter line end");
        }

        private static void EdgeCases()
        {
            Eq(LineMath.VisualColumn("", 0), 0, "empty text column");
            Eq(LineMath.LineCount(""), 1, "empty text has one line");
            Eq(LineMath.IndexFromColumn("", 0, 5), 0, "empty text index clamp");
            Eq(LineMath.VisualColumn("abc", 99), 3, "index beyond end clamps");
        }
    }
}
