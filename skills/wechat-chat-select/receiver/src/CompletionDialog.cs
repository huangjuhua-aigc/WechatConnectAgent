using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace AgentChatReceiver
{
    internal static class CompletionDialog
    {
        internal static void Show(string manifestPath)
        {
            if (!File.Exists(manifestPath)) throw new FileNotFoundException("Receipt manifest was not found.", manifestPath);
            string directory = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(manifestPath)), "files");
            string[] files = Directory.GetFiles(directory);
            Exception failure = null;
            // Receiving stays on MTA; the short-lived notification owns its STA loop.
            var thread = new Thread(delegate()
            {
                try
                {
                    Application.EnableVisualStyles();
                    Application.SetCompatibleTextRenderingDefault(false);
                    using (var form = new ReceiptToast(directory, files)) Application.Run(form);
                }
                catch (Exception error) { failure = error; }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join();
            if (failure != null) throw new InvalidOperationException("Files were saved, but the completion window failed.", failure);
        }

        private static void OpenExplorer(Form owner, string directory, string[] files)
        {
            try
            {
                if (!Directory.Exists(directory)) throw new DirectoryNotFoundException("保存目录已被移动或删除。");
                string arguments = files.Length == 1 && File.Exists(files[0])
                    ? "/select,\"" + files[0] + "\"" : "\"" + directory + "\"";
                using (Process process = Process.Start(new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"),
                    Arguments = arguments, UseShellExecute = false
                })) { }
            }
            catch (Exception error)
            {
                if (!(error is Win32Exception) && !(error is IOException) && !(error is UnauthorizedAccessException)) throw;
                MessageBox.Show(owner, "无法打开目录，可稍后从收件箱查看。\r\n\r\n" + error.Message,
                    "聊天收件箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private static GraphicsPath Rounded(RectangleF rectangle, float radius)
        {
            var path = new GraphicsPath();
            float diameter = radius * 2;
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private sealed class ReceiptToast : Form
        {
            private const int LifetimeMilliseconds = 5000;
            private readonly Stopwatch elapsed = new Stopwatch();
            private readonly System.Windows.Forms.Timer timer;
            private readonly Label countdown;
            private readonly Panel progress;
            private int progressWidth;

            internal ReceiptToast(string directory, string[] files)
            {
                SuspendLayout();
                Text = "聊天收件箱";
                Font = new Font("Microsoft YaHei UI", 9F);
                AutoScaleDimensions = new SizeF(96F, 96F);
                AutoScaleMode = AutoScaleMode.Dpi;
                ClientSize = new Size(480, 276);
                FormBorderStyle = FormBorderStyle.None;
                StartPosition = FormStartPosition.Manual;
                ShowInTaskbar = true;
                TopMost = true;
                BackColor = Color.White;
                DoubleBuffered = true;

                var badge = new SuccessMark { Bounds = new Rectangle(24, 25, 42, 42) };
                var brand = new Label {
                    Text = "聊天收件箱", AutoSize = true, Location = new Point(80, 22),
                    ForeColor = Color.FromArgb(104, 116, 137)
                };
                var heading = new Label {
                    Text = "文件已保存", AutoSize = true, Location = new Point(78, 44),
                    Font = new Font(Font.FontFamily, 16F, FontStyle.Bold), ForeColor = Color.FromArgb(22, 34, 53)
                };
                countdown = new Label {
                    Text = "5 秒后关闭", Bounds = new Rectangle(345, 25, 110, 20),
                    TextAlign = ContentAlignment.MiddleRight, ForeColor = Color.FromArgb(126, 137, 154),
                    AccessibleName = "自动关闭倒计时"
                };
                var locationCard = new RoundedPanel {
                    Bounds = new Rectangle(24, 92, 432, 104), BackColor = Color.FromArgb(245, 247, 250)
                };
                locationCard.Controls.Add(new Label {
                    Text = files.Length + " 个文件 · 保存位置", AutoSize = true, Location = new Point(14, 10),
                    ForeColor = Color.FromArgb(104, 116, 137)
                });
                locationCard.Controls.Add(new TextBox {
                    Text = directory, ReadOnly = true, Multiline = true, WordWrap = true,
                    ScrollBars = ScrollBars.None, BorderStyle = BorderStyle.None,
                    Bounds = new Rectangle(14, 34, 404, 59), Font = new Font(Font.FontFamily, 9F),
                    ForeColor = Color.FromArgb(58, 72, 94), BackColor = locationCard.BackColor,
                    AccessibleName = "文件保存位置", TabStop = false
                });
                var open = new RoundedButton(true) {
                    Text = "打开Explorer", Bounds = new Rectangle(24, 214, 270, 38), TabIndex = 0
                };
                var dismiss = new RoundedButton(false) {
                    Text = "我知道了", Bounds = new Rectangle(306, 214, 150, 38), TabIndex = 1
                };
                open.Click += delegate { OpenExplorer(this, directory, files); };
                dismiss.Click += delegate { Close(); };
                var track = new Panel { Bounds = new Rectangle(24, 269, 432, 3), BackColor = Color.FromArgb(237, 242, 249) };
                progress = new Panel { Dock = DockStyle.Left, Width = 432, BackColor = Color.FromArgb(69, 128, 236) };
                track.Controls.Add(progress);
                Controls.AddRange(new Control[] { badge, brand, heading, countdown, locationCard, open, dismiss, track });
                AcceptButton = dismiss;
                CancelButton = dismiss;
                timer = new System.Windows.Forms.Timer { Interval = 50 };
                timer.Tick += delegate { UpdateCountdown(); };
                ResumeLayout(false);
                PerformLayout();
            }

            protected override bool ShowWithoutActivation { get { return true; } }

            protected override CreateParams CreateParams
            {
                get
                {
                    var value = base.CreateParams;
                    value.ClassStyle |= 0x00020000; // CS_DROPSHADOW, no permanent system setting.
                    return value;
                }
            }

            protected override void OnShown(EventArgs e)
            {
                base.OnShown(e);
                Rectangle area = Screen.FromPoint(Cursor.Position).WorkingArea;
                int margin = (int)Math.Round(20 * DeviceDpi / 96.0);
                Location = new Point(Math.Max(area.Left, area.Right - Width - margin), Math.Max(area.Top, area.Bottom - Height - margin));
                progressWidth = progress.Parent.ClientSize.Width;
                elapsed.Start();
                timer.Start();
            }

            private void UpdateCountdown()
            {
                long remaining = Math.Max(0, LifetimeMilliseconds - elapsed.ElapsedMilliseconds);
                if (remaining == 0) { timer.Stop(); Close(); return; }
                countdown.Text = ((int)Math.Ceiling(remaining / 1000.0)) + " 秒后关闭";
                progress.Width = Math.Max(1, (int)(progressWidth * remaining / LifetimeMilliseconds));
            }

            protected override void OnSizeChanged(EventArgs e)
            {
                base.OnSizeChanged(e);
                if (Width < 32 || Height < 32) return;
                using (var shape = Rounded(new RectangleF(0, 0, Width, Height), 16 * DeviceDpi / 96F))
                {
                    Region old = Region;
                    Region = new Region(shape);
                    if (old != null) old.Dispose();
                }
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (var border = new Pen(Color.FromArgb(225, 231, 239)))
                using (var shape = Rounded(new RectangleF(.5F, .5F, Width - 1, Height - 1), 16 * DeviceDpi / 96F))
                    e.Graphics.DrawPath(border, shape);
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing && timer != null) { timer.Stop(); timer.Dispose(); }
                base.Dispose(disposing);
            }
        }

        private sealed class RoundedPanel : Panel
        {
            protected override void OnSizeChanged(EventArgs e)
            {
                base.OnSizeChanged(e);
                if (Width < 24 || Height < 24) return;
                using (var shape = Rounded(new RectangleF(0, 0, Width, Height), 10 * DeviceDpi / 96F))
                {
                    Region old = Region;
                    Region = new Region(shape);
                    if (old != null) old.Dispose();
                }
            }
        }

        private sealed class SuccessMark : Control
        {
            internal SuccessMark() { DoubleBuffered = true; }
            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (var background = new SolidBrush(Color.FromArgb(231, 248, 239)))
                    e.Graphics.FillEllipse(background, 0, 0, Width - 1, Height - 1);
                using (var check = new Pen(Color.FromArgb(25, 156, 99), Width * .065F))
                {
                    check.StartCap = check.EndCap = LineCap.Round;
                    e.Graphics.DrawLines(check, new[] {
                        new PointF(Width * .28F, Height * .51F), new PointF(Width * .44F, Height * .66F),
                        new PointF(Width * .74F, Height * .34F)
                    });
                }
            }
        }

        private sealed class RoundedButton : Button
        {
            private readonly bool primary;
            private bool hover;
            internal RoundedButton(bool primaryAction)
            {
                primary = primaryAction;
                FlatStyle = FlatStyle.Flat;
                FlatAppearance.BorderSize = 0;
                Cursor = Cursors.Hand;
                SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            }
            protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
            protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
            protected override void OnPaint(PaintEventArgs e)
            {
                e.Graphics.Clear(Parent.BackColor);
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                Color background = primary ? (hover ? Color.FromArgb(33, 88, 195) : Color.FromArgb(44, 106, 226))
                    : (hover ? Color.FromArgb(229, 234, 242) : Color.FromArgb(241, 244, 248));
                using (var brush = new SolidBrush(background))
                using (var shape = Rounded(new RectangleF(0, 0, Width - 1, Height - 1), 9 * DeviceDpi / 96F))
                    e.Graphics.FillPath(brush, shape);
                TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle,
                    primary ? Color.White : Color.FromArgb(66, 80, 101),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -5, -5));
            }
        }
    }
}
