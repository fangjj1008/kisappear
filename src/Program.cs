using System;
using System.Windows.Forms;

namespace Kisappear
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            NativeMethods.SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            var form = new EditorForm();
            if (args.Length > 0) form.TryLoadFile(args[0]);
            Application.Run(form);
            return 0;
        }
    }
}
