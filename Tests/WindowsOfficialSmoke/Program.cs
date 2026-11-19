using System.Runtime.InteropServices;
using UURemoteClone;

if (args.Length != 2) throw new ArgumentException("Expected bridge directory and official DLL path");
NativeLibrary.SetDllImportResolver(typeof(OfficialStreamer).Assembly, (name, _, _) =>
    name == "gvpb" ? NativeLibrary.Load(Path.GetFullPath(Path.Combine(args[0], "gvpb.dll"))) : IntPtr.Zero);
foreach (var role in new[] { OfficialStreamer.Role.Controller, OfficialStreamer.Role.Controlled })
{
    using var streamer = new OfficialStreamer(args[1], role);
    var version = streamer.Version;
    if (version != "V4.14.2") throw new Exception($"Unexpected native version: {version}");
    Console.WriteLine($"PASS managed P/Invoke: {role} {version}");
}
try
{
    using var invalid = new OfficialStreamer(args[1], (OfficialStreamer.Role)99);
    throw new Exception("Invalid role accepted");
}
catch (InvalidOperationException error) when (error.Message.Contains("Invalid library path or role")) {}
