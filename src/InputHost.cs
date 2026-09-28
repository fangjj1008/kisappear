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
        /// 系统光标只能在"输入彻底停下来"之后才藏。上屏的字是 WM_IME_ENDCOMPOSITION 之后才一个个
        /// 以 WM_CHAR 进来的（实测微软拼音如此），在那之前藏会把 TSF 的锚点打断，
        /// 后果是后面的词全插到前面 —— 中文顺序错乱。所以每次输入事件都重开这个静置计时器。
        /// </summary>
        private readonly Timer _settle = new Timer();

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
            _settle.Interval = 400;
            _settle.Tick += (s, e) => { _settle.Stop(); HideSystemCaret(); };
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

        /// <summary>有输入事件就把"藏系统光标"往后推，直到输入彻底静置下来。</summary>
        private void ArmCaretHide()
        {
            _settle.Stop();
            _settle.Start();
        }

        private void HideSystemCaret()
        {
            if (IsComposing) return;
            if (!IsHandleCreated || !Focused) return;
            NativeMethods.HideCaret(Handle);
        }

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
                // 父窗口放完插入点后控件会造出系统光标；这里不能立刻藏，只重排静置计时
                ArmCaretHide();
                return;                   // 不让编辑控件自己响应点击，否则它会抢走父窗口的按钮/拖动
            }
            base.WndProc(ref m);
            switch (m.Msg)
            {
                case NativeMethods.WM_IME_STARTCOMPOSITION:
                    IsComposing = true;
                    ArmCaretHide();
                    TraceIme("start");
                    PositionCompositionWindow();
                    break;
                case NativeMethods.WM_IME_COMPOSITION:
                    long flags = m.LParam.ToInt64();
                    if ((flags & NativeMethods.GCS_COMPSTR) != 0) IsComposing = true;
                    if ((flags & NativeMethods.GCS_RESULTSTR) != 0) IsComposing = false;
                    ArmCaretHide();
                    TraceIme("comp 0x" + flags.ToString("X"));
                    PositionCompositionWindow();
                    break;
                case NativeMethods.WM_IME_ENDCOMPOSITION:
                    IsComposing = false;
                    ArmCaretHide();
                    TraceIme("end");
                    break;
                case NativeMethods.WM_CHAR:
                    ArmCaretHide();   // 上屏的字正是以 WM_CHAR 到达的，此刻最不能碰系统光标
                    TraceIme("char '" + ((char)m.WParam.ToInt32()) + "'" + (IsComposing ? " (composing)" : ""));
                    break;
                case NativeMethods.WM_KEYUP:
                    ArmCaretHide();
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
            HideSystemCaret();
        }

        protected override void OnTextChanged(EventArgs e)
        {
            base.OnTextChanged(e);
            ArmCaretHide();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _settle.Dispose();
                if (_buffer != null) { _buffer.Dispose(); _buffer = null; }
            }
            base.Dispose(disposing);
        }
    }
}
