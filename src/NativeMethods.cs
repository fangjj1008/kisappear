using System;
using System.Runtime.InteropServices;
using System.Drawing;

namespace Kisappear
{
    internal static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr hIcon);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const uint SWP_NOMOVE = 0x0002, SWP_NOSIZE = 0x0001, SWP_NOACTIVATE = 0x0010;

        [DllImport("imm32.dll")]
        public static extern IntPtr ImmGetContext(IntPtr hWnd);

        [DllImport("imm32.dll")]
        public static extern bool ImmReleaseContext(IntPtr hWnd, IntPtr hIMC);

        [DllImport("imm32.dll")]
        public static extern bool ImmSetCompositionWindow(IntPtr hIMC, ref COMPOSITIONFORM lpCompForm);

        [DllImport("imm32.dll")]
        public static extern bool ImmGetOpenStatus(IntPtr hIMC);

        [DllImport("imm32.dll")]
        public static extern bool ImmSetOpenStatus(IntPtr hIMC, bool open);

        [DllImport("imm32.dll")]
        public static extern bool ImmSetConversionStatus(IntPtr hIMC, int conversion, int sentence);

        [DllImport("imm32.dll")]
        public static extern IntPtr ImmAssociateContextEx(IntPtr hWnd, IntPtr hIMC, uint flags);

        public const uint IACE_CHILDREN = 0x0001, IACE_DEFAULT = 0x0002, IACE_IGNORENOCONTEXT = 0x0004;

        public const int WM_CHAR = 0x0102;
        public const int WM_KEYUP = 0x0101;
        public const int WM_MOUSEMOVE = 0x0200;
        public const int WM_LBUTTONDOWN = 0x0201;
        public const int WM_LBUTTONUP = 0x0202;
        public const int WM_LBUTTONDBLCLK = 0x0203;
        public const int WM_RBUTTONDOWN = 0x0204;
        public const int WM_RBUTTONUP = 0x0205;
        public const int WM_RBUTTONDBLCLK = 0x0206;
        public const int WM_MBUTTONDOWN = 0x0207;
        public const int WM_MBUTTONUP = 0x0208;
        public const int WM_MOUSEWHEEL = 0x020A;
        public const int WM_IME_STARTCOMPOSITION = 0x010D;
        public const int WM_IME_ENDCOMPOSITION = 0x010E;
        public const int WM_IME_COMPOSITION = 0x010F;
        public const long GCS_COMPSTR = 0x0008;
        public const long GCS_RESULTSTR = 0x0800;

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

        public delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        public const int WH_MOUSE_LL = 14;

        public const int IME_CMODE_NATIVE = 0x0001;
        public const int IME_MODE_STRING = 0x0001;

        [StructLayout(LayoutKind.Sequential)]
        public struct POINTAPI
        {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct COMPOSITIONFORM
        {
            public int dwStyle;
            public POINTAPI ptPosition;
            public int rcLeft;
            public int rcTop;
            public int rcRight;
            public int rcBottom;
            public int dwWindowAlignment;
            public int dwWordAlignment;
        }

        public const int CFS_POINT = 0x0002;

        /// <summary>把候选窗钉到光标处，否则 IME 会跑到屏幕左上角。</summary>
        public static void SetImeCompositionWindow(IntPtr handle, Point caretScreenPos)
        {
            IntPtr hIMC = ImmGetContext(handle);
            if (hIMC == IntPtr.Zero) return;
            try
            {
                var cf = new COMPOSITIONFORM
                {
                    dwStyle = CFS_POINT,
                    ptPosition = new POINTAPI { x = caretScreenPos.X, y = caretScreenPos.Y }
                };
                ImmSetCompositionWindow(hIMC, ref cf);
            }
            finally
            {
                ImmReleaseContext(handle, hIMC);
            }
        }

        public static bool IsImeOpen(IntPtr handle)
        {
            if (handle == IntPtr.Zero) return false;
            IntPtr hIMC = ImmGetContext(handle);
            if (hIMC == IntPtr.Zero) return false;
            try { return ImmGetOpenStatus(hIMC); }
            finally { ImmReleaseContext(handle, hIMC); }
        }
    }
}
