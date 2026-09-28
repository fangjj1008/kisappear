using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Kisappear
{
    /// <summary>
    /// 输入宿主：一个正常尺寸、铺满客户区的编辑控件 —— 文本 buffer、焦点、输入法上下文、
    /// 系统光标和 TSF 组字锚点全部由它按"普通文本编辑器"的方式管理。
    ///
    /// 之前把它缩成 1×1 放在光标旁边：短文本没问题，长文本时控件内部会横向滚动，
    /// 系统光标矩形被裁到看不见，TSF 拿不到锚点就把后一个词插到前面 —— 表现为中文顺序错乱。
    ///
    /// 现在改为：它照常布局，但自己不做默认绘制，而是回调 EditorForm 把整个画面（面板、
    /// 我们画的光标、悬停时的小按钮）盖在它上面；鼠标消息收到后原样转给父窗口处理
    /// （本控件就在客户区 (0,0) 且铺满，坐标不需要换算）。用户看到的"光标"始终是画的，
    /// 控件的真实光标只用于取焦点。
    /// </summary>
    public sealed class InputHost : TextBox
    {
        private const int WM_PAINT = 0x000F;

        /// <summary>由 EditorForm 注入：把整个表面画到给定 Graphics 上。</summary>
        public Action<Graphics, int, int> PaintContent;

        /// <summary>由 EditorForm 注入：把输入法事件流记到 trace 文件（不设环境变量则完全不做事）。</summary>
        public Action<string> Trace;

        private Bitmap _buffer;

        /// <summary>
        /// 这里**不调用 HideCaret** —— 一次都不。实测（%TEMP%\kisapper-trace.txt）：
        /// 打完"…很高兴认识你"后插入点在 18，静置 400ms 让我们的计时器开火藏光标，
        /// 下一次组字开始时 `SelectionStart` 自己退回 12（上一批的锚点），句号就插进了中间。
        /// 也就是说只要藏，延后多久都会把 TSF 的锚点打回上一个提交点，表现为中文顺序错乱。
        /// 代价是系统光标本身可能可见；我们画的光标仍按视口规则钉在 20px 尾巴左侧。
        /// </summary>
        public InputHost()
        {
            Multiline = true;
            WordWrap = false;
            AcceptsReturn = true;
            AcceptsTab = true;
            BorderStyle = BorderStyle.None;
            ScrollBars = ScrollBars.None;
            HideSelection = true;
            TabStop = false;
            AutoSize = false;
            ShortcutsEnabled = true;
            ImeMode = ImeMode.On;
            Dock = DockStyle.Fill;
            BackColor = Color.FromArgb(24, 26, 31);
            ForeColor = BackColor;
        }

        /// <summary>
        /// 鼠标一律转给父窗口：本控件正好铺满客户区且位于 (0,0)，坐标可直接沿用。
        /// 编辑控件不该抢鼠标 —— 点哪儿是父窗口在决定"放光标 / 按按钮 / 拖窗口"。
        /// 注意 WS_EX_TRANSPARENT 对子窗口不做命中跳过，早先靠它把鼠标让给父窗口是错的。
        /// </summary>
        private static bool IsMouseMessage(int msg)
        {
            return msg == NativeMethods.WM_MOUSEMOVE
                || msg == NativeMethods.WM_LBUTTONDOWN || msg == NativeMethods.WM_LBUTTONUP
                || msg == NativeMethods.WM_LBUTTONDBLCLK
                || msg == NativeMethods.WM_RBUTTONDOWN || msg == NativeMethods.WM_RBUTTONUP
                || msg == NativeMethods.WM_RBUTTONDBLCLK
                || msg == NativeMethods.WM_MBUTTONDOWN || msg == NativeMethods.WM_MBUTTONUP
                || msg == NativeMethods.WM_MOUSEWHEEL;
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            NativeMethods.ImmAssociateContextEx(Handle, IntPtr.Zero,
                NativeMethods.IACE_DEFAULT | NativeMethods.IACE_CHILDREN);
        }

        /// <summary>
        /// 组字期间绝不能碰系统光标：HideCaret 会让 TSF 退回用控件起点当锚点，
        /// 结果每个新词都插到开头，表现为"中文顺序错乱"。
        /// </summary>
        public bool IsComposing { get; private set; }

        /// <summary>我们画的那条光标的位置（相对本控件），候选窗要钉在这里。</summary>
        public Point CompositionAnchor { get; set; }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_PAINT)
            {
                base.WndProc(ref m);      // 先让默认处理校验更新区域，避免重绘死循环
                PaintSurface();
                return;
            }
            if (IsMouseMessage(m.Msg))
            {
                IntPtr p = Parent.Handle;
                if (p != IntPtr.Zero) NativeMethods.SendMessage(p, m.Msg, m.WParam, m.LParam);
                // 不藏系统光标：见构造函数上的说明，藏一次就够把中文顺序打乱
                return;                   // 不让编辑控件自己响应点击，否则它会抢走父窗口的按钮/拖动
            }
            base.WndProc(ref m);
            switch (m.Msg)
            {
                case NativeMethods.WM_IME_STARTCOMPOSITION:
                    IsComposing = true;
                    TraceIme("start");
                    PositionCompositionWindow();
                    break;
                case NativeMethods.WM_IME_COMPOSITION:
                    long flags = m.LParam.ToInt64();
                    if ((flags & NativeMethods.GCS_COMPSTR) != 0) IsComposing = true;
                    if ((flags & NativeMethods.GCS_RESULTSTR) != 0) IsComposing = false;
                    TraceIme("comp 0x" + flags.ToString("X"));
                    PositionCompositionWindow();
                    break;
                case NativeMethods.WM_IME_ENDCOMPOSITION:
                    IsComposing = false;
                    TraceIme("end");
                    break;
                case NativeMethods.WM_CHAR:
                    TraceIme("char '" + ((char)m.WParam.ToInt32()) + "'" + (IsComposing ? " (composing)" : ""));
                    break;
            }
        }

        /// <summary>
        /// 中文顺序错乱的取证：每个输入法事件都记下面对上一次的插入点与长度，
        /// 看结果串到底落在哪个偏移上。没接 Trace 时完全不走这条路。
        /// </summary>
        private void TraceIme(string what)
        {
            Action<string> t = Trace;
            if (t == null) return;
            t("ime " + what + " | caret=" + SelectionStart + " selLen=" + SelectionLength +
              " len=" + Text.Length + " composing=" + (IsComposing ? 1 : 0));
        }

        private void PositionCompositionWindow()
        {
            var anchor = CompositionAnchor;
            if (anchor == Point.Empty || Parent == null) return;
            NativeMethods.SetImeCompositionWindow(Handle, Parent.PointToScreen(anchor));
        }

        /// <summary>双缓冲整面覆盖，避免先闪出编辑控件自己的文字再被盖住。</summary>
        private void PaintSurface()
        {
            var handler = PaintContent;
            if (handler == null) return;
            int w = ClientSize.Width, h = ClientSize.Height;
            if (w <= 0 || h <= 0) return;
            if (_buffer == null || _buffer.Width != w || _buffer.Height != h)
            {
                if (_buffer != null) _buffer.Dispose();
                _buffer = new Bitmap(w, h);
            }
            using (Graphics bg = Graphics.FromImage(_buffer))
            {
                bg.SmoothingMode = SmoothingMode.AntiAlias;
                handler(bg, w, h);
            }
            using (Graphics g = Graphics.FromHwnd(Handle))
                g.DrawImageUnscaled(_buffer, 0, 0);
        }

        public void InvalidateSurface()
        {
            Invalidate();
        }

        protected override void OnGotFocus(EventArgs e)
        {
            base.OnGotFocus(e);
        }

        protected override void OnTextChanged(EventArgs e)
        {
            base.OnTextChanged(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_buffer != null) { _buffer.Dispose(); _buffer = null; }
            }
            base.Dispose(disposing);
        }
    }
}
