using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Windows.ApplicationModel;
using Windows.ApplicationModel.Activation;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.8")]

namespace AgentChatReceiver
{
    internal static class Program
    {
        [MTAThread]
        private static int Main(string[] args)
        {
            string result = Option(args, "--result");
            try
            {
                string manifest;
                if (args.Contains("--show-receipt"))
                {
                    CompletionDialog.Show(Option(args, "--show-receipt"));
                    return 0;
                }
                else if (args.Contains("--import"))
                    manifest = ImportAsync(args).GetAwaiter().GetResult();
                else if (args.Contains("--identity"))
                {
                    var id = Package.Current.Id;
                    if (result != null) Capture.WriteJson(result, new { ok = true, name = id.Name, family = id.FamilyName });
                    return id.Name == "AgentChat.Receiver" ? 0 : 2;
                }
                else
                    manifest = ReceiveAsync().GetAwaiter().GetResult();
                if (result != null) Capture.WriteJson(result, new { ok = true, manifest = manifest });
                if (!args.Contains("--import")) CompletionDialog.Show(manifest);
                return 0;
            }
            catch (Exception error)
            {
                if (result != null && !File.Exists(result))
                    Capture.WriteJson(result, new { ok = false, error = error.Message });
                else
                {
                    string logs = Path.Combine(Capture.DefaultInbox(), "Logs");
                    Directory.CreateDirectory(logs);
                    File.AppendAllText(Path.Combine(logs, "receiver.log"), DateTime.UtcNow.ToString("o") + " " + error + Environment.NewLine);
                }
                return 2;
            }
        }

        private static string Option(string[] args, string key)
        {
            int index = Array.IndexOf(args, key);
            if (index < 0) return null;
            if (index + 1 >= args.Length) throw new ArgumentException("Missing value for " + key);
            return args[index + 1];
        }

        private static async Task<string> ImportAsync(string[] args)
        {
            string path = Option(args, "--import");
            string text = File.ReadAllText(path);
            if (text.Length > 16777216) throw new IOException("Import description is too large.");
            var input = new JavaScriptSerializer { MaxJsonLength = 16777216 }.Deserialize<Dictionary<string, object>>(text);
            long maxBytes = Option(args, "--max-bytes") == null ? Capture.DefaultLimit : Int64.Parse(Option(args, "--max-bytes"));
            var capture = new Capture(Option(args, "--inbox") ?? Capture.DefaultInbox(), "explicit-local-import", maxBytes);
            try
            {
                if (input.ContainsKey("files"))
                {
                    capture.Formats.Add("StorageItems");
                    foreach (object file in (System.Collections.IEnumerable)input["files"])
                        await capture.AddFileAsync((string)file, "file");
                }
                foreach (var entry in new[] { "text", "uri", "html", "rtf" })
                {
                    if (!input.ContainsKey(entry)) continue;
                    capture.Formats.Add(entry);
                    await capture.AddTextAsync((string)input[entry], "shared." + (entry == "text" || entry == "uri" ? "txt" : entry),
                        entry == "html" ? "text/html" : entry == "rtf" ? "application/rtf" : "text/plain", entry);
                }
                return capture.Commit();
            }
            catch (Exception error) { capture.Fail(error); throw; }
        }

        private static async Task<string> ReceiveAsync()
        {
            var args = AppInstance.GetActivatedEventArgs() as IShareTargetActivatedEventArgs;
            if (args == null) throw new InvalidOperationException("This receiver must be launched by Windows Share; use --import for local files.");
            var operation = args.ShareOperation;
            operation.ReportStarted();
            var data = operation.Data;
            var capture = new Capture(Capture.DefaultInbox(), "windows.shareTarget", Capture.DefaultLimit);
            var handled = new HashSet<string>();
            try
            {
                capture.Formats.AddRange(data.AvailableFormats);
                if (data.Contains(StandardDataFormats.StorageItems))
                {
                    var files = await data.GetStorageItemsAsync();
                    foreach (var item in files)
                    {
                        var file = item as StorageFile;
                        if (file == null) throw new IOException("Shared folders are not supported; share files or a ZIP.");
                        using (var stream = await file.OpenStreamForReadAsync())
                            await capture.AddAsync(stream, file.Name, file.ContentType, "file");
                    }
                    handled.Add(StandardDataFormats.StorageItems);
                }
                if (data.Contains(StandardDataFormats.Text))
                {
                    await capture.AddTextAsync(await data.GetTextAsync(), "shared-text.txt", "text/plain", "text");
                    handled.Add(StandardDataFormats.Text);
                }
                if (data.Contains(StandardDataFormats.WebLink))
                {
                    await capture.AddTextAsync((await data.GetWebLinkAsync()).AbsoluteUri, "shared-link.txt", "text/uri-list", "uri");
                    handled.Add(StandardDataFormats.WebLink);
                }
                if (data.Contains(StandardDataFormats.ApplicationLink))
                {
                    await capture.AddTextAsync((await data.GetApplicationLinkAsync()).AbsoluteUri, "shared-app-link.txt", "text/uri-list", "uri");
                    handled.Add(StandardDataFormats.ApplicationLink);
                }
                if (data.Contains(StandardDataFormats.Html))
                {
                    await capture.AddTextAsync(await data.GetHtmlFormatAsync(), "shared-html.txt", "text/html", "html");
                    handled.Add(StandardDataFormats.Html);
                }
                if (data.Contains(StandardDataFormats.Rtf))
                {
                    await capture.AddTextAsync(await data.GetRtfAsync(), "shared.rtf", "application/rtf", "rtf");
                    handled.Add(StandardDataFormats.Rtf);
                }
                if (data.Contains(StandardDataFormats.Bitmap))
                {
                    var reference = await data.GetBitmapAsync();
                    using (var randomAccess = await reference.OpenReadAsync())
                    using (var stream = randomAccess.AsStreamForRead())
                        await capture.AddAsync(stream, "shared-bitmap" + ImageExtension(randomAccess.ContentType), randomAccess.ContentType, "bitmap");
                    handled.Add(StandardDataFormats.Bitmap);
                }
                foreach (string format in data.AvailableFormats)
                    if (!handled.Contains(format)) capture.UnhandledFormats.Add(format);
                operation.ReportDataRetrieved();
                string manifest = capture.Commit();
                operation.ReportCompleted();
                return manifest;
            }
            catch (Exception error)
            {
                capture.Fail(error);
                try { operation.ReportError(error.Message); } catch { }
                throw;
            }
        }

        private static string ImageExtension(string type)
        {
            switch (type)
            {
                case "image/png": return ".png";
                case "image/jpeg": return ".jpg";
                case "image/bmp": return ".bmp";
                case "image/gif": return ".gif";
                case "image/tiff": return ".tiff";
                default: return ".bin";
            }
        }
    }
}
