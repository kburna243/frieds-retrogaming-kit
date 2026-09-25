# Sqlite: P/Invoke wrapper around %SystemRoot%\System32\winsqlite3.dll (shipped with Windows 10/11).
#
# Calling convention: winsqlite3.dll is Microsoft's own SQLite build and is compiled with
# SQLITE_APICALL = __stdcall (WINAPI), unlike the cdecl sqlite3.dll from sqlite.org. That is why
# SQLitePCLRaw ships a separate "winsqlite3" provider declaring CallingConvention.StdCall.
# On x64 only one calling convention exists, so the declaration only matters in 32-bit PowerShell;
# tests\core\Sqlite.Tests.ps1 runs a query in the 32-bit (SysWOW64) PowerShell to prove it.
#
# Only named parameters (@name, :name, $name) are supported; values bind as NULL, INTEGER
# (integral types, bool), REAL (floating types), BLOB (byte[]) or TEXT (everything else).

if (-not ('RetroCabinetKit.SqliteConnection' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace RetroCabinetKit
{
    internal static class WinSqlite
    {
        const string Dll = "winsqlite3.dll";
        const CallingConvention Cc = CallingConvention.StdCall;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr LoadLibraryW(string path);

        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_close_v2(IntPtr db);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern IntPtr sqlite3_errmsg(IntPtr db);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_busy_timeout(IntPtr db, int ms);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_total_changes(IntPtr db);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_prepare_v2(IntPtr db, IntPtr sql, int nByte, out IntPtr stmt, out IntPtr tail);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_step(IntPtr stmt);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_finalize(IntPtr stmt);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_parameter_count(IntPtr stmt);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern IntPtr sqlite3_bind_parameter_name(IntPtr stmt, int index);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_null(IntPtr stmt, int index);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_int64(IntPtr stmt, int index, long value);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_double(IntPtr stmt, int index, double value);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] value, int nByte, IntPtr destructor);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_blob(IntPtr stmt, int index, byte[] value, int nByte, IntPtr destructor);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_bind_zeroblob(IntPtr stmt, int index, int n);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_column_count(IntPtr stmt);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern IntPtr sqlite3_column_name(IntPtr stmt, int col);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_column_type(IntPtr stmt, int col);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern long sqlite3_column_int64(IntPtr stmt, int col);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern double sqlite3_column_double(IntPtr stmt, int col);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern IntPtr sqlite3_column_text(IntPtr stmt, int col);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern IntPtr sqlite3_column_blob(IntPtr stmt, int col);
        [DllImport(Dll, CallingConvention = Cc)] internal static extern int sqlite3_column_bytes(IntPtr stmt, int col);
    }

    public sealed class SqliteConnection : IDisposable
    {
        const int SQLITE_ROW = 100, SQLITE_DONE = 101;
        static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);
        IntPtr db;

        public string FilePath { get; private set; }
        public bool ReadOnly { get; private set; }

        static SqliteConnection()
        {
            // Load the system copy explicitly so no winsqlite3.dll next to powershell.exe wins.
            string full = System.IO.Path.Combine(Environment.SystemDirectory, "winsqlite3.dll");
            if (WinSqlite.LoadLibraryW(full) == IntPtr.Zero) throw new DllNotFoundException(full);
        }

        public SqliteConnection(string path, bool readOnly, bool create)
        {
            int flags = readOnly ? 0x1 : (0x2 | (create ? 0x4 : 0));
            IntPtr handle;
            int rc = WinSqlite.sqlite3_open_v2(Utf8Z(path), out handle, flags, IntPtr.Zero);
            if (rc != 0)
            {
                string msg = handle != IntPtr.Zero ? Str(WinSqlite.sqlite3_errmsg(handle)) : "";
                if (handle != IntPtr.Zero) WinSqlite.sqlite3_close_v2(handle);
                throw new InvalidOperationException("SQLite open failed (" + rc + "): " + msg + " [" + path + "]");
            }
            db = handle;
            FilePath = path;
            ReadOnly = readOnly;
            WinSqlite.sqlite3_busy_timeout(db, 5000);
        }

        public object[] Query(string sql, IDictionary parameters)
        {
            return Run(sql, parameters, true).ToArray();
        }

        public int Execute(string sql, IDictionary parameters)
        {
            int before = WinSqlite.sqlite3_total_changes(Handle);
            Run(sql, parameters, false);
            return WinSqlite.sqlite3_total_changes(Handle) - before;
        }

        public void Dispose()
        {
            if (db != IntPtr.Zero) { WinSqlite.sqlite3_close_v2(db); db = IntPtr.Zero; }
            GC.SuppressFinalize(this);
        }

        ~SqliteConnection() { if (db != IntPtr.Zero) WinSqlite.sqlite3_close_v2(db); }

        IntPtr Handle
        {
            get { if (db == IntPtr.Zero) throw new ObjectDisposedException("SqliteConnection"); return db; }
        }

        List<object> Run(string sql, IDictionary parameters, bool collect)
        {
            IntPtr h = Handle;
            var rows = new List<object>();
            byte[] bytes = Utf8Z(sql);
            GCHandle pin = GCHandle.Alloc(bytes, GCHandleType.Pinned);
            try
            {
                IntPtr p = pin.AddrOfPinnedObject();
                long end = p.ToInt64() + bytes.Length - 1;
                while (p.ToInt64() < end)
                {
                    IntPtr stmt, tail;
                    Check(WinSqlite.sqlite3_prepare_v2(h, p, (int)(end - p.ToInt64()), out stmt, out tail));
                    if (tail.ToInt64() <= p.ToInt64() && stmt == IntPtr.Zero) break;
                    p = tail;
                    if (stmt == IntPtr.Zero) continue; // only whitespace or comments left
                    try
                    {
                        Bind(stmt, parameters);
                        while (true)
                        {
                            int rc = WinSqlite.sqlite3_step(stmt);
                            if (rc == SQLITE_ROW) { if (collect) rows.Add(ReadRow(stmt)); continue; }
                            if (rc == SQLITE_DONE) break;
                            Check(rc);
                        }
                    }
                    finally { WinSqlite.sqlite3_finalize(stmt); }
                }
            }
            finally { pin.Free(); }
            return rows;
        }

        void Bind(IntPtr stmt, IDictionary parameters)
        {
            int n = WinSqlite.sqlite3_bind_parameter_count(stmt);
            for (int i = 1; i <= n; i++)
            {
                string name = Str(WinSqlite.sqlite3_bind_parameter_name(stmt, i));
                if (name == null) throw new ArgumentException("Positional '?' parameters are not supported, use @name.");
                string bare = name.Substring(1);
                object value;
                if (parameters != null && parameters.Contains(bare)) value = parameters[bare];
                else if (parameters != null && parameters.Contains(name)) value = parameters[name];
                else throw new ArgumentException("Missing SQL parameter " + name);
                Check(BindValue(stmt, i, value));
            }
        }

        static int BindValue(IntPtr stmt, int i, object v)
        {
            if (v == null || v is DBNull) return WinSqlite.sqlite3_bind_null(stmt, i);
            if (v is bool) return WinSqlite.sqlite3_bind_int64(stmt, i, (bool)v ? 1 : 0);
            if (v is sbyte || v is byte || v is short || v is ushort || v is int || v is uint || v is long || v is ulong)
                return WinSqlite.sqlite3_bind_int64(stmt, i, Convert.ToInt64(v, CultureInfo.InvariantCulture));
            if (v is float || v is double || v is decimal)
                return WinSqlite.sqlite3_bind_double(stmt, i, Convert.ToDouble(v, CultureInfo.InvariantCulture));
            byte[] blob = v as byte[];
            if (blob != null)
                return blob.Length == 0 ? WinSqlite.sqlite3_bind_zeroblob(stmt, i, 0)
                                        : WinSqlite.sqlite3_bind_blob(stmt, i, blob, blob.Length, SQLITE_TRANSIENT);
            // Terminated buffer: an empty string must bind as '' and never as NULL.
            byte[] text = Utf8Z(Convert.ToString(v, CultureInfo.InvariantCulture));
            return WinSqlite.sqlite3_bind_text(stmt, i, text, text.Length - 1, SQLITE_TRANSIENT);
        }

        static OrderedDictionary ReadRow(IntPtr stmt)
        {
            var row = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
            int cols = WinSqlite.sqlite3_column_count(stmt);
            for (int c = 0; c < cols; c++)
            {
                string name = Str(WinSqlite.sqlite3_column_name(stmt, c));
                object value = null;
                switch (WinSqlite.sqlite3_column_type(stmt, c))
                {
                    case 1: value = WinSqlite.sqlite3_column_int64(stmt, c); break;
                    case 2: value = WinSqlite.sqlite3_column_double(stmt, c); break;
                    case 3:
                        IntPtr t = WinSqlite.sqlite3_column_text(stmt, c);
                        value = Utf8(t, WinSqlite.sqlite3_column_bytes(stmt, c));
                        break;
                    case 4:
                        IntPtr b = WinSqlite.sqlite3_column_blob(stmt, c);
                        byte[] data = new byte[WinSqlite.sqlite3_column_bytes(stmt, c)];
                        if (data.Length > 0) Marshal.Copy(b, data, 0, data.Length);
                        value = data;
                        break;
                }
                row[name] = value;
            }
            return row;
        }

        void Check(int rc)
        {
            if (rc == 0 || rc == SQLITE_ROW || rc == SQLITE_DONE) return;
            throw new InvalidOperationException("SQLite error " + rc + ": " + Str(WinSqlite.sqlite3_errmsg(db)));
        }

        static byte[] Utf8Z(string s)
        {
            byte[] raw = Encoding.UTF8.GetBytes(s ?? "");
            byte[] z = new byte[raw.Length + 1];
            Buffer.BlockCopy(raw, 0, z, 0, raw.Length);
            return z;
        }

        static string Str(IntPtr p)
        {
            if (p == IntPtr.Zero) return null;
            int len = 0;
            while (Marshal.ReadByte(p, len) != 0) len++;
            return Utf8(p, len);
        }

        static string Utf8(IntPtr p, int len)
        {
            if (p == IntPtr.Zero || len == 0) return string.Empty;
            byte[] b = new byte[len];
            Marshal.Copy(p, b, 0, len);
            return Encoding.UTF8.GetString(b);
        }
    }
}
'@
}

function ConvertTo-SqlParameterTable($Parameters) {
    if (-not $Parameters) { return $null }
    $table = @{}
    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($null -ne $value) { $value = $value.PSObject.BaseObject }
        $table[[string]$key] = $value
    }
    $table
}

function Open-KitSqlite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $ReadOnly,
        [switch] $Create
    )
    New-Object RetroCabinetKit.SqliteConnection ((Resolve-FullPath $Path), [bool]$ReadOnly, [bool]$Create)
}

function Close-KitSqlite {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection)
    $Connection.Dispose()
}

function Invoke-KitSqlQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection,
        [Parameter(Mandatory)] [string] $Sql,
        [System.Collections.IDictionary] $Parameters
    )
    foreach ($row in $Connection.Query($Sql, (ConvertTo-SqlParameterTable $Parameters))) { [pscustomobject]$row }
}

function Invoke-KitSqlNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection,
        [Parameter(Mandatory)] [string] $Sql,
        [System.Collections.IDictionary] $Parameters
    )
    $Connection.Execute($Sql, (ConvertTo-SqlParameterTable $Parameters))
}

# Runs $ScriptBlock (receives the connection) inside BEGIN IMMEDIATE ... COMMIT; any error rolls back
# and is rethrown. With -Rollback the transaction is always rolled back (dry run).
function Invoke-KitSqlTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock,
        [switch] $Rollback
    )
    $null = $Connection.Execute('BEGIN IMMEDIATE', $null)
    try {
        $result = & $ScriptBlock $Connection
    } catch {
        $null = $Connection.Execute('ROLLBACK', $null)
        throw
    }
    $null = $Connection.Execute($(if ($Rollback) { 'ROLLBACK' } else { 'COMMIT' }), $null)
    $result
}

function Get-KitSqlTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection)
    Invoke-KitSqlQuery -Connection $Connection -Sql "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name" |
        ForEach-Object { $_.name }
}

function Get-KitSqlColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection,
        [Parameter(Mandatory)] [string] $Table
    )
    $quoted = '"' + $Table.Replace('"', '""') + '"'
    Invoke-KitSqlQuery -Connection $Connection -Sql "PRAGMA table_info($quoted)" |
        ForEach-Object { [pscustomobject]@{ Name = $_.name; Type = $_.type; PrimaryKey = [bool]$_.pk } }
}

# Copy -> change the copy inside one transaction -> PRAGMA integrity_check -> atomic swap.
# The original is kept as <name>.bak_<purpose>_<yyyyMMdd-HHmmss>. On any error the original is
# untouched and the working copy is removed. -WhatIf runs the change on the copy and rolls it back,
# so the returned Result (whatever the script block returns, e.g. counts) is a real dry run.
function Update-KitDatabaseSafely {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9-]+$')] [string] $Purpose,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock
    )
    $full = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Database not found: $full" }
    $wal = Get-Item -LiteralPath "$full-wal" -Force -ErrorAction SilentlyContinue
    if ($wal -and $wal.Length -gt 0) { throw (Get-KitText 'Db.PendingWal' -f $full) }

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $work   = "$full.work_$stamp"
    $backup = "$full.bak_${Purpose}_$stamp"
    $apply  = $PSCmdlet.ShouldProcess($full, "Update database ($Purpose)")
    $before = Get-Item -LiteralPath $full

    $connection = $null
    try {
        Copy-Item -LiteralPath $full -Destination $work -WhatIf:$false
        $connection = Open-KitSqlite -Path $work
        $result = Invoke-KitSqlTransaction -Connection $connection -ScriptBlock $ScriptBlock -Rollback:(-not $apply)
        $check  = @(Invoke-KitSqlQuery -Connection $connection -Sql 'PRAGMA integrity_check')
        $verdict = ($check | ForEach-Object { $_.integrity_check }) -join '; '
        if ($verdict -ne 'ok') { throw (Get-KitText 'Db.IntegrityFailed' -f $verdict) }
        Close-KitSqlite $connection; $connection = $null

        if (-not $apply) {
            Remove-Item -LiteralPath $work -Force -WhatIf:$false
            return [pscustomobject]@{ Path = $full; Backup = $null; WhatIf = $true; Result = $result }
        }
        $now = Get-Item -LiteralPath $full
        if ($now.Length -ne $before.Length -or $now.LastWriteTimeUtc -ne $before.LastWriteTimeUtc) {
            throw (Get-KitText 'Db.ChangedMeanwhile' -f $full)
        }
        [IO.File]::Replace($work, $full, $backup)
        Write-KitLog (Get-KitText 'Db.Updated' -f $full, $backup)
        [pscustomobject]@{ Path = $full; Backup = $backup; WhatIf = $false; Result = $result }
    } catch {
        if ($connection) { Close-KitSqlite $connection }
        foreach ($leftover in $work, "$work-journal", "$work-wal", "$work-shm") {
            if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Force -WhatIf:$false }
        }
        throw
    }
}
