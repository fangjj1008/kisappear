using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

namespace Kisappear
{
    public sealed class EditorForm : Form
    {
        // 逻辑像素常量，运行时按设备 DPI 缩放
        private const int LogPad = 6;
        private const int LogCaretW = 2;
        private const int LogTail = 20;
        private const int LogBtn = 18;
        private const int LogGap = 4;
        private const int LogStatusW = 84;

        private static readonly Color ColBack = Color.FromArgb(24, 26, 31);
        private static readonly Color ColAccent = Color.FromArgb(96, 160, 255);
        private static readonly Color ColCaret = Color.FromArgb(232, 236, 244);
        private static readonly Color ColStatus = Color.FromArgb(150, 156, 168);
        private static readonly Color ColBtn = Color.FromArgb(44, 48, 58);
        private static readonly Color ColBtnHot = Color.FromArgb(74, 82, 98);

        private readonly InputHost _input = new InputHost();
        private readonly Timer _blink = new Timer();
        private readonly Timer _poll = new Timer();
        private readonly Font _editFont;
        private readonly Font _uiFont;

        private string _filePath;
        private bool _dirty;
        private bool _loading;

        private float _scale = 1f;
        private int _pad = LogPad;
        private int _caretW = LogCaretW;
        private int _tail = LogTail;
        private int _btn = LogBtn;
        private int _gap = LogGap;
        private int _statusW = LogStatusW;

        private int _charWidth = 7;
        private int _baseWidth = 34;
        private int _hoverWidth = 176;
        private int _scrollX;
        private int _caretX = LogPad;

        private bool _caretOn = true;
        private bool _hover;
        private int _hotButton;
        private bool _movingWindow;
        private bool _draggingSelect;
        private int _dragAnchor;
        private Point _lastMouseScreen;
        private bool _movedWhileRightDown;
        private bool _wasMinimized;
        private bool _placed;
        private bool _hasIcon;
        private ContextMenuStrip _menu;

        // 取色：点取色按钮 -> 屏幕任意一点按下再抬起 -> 把那个颜色换成窗口自身底色，
        // 光标按亮度自动反相，否则底色一变光标就糊在一起看不见
        private Color _panelColor = ColBack;
        private Color _caretColor = ColCaret;
        private bool _picking;
        private bool _pendingPick;
        private bool _pressMoved;
        private Point _pressScreen;

        private enum Hot { None = 0, Min = 1, Close = 2, Pick = 3 }

        public EditorForm()
        {
            Text = "消失の写字板";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = true;
            MinimizeBox = true;
            TopMost = true;
            BackColor = ColBack;
            KeyPreview = true;
            // 不给 Form 加 Selectable：焦点必须一直留在隐藏的输入宿主上，否则输入法挂不住
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            AutoScaleMode = AutoScaleMode.None;

            _editFont = new Font("Consolas", 11f, FontStyle.Regular, GraphicsUnit.Point);
            _uiFont = new Font("Segoe UI", 7.5f, FontStyle.Regular, GraphicsUnit.Point);
            _input.Font = _editFont;
            _input.PaintContent = RenderContent;
            _input.Trace = Trace;
            _input.TextChanged += (s, e) => { if (!_loading) MarkDirty(); OnTextOrCaretChanged(); };
            Controls.Add(_input);
            ApplyGeometry();

            _blink.Interval = 530;
            _blink.Tick += (s, e) => { _caretOn = !_caretOn; InvalidateCaret(); };
            _poll.Interval = 60;
            _poll.Tick += (s, e) => PollMouse();

            BuildMenu();
            TrySetIcon();
            Trace("ctor-end");
        }

        private string Content { get { return _input.Text; } }

        private int Caret { get { return _input.SelectionStart; } }

        private bool HasSelection { get { return _input.SelectionLength > 0; } }

        // ---------- 尺寸与 DPI ----------

        private void ComputeMetrics()
        {
            float scale = 1f;
            try
            {
                using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) scale = g.DpiX / 96f;
            }
            catch { }
            if (scale < 1f) scale = 1f;
            _scale = scale;
            _pad = Scale(LogPad, scale);
            _caretW = Math.Max(2, Scale(LogCaretW, scale));
            _tail = Scale(LogTail, scale);
            _btn = Math.Max(16, Scale(LogBtn, scale));
            _gap = Scale(LogGap, scale);
            _statusW = Scale(LogStatusW, scale);
        }

        private static int Scale(int logical, float scale) { return (int)Math.Round(logical * scale); }

        private int Radius() { return Math.Max(4, Scale(6, _scale)); }

        /// <summary>
        /// 尺寸必须在 handle 创建之后重申：CreateGraphics 会提前触发 OnHandleCreated，
        /// WinForms 随后用默认 ClientSize 覆盖构造期设置的值。
        /// </summary>
        private void ApplyGeometry()
        {
            ComputeMetrics();
            int lineH = Math.Max(20, Math.Max(Scale(22, _scale), _editFont.Height + _pad));
            _baseWidth = _pad * 2 + _caretW + _tail;
            _hoverWidth = _baseWidth + _gap + _statusW + 2 * _gap + 3 * _btn + _gap + _pad;
            ClientSize = new Size(_hover ? _hoverWidth : _baseWidth, lineH);
            if (IsHandleCreated) MeasureCharWidth();
            UpdateRegion();
        }

        private void MeasureCharWidth()
        {
            using (Graphics g = CreateGraphics())
            {
                SizeF m = g.MeasureString("M", _editFont, new PointF(0, 0), StringFormat.GenericTypographic);
                _charWidth = Math.Max(1, (int)Math.Round(m.Width));
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ApplyGeometry();
            Trace("handleCreated");
            if (!_blink.Enabled) _blink.Start();
            if (!_poll.Enabled) _poll.Start();
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            ApplyGeometry();
            PlaceAtStartupPoint();
            Trace("shown");
            _input.Focus();
            DumpImeDiag();
            ComputeViewport();
            DumpState();
            if (_testPick) BeginInvoke((MethodInvoker)StartPick);   // 没有真鼠标时也能验证钩子是否建立
        }

        private void PlaceAtStartupPoint()
        {
            if (_placed) return;
            _placed = true;
            var wa = Screen.FromControl(this).WorkingArea;
            Location = new Point(wa.Right - _baseWidth - 24, wa.Top + 80);
        }

        private string _imeDiag = "none";

        private void DumpImeDiag()
        {
            IntPtr host = _input.Handle;
            IntPtr hIMC = NativeMethods.ImmGetContext(host);
            if (hIMC == IntPtr.Zero) { _imeDiag = "nocontext"; return; }
            bool opened = NativeMethods.ImmSetOpenStatus(hIMC, true);
            bool conv = NativeMethods.ImmSetConversionStatus(hIMC, NativeMethods.IME_CMODE_NATIVE, NativeMethods.IME_MODE_STRING);
            bool now = NativeMethods.ImmGetOpenStatus(hIMC);
            NativeMethods.ImmReleaseContext(host, hIMC);
            _imeDiag = "ctx=1,set=" + (opened ? 1 : 0) + ",conv=" + (conv ? 1 : 0) + ",now=" + (now ? 1 : 0);
            DumpState();
        }

        // ---------- 视口与绘制 ----------

        private void ComputeViewport()
        {
            string t = Content;
            int caret = Caret;
            int col = LineMath.VisualColumn(t, caret);
            int caretPixel = col * _charWidth;
            int maxCaretX = Math.Max(0, _baseWidth - _pad - _caretW - _tail);
            _scrollX = Math.Max(0, caretPixel - maxCaretX);
            _caretX = _pad + caretPixel - _scrollX;
            _input.CompositionAnchor = new Point(_caretX, 2);   // 候选窗钉在画出来的光标处
        }

        private void OnTextOrCaretChanged()
        {
            _caretOn = true;
            _blink.Stop();
            _blink.Start();
            DumpState();
            Repaint();
        }

        private void MarkDirty()
        {
            if (_dirty) return;
            _dirty = true;
            Repaint();
        }

        private void InvalidateCaret()
        {
            Repaint(new Rectangle(_caretX - 2, 0, _caretW + 4, ClientSize.Height));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            RenderContent(e.Graphics, ClientSize.Width, ClientSize.Height);
        }

        /// <summary>画面由宿主控件的 WM_PAINT 回调到这里：它铺满客户区，我们整面盖上去。</summary>
        private void RenderContent(Graphics g, int w, int h)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(_panelColor);
            ComputeViewport();

            Color border = HasSelection ? ColAccent : _panelColor;   // 边框跟面板同色，取色后不会出现"底色变了边框还是黑的"
            using (GraphicsPath fill = RoundRect(new Rectangle(0, 0, w, h), Radius()))
            using (GraphicsPath edge = RoundRect(new Rectangle(0, 0, w - 1, h - 1), Radius()))
            using (var bg = new SolidBrush(_panelColor))
            using (var pen = new Pen(border, 1f))
            {
                pen.Alignment = PenAlignment.Inset;
                g.FillPath(bg, fill);
                g.DrawPath(pen, edge);
            }

            DrawCaret(g, h);
            if (_hover)
            {
                DrawStatus(g);
                DrawButtons(g);
            }
        }

        // 宿主铺满客户区，重绘必须打到它身上，Form.Invalidate 已经看不见效果了
        private void Repaint()
        {
            _input.Invalidate();
            base.Invalidate();
        }

        private void Repaint(Rectangle r)
        {
            _input.Invalidate(r);
            base.Invalidate(r);
        }

        private void DrawCaret(Graphics g, int h)
        {
            bool focused = _input.Focused;
            if (!HasSelection && !_caretOn && focused) return;
            Color c = focused ? _caretColor : Blend(_caretColor, _panelColor, 0.45f);
            if (HasSelection) c = ColAccent;
            using (var b = new SolidBrush(c))
                g.FillRectangle(b, _caretX, _pad, _caretW, h - _pad * 2);
        }

        private static Color Blend(Color a, Color b, float weightOfA)
        {
            return Color.FromArgb(
                (int)(a.R * weightOfA + b.R * (1 - weightOfA)),
                (int)(a.G * weightOfA + b.G * (1 - weightOfA)),
                (int)(a.B * weightOfA + b.B * (1 - weightOfA)));
        }

        private void DrawStatus(Graphics g)
        {
            Rectangle status = StatusRect();
            string label = _picking
                ? "取色 #" + Hex(_pickColor) + " 左键应用"
                : DisplayName() + (_dirty ? " *" : "") + "  L" + (LineMath.LineIndexOf(Content, Caret) + 1)
                  + ":" + (LineMath.VisualColumn(Content, Caret) + 1)
                  + (_panelColor.ToArgb() == ColBack.ToArgb() ? "" : "  #" + Hex(_panelColor));
            var flags = TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding;
            TextRenderer.DrawText(g, label, _uiFont, status, _picking ? ColAccent : ColStatus, flags);
        }

        private Rectangle StatusRect()
        {
            int minLeft = MinRect().X;
            return new Rectangle(_baseWidth + _gap / 2, 0, Math.Max(0, minLeft - _gap / 2 - (_baseWidth + _gap / 2)), ClientSize.Height);
        }

        private Rectangle CloseRect()
        {
            return new Rectangle(ClientSize.Width - _pad - _btn, (ClientSize.Height - _btn) / 2, _btn, _btn);
        }

        private Rectangle MinRect()
        {
            Rectangle c = CloseRect();
            return new Rectangle(c.X - _gap - _btn, c.Y, _btn, _btn);
        }

        private Rectangle PickRect()
        {
            Rectangle m = MinRect();
            return new Rectangle(m.X - _gap - _btn, m.Y, _btn, _btn);
        }

        private void DrawButtons(Graphics g)
        {
            DrawButtonFace(g, PickRect(), _hotButton == (int)Hot.Pick || _picking);
            DrawButtonFace(g, MinRect(), _hotButton == (int)Hot.Min);
            DrawButtonFace(g, CloseRect(), _hotButton == (int)Hot.Close);
            using (var pen = new Pen(ColCaret, 1.4f))
            {
                int inset = Math.Max(4, (int)(_btn * 0.28f));
                Rectangle mn = MinRect();
                int y = mn.Y + mn.Height / 2;
                pen.Color = _hotButton == (int)Hot.Min ? ColCaret : ColStatus;
                g.DrawLine(pen, mn.X + inset, y, mn.Right - inset, y);

                Rectangle cl = CloseRect();
                pen.Color = _hotButton == (int)Hot.Close ? ColCaret : ColStatus;
                int a = cl.X + inset, b = cl.Right - inset;
                int t = cl.Y + inset, bo = cl.Bottom - inset;
                g.DrawLine(pen, a, t, b, bo);
                g.DrawLine(pen, b, t, a, bo);

                DrawEyedropper(g);
            }
        }

        /// <summary>滴管：斜杆 + 尖头 + 顶部胶头，够小也能认出来。</summary>
        private void DrawEyedropper(Graphics g)
        {
            Rectangle r = PickRect();
            bool hot = _hotButton == (int)Hot.Pick || _picking;
            using (var pen = new Pen(hot ? ColCaret : ColStatus, Math.Max(1.4f, _btn * 0.09f)))
            {
                float x0 = r.X + r.Width * 0.30f, y0 = r.Bottom - r.Height * 0.30f;
                float x1 = r.X + r.Width * 0.62f, y1 = r.Y + r.Height * 0.42f;
                g.DrawLine(pen, x0, y0, x1, y1);
                using (var tip = new SolidBrush(pen.Color))
                {
                    float s = Math.Max(2f, r.Width * 0.16f);
                    g.FillRectangle(tip, x0 - s / 2, y0 - s / 2, s, s);
                    g.FillRectangle(tip, x1 - s * 0.8f, y1 - s * 1.1f, s * 1.6f, s * 1.6f);
                }
            }
        }

        private void DrawButtonFace(Graphics g, Rectangle r, bool hot)
        {
            using (GraphicsPath p = RoundRect(r, 4))
            using (var b = new SolidBrush(hot ? ColBtnHot : ColBtn))
                g.FillPath(b, p);
        }

        private static GraphicsPath RoundRect(Rectangle r, int radius)
        {
            var p = new GraphicsPath();
            int d = radius * 2;
            if (r.Width <= 0 || r.Height <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        private void UpdateRegion()
        {
            if (ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
            using (GraphicsPath p = RoundRect(new Rectangle(0, 0, ClientSize.Width, ClientSize.Height), Radius()))
            {
                Region region = new Region(p);
                Region old = Region;
                Region = region;
                if (old != null) old.Dispose();
            }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (WindowState != FormWindowState.Normal)
            {
                _wasMinimized = true;
            }
            else if (_wasMinimized)
            {
                _wasMinimized = false;
                SetClientWidth(_baseWidth);
                RestoreTopMost();
                ClampToScreen();
                Activate();
                _input.Focus();
            }
            UpdateRegion();
            Repaint();
        }

        /// <summary>
        /// FormBorderStyle.None 会让窗口不带 WS_MINIMIZEBOX/WS_SYSMENU，
        /// 任务栏按钮因此无法还原。无边框下加了这两位不会冒出标题栏。
        /// </summary>
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.Style |= unchecked((int)0x00020000); // WS_MINIMIZEBOX
                cp.Style |= unchecked((int)0x00080000); // WS_SYSMENU
                return cp;
            }
        }

        /// <summary>还原后 Windows 可能丢掉 topmost；WinForms 的 setter 会短路同值赋值，所以直接调 SetWindowPos。</summary>
        private void RestoreTopMost()
        {
            if (!TopMost) return;
            NativeMethods.SetWindowPos(Handle, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
                NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);
        }

        // ---------- hover 轮询 ----------

        /// <summary>
        /// 宿主编辑控件铺满客户区，WM_SETCURSOR 会先发给它并固定成 I Beam；
        /// 显式设过 Cursor 才能覆盖它，否则悬停按钮不会变手型、取色也不会变十字。
        /// </summary>
        private void SetUiCursor(Cursor c)
        {
            Cursor = c;
            _input.Cursor = c;
        }

        private void PollMouse()
        {
            if (WindowState != FormWindowState.Normal)
            {
                _hover = false;
                return;
            }
            if (_picking) { RefreshPickPreview(); return; }   // 取色期间冻结 hover 展开/收起，输入由全局钩子处理
            Point origin = PointToScreen(Point.Empty);
            var screenRect = new Rectangle(origin.X, origin.Y, Width, Height);
            bool over = screenRect.Contains(Cursor.Position);
            if (over != _hover)
            {
                _hover = over;
                SetClientWidth(over ? _hoverWidth : _baseWidth);
                if (!over) _hotButton = (int)Hot.None;
            }
            int hot = (int)Hot.None;
            if (_hover)
            {
                Point c = PointToClient(Cursor.Position);
                if (CloseRect().Contains(c)) hot = (int)Hot.Close;
                else if (MinRect().Contains(c)) hot = (int)Hot.Min;
                else if (PickRect().Contains(c)) hot = (int)Hot.Pick;
            }
            if (hot != _hotButton)
            {
                _hotButton = hot;
                SetUiCursor(hot == (int)Hot.None ? Cursors.IBeam : Cursors.Hand);
                Repaint();
            }
            // TextBox 不会为"选区/插入点变化"事件，只能轮询补一次状态转储
            if (Caret != _lastCaret || _input.SelectionLength != _lastSel)
            {
                _lastCaret = Caret;
                _lastSel = _input.SelectionLength;
                DumpState();
                Repaint();
            }
        }

        private int _lastCaret = -1;
        private int _lastSel = -1;

        private void SetClientWidth(int target)
        {
            int delta = target - ClientSize.Width;
            if (delta == 0) return;
            Trace("setWidth->" + target);
            var wa = Screen.FromControl(this).WorkingArea;
            if (delta > 0 && Bounds.Right + delta > wa.Right)
                Location = new Point(Location.X - delta, Location.Y);
            ClientSize = new Size(target, ClientSize.Height);
            UpdateRegion();
            Repaint();
        }

        // ---------- 鼠标：只负责放光标和窗口移动，编辑交给宿主 ----------

        /// <summary>取证用：鼠标消息到底有没有到达本窗口（宿主收到会转发过来）。</summary>
        private string _lastMouse = "none";

        private void NoteMouse(string kind, MouseEventArgs e)
        {
            _lastMouse = kind + "@" + e.X + "," + e.Y + "/" + e.Button;
            DumpState();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            NoteMouse("down", e);
            if (_picking)
            {
                if (e.Button == MouseButtons.Right) CancelPick();
                return;
            }
            if (e.Button == MouseButtons.Right)
            {
                _movingWindow = true;
                _movedWhileRightDown = false;
                _lastMouseScreen = Control.MousePosition;
                return;
            }
            if (e.Button != MouseButtons.Left) return;
            _pressMoved = false;
            _pressScreen = Control.MousePosition;
            // 左键拖动也要用这个基准，漏了会拿上次右键的旧坐标算位移，窗口一下跳出屏幕
            _lastMouseScreen = Control.MousePosition;

            Point c = e.Location;
            if (_hover && CloseRect().Contains(c)) { DoClose(); return; }
            if (_hover && MinRect().Contains(c)) { DoMinimize(); return; }
            if (_hover && PickRect().Contains(c)) { _pendingPick = true; return; }

            _draggingSelect = (ModifierKeys & Keys.Shift) != 0;
            if (_draggingSelect)
            {
                if (!_input.Focused) _input.Focus();
                _dragAnchor = Caret;
                ExtendSelectionTo(PosFromX(c.X));
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (_picking) return;
            if (_movingWindow)
            {
                if (e.Button != MouseButtons.Right) { _movingWindow = false; return; }
                DragWindowTo(Control.MousePosition);
                return;
            }
            if (e.Button != MouseButtons.Left) return;
            Point now = Control.MousePosition;
            if (!_pressMoved && Math.Abs(now.X - _pressScreen.X) > 2 || !_pressMoved && Math.Abs(now.Y - _pressScreen.Y) > 2)
                _pressMoved = true;
            if (!_pressMoved) return;
            // 左键拖动 = 移动窗口（窗口只有 34px，拖动比拖选更常用）；Shift+拖动 = 选段
            if (_draggingSelect) ExtendSelectionTo(PosFromX(e.X));
            else DragWindowTo(now);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            NoteMouse("up", e);
            _movingWindow = false;
            if (_pressMoved)
            {
                // 按钮这一下的抬起只负责"进入取色模式"，不能同时被当成选点，
                // 否则会立刻采到我们自己面板的深色，光标变深色=看不见，像是没生效
                if (_pendingPick) _pendingPick = false;
                ClampToScreen();
                _pressMoved = false;
                return;
            }
            if (_pendingPick) { _pendingPick = false; StartPick(); return; }
            if (_picking) return;
            if (e.Button != MouseButtons.Left) return;
            if (_draggingSelect) { _draggingSelect = false; return; }
            if (ClientRectangle.Contains(e.Location))
            {
                if (!_input.Focused) _input.Focus();
                int pos = PosFromX(e.X);
                _dragAnchor = pos;
                _input.SelectionStart = pos;
                _input.SelectionLength = 0;
                Trace("click-place x=" + e.X + " -> pos=" + pos + " len=" + Content.Length);
            }
        }

        private void ExtendSelectionTo(int pos)
        {
            int start = Math.Min(_dragAnchor, pos);
            _input.Select(start, Math.Abs(pos - _dragAnchor));
        }

        private void DragWindowTo(Point screenNow)
        {
            int dx = screenNow.X - _lastMouseScreen.X, dy = screenNow.Y - _lastMouseScreen.Y;
            if (dx == 0 && dy == 0) return;
            _lastMouseScreen = screenNow;
            Location = new Point(Location.X + dx, Location.Y + dy);
            if (_movingWindow) _movedWhileRightDown = true;
        }

        /// <summary>窗口整个跑到所有屏幕之外就再也拖不回来了，兜底拉回右上角。</summary>
        private void ClampToScreen()
        {
            Rectangle r = Bounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            foreach (Screen s in Screen.AllScreens)
            {
                var inter = Rectangle.Intersect(r, s.WorkingArea);
                if (inter.Width >= Math.Min(40, r.Width) && inter.Height >= Math.Min(12, r.Height)) return;
            }
            var wa = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(wa.Right - Width - 24, wa.Top + 80);
        }

        // ---------- 取色 ----------
        // 用全局鼠标低级钩子，而不是鼠标捕获或轮询：
        // 捕获在 WM_LBUTTONUP 里 SetCapture 会被系统随后的处理释放掉；轮询则有几十毫秒的判定延迟。
        // 钩子在我们自己的消息循环里回调，抬起那一刻立即生效。

        private NativeMethods.LowLevelMouseProc _pickProc;   // 字段持有，防止被 GC 回收掉原生回调
        private IntPtr _pickHook;
        private Point _pickLast;
        private bool _pickDirty;
        private Color _pickColor = ColCaret;

        private void StartPick()
        {
            _picking = true;
            _pickColor = ScreenColorAt(Cursor.Position);
            _pickLast = Cursor.Position;
            _pickDirty = false;
            SetUiCursor(Cursors.Cross);
            if (_pickProc == null) _pickProc = OnPickMouseEvent;
            if (_pickHook == IntPtr.Zero)
                _pickHook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _pickProc,
                    NativeMethods.GetModuleHandle(null), 0);
            DumpState();   // hook=0 就说明取色模式根本没建立，别把它误报成"点了没反应"
            Repaint();
        }

        private void StopPickHook()
        {
            if (_pickHook == IntPtr.Zero) return;
            NativeMethods.UnhookWindowsHookEx(_pickHook);
            _pickHook = IntPtr.Zero;
        }

        private IntPtr OnPickMouseEvent(int nCode, IntPtr wParam, IntPtr lParam)
        {
            // 低级钩子会阻塞全系统输入，回调里只记状态，读屏和重绘交给定时器；
            // 只有"点击应用"这一条留在钩子里，保证点下即变色。
            if (nCode >= 0 && _picking)
            {
                int msg = wParam.ToInt32();
                if (msg == NativeMethods.WM_LBUTTONUP) ApplyPickedColor(Cursor.Position);
                else if (msg == NativeMethods.WM_RBUTTONUP) CancelPick();
                else if (msg == NativeMethods.WM_MOUSEMOVE)
                {
                    Point p = Cursor.Position;
                    if (p != _pickLast) { _pickLast = p; _pickDirty = true; }
                }
            }
            return NativeMethods.CallNextHookEx(_pickHook, nCode, wParam, lParam);
        }

        /// <summary>由 hover 定时器驱动：把钩子记下的最新鼠标点采成预览色并重绘。</summary>
        private void RefreshPickPreview()
        {
            if (!_pickDirty) return;
            _pickDirty = false;
            _pickColor = ScreenColorAt(_pickLast);
            Repaint();
        }

        private void CancelPick()
        {
            if (!_picking) return;
            _picking = false;
            StopPickHook();
            SetUiCursor(Cursors.Arrow);
            Repaint();
        }

        private static Color ScreenColorAt(Point screenPos)
        {
            try
            {
                using (var bmp = new Bitmap(1, 1))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                        g.CopyFromScreen(screenPos.X, screenPos.Y, 0, 0, new Size(1, 1));
                    return bmp.GetPixel(0, 0);
                }
            }
            catch { return ColCaret; }
        }

        private void ApplyPickedColor(Point screenPos)
        {
            Color picked = ScreenColorAt(screenPos);
            _panelColor = picked;
            _caretColor = Luminance(picked) > 140
                ? Color.FromArgb(28, 30, 36)
                : Color.FromArgb(236, 240, 248);
            _input.BackColor = picked;          // 宿主铺满客户区，不同色会在画面上留一块补丁
            _picking = false;
            StopPickHook();
            SetUiCursor(Cursors.Arrow);
            DumpState();
            Repaint();
        }

        private static int Luminance(Color c) { return (c.R * 299 + c.G * 587 + c.B * 114) / 1000; }

        private static string Hex(Color c) { return c.R.ToString("X2") + c.G.ToString("X2") + c.B.ToString("X2"); }

        private void ResetColors()
        {
            _panelColor = ColBack;
            _caretColor = ColCaret;
            _input.BackColor = ColBack;
            Repaint();
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            string t = Content;
            int moved = e.Delta > 0 ? LineMath.UpColumn(t, Caret) : LineMath.DownColumn(t, Caret);
            if (moved >= 0)
            {
                _input.SelectionStart = moved;
                _input.SelectionLength = 0;
            }
        }

        private int PosFromX(int x)
        {
            ComputeViewport();
            string t = Content;
            int lineStart = LineMath.LineStart(t, Caret);
            int column = (x - _pad + _scrollX + _caretW / 2) / _charWidth;
            return LineMath.IndexFromColumn(t, lineStart, Math.Max(0, column));
        }

        // ---------- 键盘：只截自己要的全局动作，其余交给宿主 ----------

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            switch (keyData)
            {
                case Keys.Control | Keys.S: Save(); return true;
                case Keys.Control | Keys.Shift | Keys.S: SaveAs(); return true;
                case Keys.Control | Keys.O: Open(); return true;
                case Keys.Control | Keys.N: NewDoc(); return true;
                case Keys.Control | Keys.W: DoClose(); return true;
                case Keys.Escape: if (_picking) CancelPick(); else ClearSelection(); return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        private void ClearSelection()
        {
            if (_input.SelectionLength <= 0) return;
            _input.SelectionLength = 0;
            Repaint();
        }

        protected override void OnDeactivate(EventArgs e)
        {
            base.OnDeactivate(e);
            Repaint();
        }

        protected override void OnActivated(EventArgs e)
        {
            base.OnActivated(e);
            _caretOn = true;
            _input.Focus();
            Repaint();
        }

        // ---------- 文件 ----------

        private string DisplayName()
        {
            if (string.IsNullOrEmpty(_filePath)) return "未命名";
            return Path.GetFileNameWithoutExtension(_filePath);
        }

        private void SetTextPreservingUndo(string text)
        {
            _loading = true;
            _input.Text = text ?? string.Empty;
            _loading = false;
            _dirty = false;
            Repaint();
        }

        private string TextForDisk()
        {
            return Content.Replace("\r\n", "\n").Replace("\n", "\r\n");
        }

        private void NewDoc()
        {
            if (!ConfirmDiscard()) return;
            _filePath = null;
            SetTextPreservingUndo(string.Empty);
        }

        private void Open()
        {
            if (!ConfirmDiscard()) return;
            using (var dlg = new OpenFileDialog())
            {
                dlg.Filter = "文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*";
                dlg.Title = "打开文档";
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                try
                {
                    SetTextPreservingUndo(File.ReadAllText(dlg.FileName, Encoding.UTF8));
                    _filePath = dlg.FileName;
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "无法打开文件：" + ex.Message, "消失の写字板", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }

        public void TryLoadFile(string path)
        {
            try
            {
                if (!File.Exists(path)) return;
                SetTextPreservingUndo(File.ReadAllText(path, Encoding.UTF8));
                _filePath = path;
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "无法打开文件：" + ex.Message, "消失の写字板", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void Save()
        {
            if (string.IsNullOrEmpty(_filePath)) { SaveAs(); return; }
            WriteTo(_filePath);
        }

        private void SaveAs()
        {
            using (var dlg = new SaveFileDialog())
            {
                dlg.Filter = "文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*";
                dlg.Title = "保存文档";
                dlg.FileName = string.IsNullOrEmpty(_filePath) ? "未命名.txt" : Path.GetFileName(_filePath);
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                WriteTo(dlg.FileName);
            }
        }

        private void WriteTo(string path)
        {
            try
            {
                File.WriteAllText(path, TextForDisk(), new UTF8Encoding(false));
                _filePath = path;
                _dirty = false;
                Repaint();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "无法保存文件：" + ex.Message, "消失の写字板", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private bool ConfirmDiscard()
        {
            if (!_dirty) return true;
            var r = MessageBox.Show(this, "当前内容尚未保存，要保存吗？", "消失の写字板", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (r == DialogResult.Cancel) return false;
            if (r == DialogResult.Yes)
            {
                Save();
                return !_dirty;
            }
            _dirty = false;
            return true;
        }

        private void DoMinimize()
        {
            // 最小化状态下不能改 ClientSize：Windows 会把这个中间态记成"还原后的正常尺寸"，
            // 于是从任务栏点回来只剩一条竖线。收起宽度推迟到 OnResize 的还原分支。
            _hover = false;
            _hotButton = (int)Hot.None;
            WindowState = FormWindowState.Minimized;
        }

        private void DoClose()
        {
            if (!ConfirmDiscard()) return;
            Close();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing && !ConfirmDiscard()) { e.Cancel = true; return; }
            StopPickHook();
            _blink.Stop();
            _poll.Stop();
            base.OnFormClosing(e);
        }

        // ---------- 图标与菜单 ----------

        private void TrySetIcon()
        {
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Kisappear.AppIcon"))
                {
                    if (s == null) return;
                    using (var bmp = new Bitmap(s))
                    {
                        IntPtr hicon = bmp.GetHicon();
                        try
                        {
                            using (var tmp = Icon.FromHandle(hicon))
                                Icon = (Icon)tmp.Clone();
                        }
                        finally
                        {
                            NativeMethods.DestroyIcon(hicon);
                        }
                    }
                }
                _hasIcon = true;
            }
            catch { }
        }

        private void BuildMenu()
        {
            _menu = new ContextMenuStrip();
            Add("新建  Ctrl+N", (s, e) => NewDoc());
            Add("打开…  Ctrl+O", (s, e) => Open());
            Add("保存  Ctrl+S", (s, e) => Save());
            Add("另存为…  Ctrl+Shift+S", (s, e) => SaveAs());
            _menu.Items.Add(new ToolStripSeparator());
            Add("全选  Ctrl+A", (s, e) => { _input.SelectAll(); Repaint(); });
            Add("取消选区", (s, e) => ClearSelection());
            _menu.Items.Add(new ToolStripSeparator());
            Add("取色（改变光标颜色）", (s, e) => StartPick());
            Add("恢复默认配色", (s, e) => ResetColors());
            _menu.Items.Add(new ToolStripSeparator());
            var top = new ToolStripMenuItem("保持置顶") { Checked = true, CheckOnClick = true };
            top.CheckedChanged += (s, e) => TopMost = top.Checked;
            _menu.Items.Add(top);
            Add("最小化", (s, e) => DoMinimize());
            Add("退出", (s, e) => DoClose());
        }

        private void Add(string label, EventHandler handler)
        {
            var item = new ToolStripMenuItem(label);
            item.Click += handler;
            _menu.Items.Add(item);
        }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            if (e.Button == MouseButtons.Right && !_movedWhileRightDown)
                _menu.Show(Cursor.Position);
        }

        // ---------- 取证日志 ----------
        // 默认就开：中文顺序这类问题只有"用户实际敲的那一版"能作证，而靠启动时记得设环境变量
        // 已经连着丢过三次现场（用户直接双击 exe，日志全是空的）。KISAPPER_NOLOG=1 才关。

        private static readonly bool _noLog = Environment.GetEnvironmentVariable("KISAPPER_NOLOG") == "1";

        private static string LogPath(string envName, string defaultName)
        {
            string v = Environment.GetEnvironmentVariable(envName);
            if (!string.IsNullOrEmpty(v)) return v;
            if (_noLog) return null;
            // 带 pid：多个实例同时开着时，state/buffer 是整面覆写的，共名会互相盖掉，
            // 取证就会看到"trace 说 len=55、state 说 len=8"这种自相矛盾的现场
            return Path.Combine(Path.GetTempPath(),
                defaultName.Replace(".txt", "-") +
                System.Diagnostics.Process.GetCurrentProcess().Id + ".txt");
        }

        private readonly string _stateFile = LogPath("KISAPPER_STATE_FILE", "kisapper-state.txt");
        private readonly string _traceFile = LogPath("KISAPPER_TRACE_FILE", "kisapper-trace.txt");
        private readonly string _dumpFile = LogPath("KISAPPER_DUMP_FILE", "kisapper-buffer.txt");
        private readonly bool _testPick = Environment.GetEnvironmentVariable("KISAPPER_TEST_PICK") == "1";

        private void Trace(string what)
        {
            if (string.IsNullOrEmpty(_traceFile)) return;
            try
            {
                int dpi = 0;
                if (IsHandleCreated) { using (Graphics gg = CreateGraphics()) dpi = (int)gg.DpiX; }
                File.AppendAllText(_traceFile, what + " | client=" + ClientSize + " bounds=" + Bounds +
                                   " base=" + _baseWidth + " hover=" + _hoverWidth + " pad=" + _pad +
                                   " tail=" + _tail + " scale=" + _scale + " dpi=" + dpi + "\r\n");
            }
            catch { }
        }

        private void DumpState()
        {
            if (string.IsNullOrEmpty(_stateFile) && string.IsNullOrEmpty(_dumpFile)) return;
            try
            {
                string t = Content;
                string tail = "";
                int n = Math.Min(3, t.Length);
                for (int i = t.Length - n; i < t.Length; i++)
                    tail += (tail.Length > 0 ? "-" : "") + (int)t[i];

                // 完整 buffer 落盘：中文顺序错乱只能靠比对"打的字"和"存下的字"来定性
                if (!string.IsNullOrEmpty(_dumpFile))
                    File.WriteAllText(_dumpFile, t, new System.Text.UTF8Encoding(false));

                if (string.IsNullOrEmpty(_stateFile)) return;
                File.WriteAllText(_stateFile,
                    "len=" + t.Length +
                    " caret=" + Caret +
                    " sel=" + (HasSelection ? 1 : 0) +
                    " selLen=" + _input.SelectionLength +
                    " line=" + (LineMath.LineIndexOf(t, Caret) + 1) +
                    " col=" + (LineMath.VisualColumn(t, Caret) + 1) +
                    " caretX=" + _caretX +
                    " w=" + ClientSize.Width +
                    " tail=" + tail +
                    " icon=" + (_hasIcon ? 1 : 0) +
                    " imediag=" + _imeDiag +
                    " picking=" + (_picking ? 1 : 0) +
                    " hook=" + (_pickHook == IntPtr.Zero ? 0 : 1) +
                    " pickColor=" + _pickColor.R + "-" + _pickColor.G + "-" + _pickColor.B +
                    " caretColor=" + _caretColor.R + "-" + _caretColor.G + "-" + _caretColor.B +
                    " panelColor=" + _panelColor.R + "-" + _panelColor.G + "-" + _panelColor.B +
                    " hostFocused=" + (_input.Focused ? 1 : 0) +
                    " lastMouse=" + _lastMouse +
                    " ime=" + (NativeMethods.IsImeOpen(_input.Handle) ? 1 : 0));
            }
            catch { }
        }
    }
}
