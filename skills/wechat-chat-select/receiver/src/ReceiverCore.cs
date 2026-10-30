using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace AgentChatReceiver
{
    // The Staging -> Ready contract follows WeChatBridge's MIT-licensed design.
    // This implementation is standalone and does not load WeChatBridge binaries.
    internal sealed class Capture
    {
        internal const long DefaultLimit = 1073741824;
        private readonly string root;
        private readonly string stage;
        private readonly string batchId = Guid.NewGuid().ToString("D");
        private readonly long limit;
        private long total;
        private bool finished;
        private readonly List<object> items = new List<object>();
        internal readonly List<string> Warnings = new List<string>();
        internal readonly List<string> Formats = new List<string>();
        internal readonly List<string> UnhandledFormats = new List<string>();
        private readonly string source;

        internal Capture(string inbox, string sourceName, long maxBytes)
        {
            root = Path.GetFullPath(inbox);
            source = sourceName;
            limit = maxBytes;
            if (limit <= 0) throw new ArgumentException("The byte limit must be positive.");
            stage = Path.Combine(root, "Staging", batchId + ".staging");
            Directory.CreateDirectory(Path.Combine(stage, "files"));
        }

        internal static string DefaultInbox()
        {
            // AppData may be redirected by MSIX; agents need a shared physical path.
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".agent-chat-receiver", "Inbox");
        }

        internal async Task AddFileAsync(string path, string kind)
        {
            if (!File.Exists(path) || Directory.Exists(path)) throw new IOException("Shared item is not a file.");
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Reparse-point source files are not supported.");
            using (var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                await AddAsync(input, Path.GetFileName(path), "application/octet-stream", kind);
        }

        internal async Task AddTextAsync(string text, string name, string contentType, string kind)
        {
            using (var stream = new MemoryStream(new UTF8Encoding(false, true).GetBytes(text)))
                await AddAsync(stream, name, contentType, kind);
        }

        internal async Task AddAsync(Stream input, string displayName, string contentType, string kind)
        {
            if (finished) throw new InvalidOperationException("Capture is already finished.");
            if (items.Count >= 1024) throw new IOException("Too many shared items.");
            string fileName = (items.Count + 1).ToString("D4") + "_" + SafeName(displayName);
            string relative = "files/" + fileName;
            string destination = Path.Combine(stage, "files", fileName);
            long count = 0;
            string digest;
            using (var hash = SHA256.Create())
            using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                byte[] buffer = new byte[131072];
                int read;
                while ((read = await input.ReadAsync(buffer, 0, buffer.Length)) != 0)
                {
                    count = checked(count + read);
                    total = checked(total + read);
                    if (count > limit || total > limit) throw new IOException("Shared data exceeds the byte limit.");
                    await output.WriteAsync(buffer, 0, read);
                    hash.TransformBlock(buffer, 0, read, null, 0);
                }
                hash.TransformFinalBlock(new byte[0], 0, 0);
                digest = BitConverter.ToString(hash.Hash).Replace("-", "").ToLowerInvariant();
                output.Flush(true);
            }
            items.Add(new Dictionary<string, object> {
                {"id", Guid.NewGuid().ToString("D")}, {"relativePath", relative},
                {"displayName", displayName}, {"byteCount", count}, {"contentType", contentType},
                {"kind", kind}, {"sha256", digest}
            });
        }

        internal string Commit()
        {
            if (finished || items.Count == 0) throw new InvalidOperationException("No captured data to commit.");
            var manifest = new Dictionary<string, object> {
                {"schemaVersion", 1}, {"batchId", batchId},
                {"createdAt", DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")},
                {"action", "capture"}, {"source", source}, {"formats", Formats},
                {"items", items}, {"warnings", Warnings}, {"unhandledFormats", UnhandledFormats},
                {"partial", Warnings.Count > 0 || UnhandledFormats.Count > 0}
            };
            WriteJson(Path.Combine(stage, "manifest.json"), manifest);
            string ready = Path.Combine(root, "Ready", batchId);
            Directory.CreateDirectory(Path.GetDirectoryName(ready));
            Directory.Move(stage, ready);
            finished = true;
            return Path.Combine(ready, "manifest.json");
        }

        internal void Fail(Exception error)
        {
            if (finished) return;
            try
            {
                WriteJson(Path.Combine(stage, "error.json"), new {
                    source = source, batchId = batchId, error = error.Message,
                    createdAt = DateTime.UtcNow.ToString("o")
                });
                string failed = Path.Combine(root, "Failed", batchId);
                Directory.CreateDirectory(Path.GetDirectoryName(failed));
                Directory.Move(stage, failed);
                finished = true;
            }
            catch { /* Failure reporting must not hide the original error. */ }
        }

        internal static string SafeName(string name)
        {
            string leaf = Path.GetFileName(name ?? "");
            if (String.IsNullOrWhiteSpace(leaf)) leaf = "payload.bin";
            foreach (char c in Path.GetInvalidFileNameChars()) leaf = leaf.Replace(c, '_');
            var builder = new StringBuilder();
            foreach (char c in leaf) builder.Append(Char.IsControl(c) ? '_' : c);
            leaf = builder.ToString().Trim().TrimEnd('.', ' ');
            if (leaf.Length > 160) leaf = leaf.Substring(0, 140) + "_truncated";
            return String.IsNullOrEmpty(leaf) ? "payload.bin" : leaf;
        }

        internal static void WriteJson(string path, object value)
        {
            var json = new JavaScriptSerializer { MaxJsonLength = 16777216 };
            byte[] bytes = new UTF8Encoding(false).GetBytes(json.Serialize(value));
            using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                output.Write(bytes, 0, bytes.Length);
                output.Flush(true);
            }
        }
    }
}
