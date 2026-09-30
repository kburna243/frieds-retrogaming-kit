"""Output relay for Gunmote's ArcadeHook (TCP client on localhost:8000) -> Wiimote rumble + life LEDs.

Sources:
  * FFBBlaster (TeknoParrot, OutputsSystem=1, NetOutputsTCPPort=8002): TCP, we are its client.
  * MAME output window messages ("MAMEOutput" window): DemulShooter (WM_OutputsEnabled) and standalone MAME.
    DemulShooter's own TCP server also wants port 8000, so it is read via window messages instead.
Per line we
  * hold "<recoil> = 0" back until the pulse is HOLD_MS old (FFBBlaster ~16 ms, too short for the Wiimote motor),
  * emit "P<n>_Shot" (HOLD_MS pulse) when an ammo counter drops (Walking Dead: recoil only on reload),
  * turn a life value into "P<n>_Led1..4" (life bar on the Wiimote LEDs),
  * rename "mame_start" so Gunmote uses one shared INI per source (FFBBlaster / DemulShooter); MAME keeps its
    per-game INIs. The real name stays in the trace (touch recoil-stretch.trace to log every line).
Runs permanently (task "Gunmote Recoil Stretch"). Self-check: python recoil-stretch.py --selftest
"""
import asyncio
import re
import sys
import threading
import time
from pathlib import Path

LISTEN_PORT, UPSTREAM_PORT, HOLD_MS = 8000, 8002, 150
STRETCH = {"1pRecoil", "2pRecoil", "P1_CtmRecoil", "P2_CtmRecoil"}
HEALTH = {"P1_Health": "P1", "P2_Health": "P2", "P1_Life": "P1", "P2_Life": "P2"}
AMMO = {"Ammo1pA": "P1", "Ammo2pA": "P2", "P1_Ammo": "P1", "P2_Ammo": "P2"}
LINE = re.compile(rb"^\s*(.+?)\s*=\s*(-?\d+)\s*$")
MAME_START = re.compile(rb"^(\s*mame_start\s*=\s*)(.*?)(\s*)$", re.S)
SHARED_FFB, SHARED_DS = b"TeknoParrot FFB", b"DemulShooter"

TRACE_ON = Path(__file__).with_name("recoil-stretch.trace")
TRACE_LOG = Path(__file__).with_name("recoil-stretch-trace.log")
CLIENTS = set()          # connected Gunmote writers
WM_START = [None]        # last mame_start from the window-message source, replayed to late Gunmote connections


def trace(msg):
    if TRACE_ON.exists():
        with TRACE_LOG.open("ab") as f:
            f.write(time.strftime("%H:%M:%S").encode() + b" %.3f " % (time.monotonic() % 1000) + msg.strip() + b"\n")


def led_bar(player, value, eol, top=100):
    # Counters up to 4 lives map 1:1 (Rambo 3..1); anything with a larger maximum (percent, 5 lives, ...)
    # is scaled to 4 LEDs against the highest value seen since mame_start.
    lit = value if top <= 4 else -(-value * 4 // top)
    return b"".join(b"%s_Led%d = %d%s" % (player.encode(), k, int(k <= lit), eol) for k in range(1, 5))


class Relay:
    def __init__(self, sink, hold_ms, shared=None):
        self.sink, self.hold, self.shared = sink, hold_ms / 1000, shared
        self.loop = asyncio.get_running_loop()
        self.on_since, self.pending, self.ammo, self.shot_off, self.top = {}, {}, {}, {}, {}

    def feed(self, msg):
        trace(msg)
        eol = msg[len(msg.rstrip(b"\r\n")):] or b"\r"
        if s := MAME_START.match(msg):
            self.ammo.clear(); self.top.clear()
            if self.shared:
                msg = s.group(1) + self.shared + s.group(3)
        m = LINE.match(msg.strip())
        name = m and m.group(1).decode(errors="replace")
        if name in STRETCH:
            if m.group(2) != b"0":
                if t := self.pending.pop(name, None):
                    t.cancel()  # still rumbling from the last shot: stay on
                self.on_since[name] = time.monotonic()
            else:
                wait = self.hold - (time.monotonic() - self.on_since.get(name, 0))
                if wait > 0:
                    self.pending[name] = self.loop.call_later(wait, self.sink, msg)
                    return
        self.sink(msg)
        if name in AMMO:
            value, player = int(m.group(2)), AMMO[name]
            if value < self.ammo.get(name, -1):
                if t := self.shot_off.pop(player, None):
                    t.cancel()
                self.sink(b"%s_Shot = 1%s" % (player.encode(), eol))
                self.shot_off[player] = self.loop.call_later(self.hold, self.sink, b"%s_Shot = 0%s" % (player.encode(), eol))
            self.ammo[name] = value
        if name in HEALTH:
            value = int(m.group(2))
            self.top[name] = max(self.top.get(name, 0), value)
            self.sink(led_bar(HEALTH[name], value, eol, self.top[name]))

    def close(self):
        for t in (*self.pending.values(), *self.shot_off.values()):
            t.cancel()


def lines(buf):
    """Split complete CR/LF-terminated lines off buf -> (lines, rest)."""
    out = []
    while (i := min((p for p in (buf.find(b"\r"), buf.find(b"\n")) if p >= 0), default=-1)) >= 0:
        j = i + 1
        while j < len(buf) and buf[j:j + 1] in (b"\r", b"\n"):
            j += 1
        out.append(buf[:j]); buf = buf[j:]
    return out, buf


async def pump_up(reader, writer, relay):
    buf = b""
    while data := await reader.read(4096):
        done, buf = lines(buf + data)
        for msg in done:
            relay.feed(msg)
        await writer.drain()


async def until_eof(reader):
    while await reader.read(4096):
        pass


async def handle(c_reader, c_writer, upstream_port, hold_ms):
    """One Gunmote connection: stays open; FFBBlaster is (re)connected whenever a game is running."""
    CLIENTS.add(c_writer)
    if WM_START[0]:
        c_writer.write(WM_START[0])
    closed = asyncio.create_task(until_eof(c_reader))
    try:
        while not closed.done():
            try:
                u_reader, u_writer = await asyncio.open_connection("127.0.0.1", upstream_port)
            except OSError:
                await asyncio.wait([closed], timeout=1)
                continue
            relay = Relay(c_writer.write, hold_ms, SHARED_FFB)
            up = asyncio.create_task(pump_up(u_reader, c_writer, relay))
            await asyncio.wait([up, closed], return_when=asyncio.FIRST_COMPLETED)
            up.cancel(); relay.close(); u_writer.close()
    except (ConnectionError, OSError):
        pass
    finally:
        closed.cancel(); CLIENTS.discard(c_writer); c_writer.close()


def broadcast(data):
    for w in list(CLIENTS):
        w.write(data)


def wm_source(loop, feed):
    """MAME output protocol client (window messages). Runs in its own thread with a Win32 message loop."""
    import ctypes
    from ctypes import wintypes as W
    u32, k32 = ctypes.WinDLL("user32"), ctypes.WinDLL("kernel32")
    LRESULT = ctypes.c_ssize_t
    WNDPROC = ctypes.WINFUNCTYPE(LRESULT, W.HWND, W.UINT, W.WPARAM, W.LPARAM)
    u32.DefWindowProcW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]; u32.DefWindowProcW.restype = LRESULT
    u32.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
    u32.FindWindowW.argtypes = [W.LPCWSTR, W.LPCWSTR]; u32.FindWindowW.restype = W.HWND
    u32.CreateWindowExW.argtypes = [W.DWORD, W.LPCWSTR, W.LPCWSTR, W.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                    ctypes.c_int, W.HWND, W.HMENU, W.HINSTANCE, W.LPVOID]
    u32.CreateWindowExW.restype = W.HWND
    k32.OpenProcess.restype = W.HANDLE

    class WNDCLASSW(ctypes.Structure):
        _fields_ = [("style", W.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                    ("hInstance", W.HINSTANCE), ("hIcon", W.HICON), ("hCursor", W.HANDLE), ("hbrBackground", W.HBRUSH),
                    ("lpszMenuName", W.LPCWSTR), ("lpszClassName", W.LPCWSTR)]

    class COPYDATASTRUCT(ctypes.Structure):
        _fields_ = [("dwData", ctypes.c_size_t), ("cbData", W.DWORD), ("lpData", ctypes.c_void_p)]

    reg = {n: u32.RegisterWindowMessageW(n) for n in ("MAMEOutputStart", "MAMEOutputStop", "MAMEOutputUpdateState",
                                                      "MAMEOutputRegister", "MAMEOutputGetIDString")}
    st = {"server": None, "hwnd": None, "names": {}, "wait": {}, "shared": None}

    def emit(line):
        loop.call_soon_threadsafe(feed, line)

    def owner_exe(hwnd):
        pid = W.DWORD()
        u32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        h = k32.OpenProcess(0x1000, False, pid.value)  # PROCESS_QUERY_LIMITED_INFORMATION
        buf, n = ctypes.create_unicode_buffer(260), W.DWORD(260)
        ok = h and k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(n))
        if h:
            k32.CloseHandle(h)
        return buf.value.lower() if ok else ""

    def attach(server):
        st.update(server=server, names={}, wait={})
        st["shared"] = SHARED_DS if "demulshooter" in owner_exe(server) else None
        u32.PostMessageW(server, reg["MAMEOutputRegister"], st["hwnd"], 4711)
        u32.PostMessageW(server, reg["MAMEOutputGetIDString"], st["hwnd"], 0)  # id 0 = game name

    def wndproc(hwnd, msg, wp, lp):
        if msg == reg["MAMEOutputStart"]:
            attach(wp)
        elif msg == reg["MAMEOutputStop"]:
            if st["server"]:
                emit(b"mame_stop = 1\r")
            st["server"] = None
        elif msg == reg["MAMEOutputUpdateState"] and st["server"]:
            oid, value = wp, ctypes.c_int32(lp & 0xFFFFFFFF).value
            if oid in st["names"]:
                emit(b"%s = %d\r" % (st["names"][oid], value))
            else:
                if oid not in st["wait"]:
                    u32.PostMessageW(st["server"], reg["MAMEOutputGetIDString"], hwnd, oid)
                st["wait"][oid] = value
        elif msg == 0x004A:  # WM_COPYDATA: {UINT32 id; char name[]}
            cds = ctypes.cast(lp, ctypes.POINTER(COPYDATASTRUCT)).contents
            if cds.cbData >= 4 and cds.lpData:
                oid = ctypes.c_uint32.from_address(cds.lpData).value
                name = ctypes.string_at(cds.lpData + 4).strip()
                if oid == 0:
                    emit(b"mame_start = %s\r" % (st["shared"] or name))
                else:
                    st["names"][oid] = name
                    if oid in st["wait"]:
                        emit(b"%s = %d\r" % (name, st["wait"].pop(oid)))
            return 1
        elif msg == 0x0113 and not st["server"]:  # WM_TIMER: output server already running when we started?
            if server := u32.FindWindowW("MAMEOutput", None):
                attach(server)
        return u32.DefWindowProcW(hwnd, msg, wp, lp)

    proc = WNDPROC(wndproc)
    wc = WNDCLASSW(lpfnWndProc=proc, hInstance=k32.GetModuleHandleW(None), lpszClassName="RecoilStretchMameClient")
    u32.RegisterClassW(ctypes.byref(wc))
    st["hwnd"] = u32.CreateWindowExW(0, wc.lpszClassName, "recoil-stretch", 0x80000000, 0, 0, 0, 0, None, None,
                                     wc.hInstance, None)  # hidden top-level popup: receives the broadcast Start/Stop
    u32.SetTimer(st["hwnd"], 1, 2000, None)
    msg = W.MSG()
    while u32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
        u32.TranslateMessage(ctypes.byref(msg)); u32.DispatchMessageW(ctypes.byref(msg))


async def serve(listen_port=LISTEN_PORT, upstream_port=UPSTREAM_PORT, hold_ms=HOLD_MS):
    return await asyncio.start_server(lambda r, w: handle(r, w, upstream_port, hold_ms), "127.0.0.1", listen_port)


async def selftest():
    got = []

    async def fake_ffbblaster(r, w):
        for line in (b"mame_start = rambo\r", b"1pRecoil = 1\r", b"1pRecoil = 0\r", b"P1_Damage = 1\r", b"P1_Health = 2\r",
                     b"Ammo1pA = 8\r", b"Ammo1pA = 7\r"):
            w.write(line)
        await w.drain()
        await asyncio.sleep(0.4)
        w.close()

    up = await asyncio.start_server(fake_ffbblaster, "127.0.0.1", 18002)
    proxy = await serve(18000, 18002, 150)
    r, cw = await asyncio.open_connection("127.0.0.1", 18000)
    t0 = time.monotonic()
    while len(got) < 13:
        got.append((await r.readuntil(b"\r"), time.monotonic() - t0))
    cw.close(); up.close(); proxy.close()
    names = [g[0] for g in got]
    assert names[:11] == [b"mame_start = TeknoParrot FFB\r", b"1pRecoil = 1\r", b"P1_Damage = 1\r", b"P1_Health = 2\r",
                          b"P1_Led1 = 1\r", b"P1_Led2 = 1\r", b"P1_Led3 = 0\r", b"P1_Led4 = 0\r",
                          b"Ammo1pA = 8\r", b"Ammo1pA = 7\r", b"P1_Shot = 1\r"], names
    assert set(names[11:]) == {b"1pRecoil = 0\r", b"P1_Shot = 0\r"}, names
    assert min(got[11][1], got[12][1]) >= 0.14, got
    assert led_bar("P1", 100, b"\r").count(b"= 1") == 4 and led_bar("P1", 26, b"\r").count(b"= 1") == 2
    assert led_bar("P1", 25, b"\r").count(b"= 1") == 1 and led_bar("P1", 0, b"\r").count(b"= 1") == 0

    # DemulShooter path (window-message source feeds a broadcast Relay): shared INI name, CtmRecoil stretch, 5 lives.
    out = []
    ds = Relay(out.append, 150, SHARED_DS)
    for line in (b"mame_start = hotd2\r", b"P1_Life = 5\r", b"P1_CtmRecoil = 1\r", b"P1_CtmRecoil = 0\r", b"P1_Life = 3\r"):
        ds.feed(line)
    assert out[0] == b"mame_start = DemulShooter\r", out
    assert out[2] == b"P1_Led1 = 1\rP1_Led2 = 1\rP1_Led3 = 1\rP1_Led4 = 1\r", out   # 5 of 5 -> 4 LEDs
    assert b"P1_CtmRecoil = 0\r" not in out, out                                    # held back
    assert out[-1] == b"P1_Led1 = 1\rP1_Led2 = 1\rP1_Led3 = 1\rP1_Led4 = 0\r", out  # 3 of 5 -> 3 LEDs
    await asyncio.sleep(0.2)
    assert out[-1] == b"P1_CtmRecoil = 0\r", out
    ds.close()
    print("selftest ok: recoil off delayed %.0f ms, ammo drop -> P1_Shot, life bar scaled, DemulShooter shared INI + CtmRecoil"
          % (got[11][1] * 1000))


async def main():
    loop = asyncio.get_running_loop()
    wm = Relay(broadcast, HOLD_MS)

    def wm_feed(line):
        if MAME_START.match(line):
            WM_START[0] = line
        elif line.startswith(b"mame_stop"):
            WM_START[0] = None
        wm.feed(line)

    threading.Thread(target=wm_source, args=(loop, wm_feed), daemon=True).start()
    server = await serve()
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(selftest() if "--selftest" in sys.argv else main())
