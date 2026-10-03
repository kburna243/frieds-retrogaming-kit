# Writes a minimal Visual Pinball table for tests: an OLE compound file with the storage GameStg and the
# stream GameData that holds the given script text (Western code page, as VPX stores it). A real table holds
# far more records around the script; the audit reads the whole stream, so the script alone is enough.
param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [AllowEmptyString()] [string] $Script
)

if (-not ('RetroCabinetKit.Tests.VpxWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace RetroCabinetKit.Tests {
    [ComImport, Guid("0000000b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IWriteStorage {
        [PreserveSig] int CreateStream([MarshalAs(UnmanagedType.LPWStr)] string name, uint mode, uint r1, uint r2, out IStream stream);
        void OpenStream();
        [PreserveSig] int CreateStorage([MarshalAs(UnmanagedType.LPWStr)] string name, uint mode, uint r1, uint r2, out IWriteStorage storage);
        void OpenStorage();
        void CopyTo();
        void MoveElementTo();
        [PreserveSig] int Commit(uint flags);
    }

    public static class VpxWriter {
        // STGM_CREATE | STGM_READWRITE | STGM_SHARE_EXCLUSIVE
        const uint Create = 0x00001000 | 0x00000002 | 0x00000010;

        [DllImport("ole32.dll")]
        static extern int StgCreateDocfile([MarshalAs(UnmanagedType.LPWStr)] string name, uint mode, uint reserved, out IWriteStorage storage);

        public static void Write(string path, byte[] data) {
            IWriteStorage root, game; IStream stream;
            int hr = StgCreateDocfile(path, Create, 0, out root);
            if (hr != 0) throw new InvalidOperationException("create 0x" + hr.ToString("X8"));
            try {
                hr = root.CreateStorage("GameStg", Create, 0, 0, out game);
                if (hr != 0) throw new InvalidOperationException("GameStg 0x" + hr.ToString("X8"));
                try {
                    hr = game.CreateStream("GameData", Create, 0, 0, out stream);
                    if (hr != 0) throw new InvalidOperationException("GameData 0x" + hr.ToString("X8"));
                    try { stream.Write(data, data.Length, IntPtr.Zero); stream.Commit(0); }
                    finally { Marshal.ReleaseComObject(stream); }
                    game.Commit(0);
                } finally { Marshal.ReleaseComObject(game); }
                root.Commit(0);
            } finally { Marshal.ReleaseComObject(root); }
        }
    }
}
'@
}

$full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
$dir = Split-Path -Parent $full
if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
[RetroCabinetKit.Tests.VpxWriter]::Write($full, [Text.Encoding]::GetEncoding(1252).GetBytes($Script))
$full
