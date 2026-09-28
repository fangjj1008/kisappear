using System;

namespace Kisappear
{
    /// <summary>
    /// 纯函数行/列计算。文本可能含 \r\n（宿主 TextBox 的换行风格），一律以 '\n' 作行尾。
    /// 视觉列按"宽字符占两格"折算：等宽字体下中日韩全角字符实际占两个字符宽，
    /// 直接拿 UTF-16 索引差当列数会让光标位置越打越偏。
    /// </summary>
    public static class LineMath
    {
        public static int LineStart(string text, int index)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int i = Clamp(index, 0, text.Length);
            while (i > 0 && text[i - 1] != '\n') i--;
            return i;
        }

        /// <summary>行尾索引（不含换行符）。CRLF 停在 '\r' 前，避免光标落进 \r 和 \n 之间。</summary>
        public static int LineEnd(string text, int index)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int i = Clamp(index, 0, text.Length);
            while (i < text.Length && text[i] != '\n')
            {
                if (text[i] == '\r' && i + 1 < text.Length && text[i + 1] == '\n') break;
                i++;
            }
            return i;
        }

        /// <summary>行内可视列（宽字符计 2）。'\r' 紧跟 '\n' 时不计入。</summary>
        public static int VisualColumn(string text, int index)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int start = LineStart(text, index);
            int end = LineEnd(text, index);
            int col = 0;
            for (int i = start; i < Clamp(index, 0, text.Length); i++)
            {
                if (text[i] == '\r' && i + 1 < end && text[i + 1] == '\n') continue;
                col += IsWide(text[i]) ? 2 : 1;
            }
            return col;
        }

        /// <summary>把可视列换算回索引；超出行长时返回行尾索引。</summary>
        public static int IndexFromColumn(string text, int lineStart, int column)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int end = LineEnd(text, lineStart);
            int i = Clamp(lineStart, 0, text.Length);
            int col = 0;
            while (i < end && col < column)
            {
                if (text[i] == '\r' && i + 1 < end && text[i + 1] == '\n') { i++; continue; }
                col += IsWide(text[i]) ? 2 : 1;
                if (col > column) { return i + 1 > end ? end : i + 1; }
                i++;
            }
            return i > end ? end : i;
        }

        public static int LineIndexOf(string text, int index)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int n = 0;
            int limit = Clamp(index, 0, text.Length);
            for (int i = 0; i < limit; i++) if (text[i] == '\n') n++;
            return n;
        }

        public static int LineCount(string text)
        {
            if (string.IsNullOrEmpty(text)) return 1;
            int n = 1;
            for (int i = 0; i < text.Length; i++) if (text[i] == '\n') n++;
            return n;
        }

        /// <summary>上一行同列的索引；已在首行时返回 -1。</summary>
        public static int UpColumn(string text, int index)
        {
            if (string.IsNullOrEmpty(text)) return -1;
            int ls = LineStart(text, index);
            if (ls == 0) return -1;
            int col = VisualColumn(text, index);
            int prevStart = LineStart(text, ls - 1);
            return IndexFromColumn(text, prevStart, col);
        }

        public static int DownColumn(string text, int index)
        {
            if (string.IsNullOrEmpty(text)) return -1;
            int le = LineEnd(text, index);
            if (le >= text.Length) return -1;
            int next = le + 1;
            int col = VisualColumn(text, index);
            return IndexFromColumn(text, next, col);
        }

        public static bool IsWide(char c)
        {
            return (c >= 0x1100 && c <= 0x115F)      // 韩文字母 Jamo
                   || (c >= 0x2E80 && c <= 0x303E)   // CJK 部首、假名、标点
                   || (c >= 0x3041 && c <= 0x33FF)
                   || (c >= 0x3400 && c <= 0x4DBF)
                   || (c >= 0x4E00 && c <= 0x9FFF)   // CJK 统一表意文字
                   || (c >= 0xA000 && c <= 0xA4CF)
                   || (c >= 0xAC00 && c <= 0xD7A3)   // 韩文音节
                   || (c >= 0xF900 && c <= 0xFAFF)
                   || (c >= 0xFE30 && c <= 0xFE6F)
                   || (c >= 0xFF00 && c <= 0xFF60)   // 全角字符
                   || (c >= 0xFFE0 && c <= 0xFFE6);
        }

        private static int Clamp(int v, int min, int max)
        {
            if (v < min) return min;
            return v > max ? max : v;
        }
    }
}
