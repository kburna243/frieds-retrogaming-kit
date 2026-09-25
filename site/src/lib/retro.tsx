import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useI18n } from "../i18n";
import { setSoundEnabled } from "../utils/retroAudio";

// localStorage can throw (private mode, blocked storage) — never let that break the page.
export function store(key: string, value?: string): string | null {
  try {
    if (value === undefined) return localStorage.getItem(key);
    localStorage.setItem(key, value);
  } catch {
    /* ignore */
  }
  return null;
}

/* ------------------------------------------------ sound engine */
let audioCtx: AudioContext | null = null;
function ac(): AudioContext {
  if (!audioCtx) {
    const AC =
      window.AudioContext ||
      (window as unknown as { webkitAudioContext: typeof AudioContext })
        .webkitAudioContext;
    audioCtx = new AC();
  }
  return audioCtx;
}

function tone(
  freq: number,
  start: number,
  dur: number,
  type: OscillatorType = "square",
  vol = 0.045
) {
  const c = ac();
  const t0 = c.currentTime + start;
  const osc = c.createOscillator();
  const gain = c.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  gain.gain.setValueAtTime(0.0001, t0);
  gain.gain.exponentialRampToValueAtTime(vol, t0 + 0.008);
  gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  osc.connect(gain).connect(c.destination);
  osc.start(t0);
  osc.stop(t0 + dur + 0.02);
}

export type Sfx = "coin" | "blip" | "select" | "error" | "power" | "type" | "start";

function playSfx(s: Sfx) {
  try {
    const c = ac();
    if (c.state === "suspended") void c.resume();
    switch (s) {
      case "coin":
        tone(988, 0, 0.09, "square", 0.05);
        tone(1319, 0.08, 0.22, "square", 0.05);
        break;
      case "blip":
        tone(660, 0, 0.05, "square", 0.035);
        break;
      case "select":
        tone(523, 0, 0.05, "square", 0.04);
        tone(784, 0.05, 0.07, "square", 0.04);
        break;
      case "error":
        tone(160, 0, 0.16, "sawtooth", 0.05);
        tone(120, 0.1, 0.2, "sawtooth", 0.05);
        break;
      case "type":
        tone(1400 + Math.random() * 500, 0, 0.018, "square", 0.014);
        break;
      case "start":
        [523, 659, 784, 1047].forEach((f, i) => tone(f, i * 0.07, 0.1, "square", 0.045));
        break;
      case "power":
        [392, 523, 659, 784, 1047, 1319].forEach((f, i) =>
          tone(f, i * 0.055, 0.12, "triangle", 0.055)
        );
        break;
    }
  } catch {
    /* audio not available – silence is also retro */
  }
}

/* ------------------------------------------------ context */
type RetroCtx = {
  sfxOn: boolean;
  toggleSfx: () => void;
  play: (s: Sfx) => void;
  crtOn: boolean;
  toggleCrt: () => void;
  credits: number;
  addCoins: (n: number) => void;
  toast: string | null;
  showToast: (msg: string) => void;
  konami: boolean;
};

const Ctx = createContext<RetroCtx | null>(null);

export function useRetro(): RetroCtx {
  const v = useContext(Ctx);
  if (!v) throw new Error("useRetro outside provider");
  return v;
}

const KONAMI = [
  "ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown",
  "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight",
  "b", "a",
];

export function RetroProvider({ children }: { children: ReactNode }) {
  const [sfxOn, setSfxOn] = useState(true);
  const [crtOn, setCrtOn] = useState(true);
  const [credits, setCredits] = useState(0);
  const [toast, setToast] = useState<string | null>(null);
  const [konami, setKonami] = useState(false);
  const toastTimer = useRef<number | null>(null);
  const konamiIdx = useRef(0);

  const { t } = useI18n();
  const konamiMsg = useRef(t.konami);
  konamiMsg.current = t.konami;

  useEffect(() => {
    const s = store("fried-sfx");
    if (s !== null) setSfxOn(s === "1");
    const c = store("fried-crt");
    if (c !== null) setCrtOn(c === "1");
  }, []);

  // keep the mascot's own sound helper in sync with the global toggle
  useEffect(() => setSoundEnabled(sfxOn), [sfxOn]);

  const play = useCallback(
    (s: Sfx) => {
      if (sfxOn) playSfx(s);
    },
    [sfxOn]
  );

  const showToast = useCallback((msg: string) => {
    setToast(msg);
    if (toastTimer.current) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3400);
  }, []);

  const addCoins = useCallback((n: number) => setCredits((c) => c + n), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      if (key === KONAMI[konamiIdx.current]) {
        konamiIdx.current += 1;
        if (konamiIdx.current === KONAMI.length) {
          konamiIdx.current = 0;
          setKonami(true);
          setCredits((c) => c + 30);
          playSfx("power");
          showToast(konamiMsg.current);
        }
      } else {
        konamiIdx.current = key === KONAMI[0] ? 1 : 0;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const toggleSfx = () => {
    setSfxOn((v) => {
      store("fried-sfx", v ? "0" : "1");
      if (!v) playSfx("select");
      return !v;
    });
  };
  const toggleCrt = () => {
    setCrtOn((v) => {
      store("fried-crt", v ? "0" : "1");
      playSfx("blip");
      return !v;
    });
  };

  return (
    <Ctx.Provider
      value={{ sfxOn, toggleSfx, play, crtOn, toggleCrt, credits, addCoins, toast, showToast, konami }}
    >
      {children}
    </Ctx.Provider>
  );
}

/* ------------------------------------------------ scroll reveal */
export function Reveal({
  children,
  delay = 0,
  className = "",
  as: Tag = "div",
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
  as?: "div" | "section" | "li" | "span";
}) {
  const ref = useRef<HTMLElement | null>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((en) => {
          if (en.isIntersecting) {
            en.target.classList.add("is-in");
            io.unobserve(en.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return (
    <Tag
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ref={ref as any}
      className={`reveal ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </Tag>
  );
}

/* ------------------------------------------------ typed text hook */
export function useTypedLines(
  lines: string[],
  active: boolean,
  speed = 14
): { shown: string[]; done: boolean } {
  const [shown, setShown] = useState<string[]>([]);
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (!active) return;
    let li = 0;
    let ci = 0;
    let cancelled = false;
    let timer = 0;
    setShown([]);
    setDone(false);
    const tick = () => {
      if (cancelled) return;
      if (li >= lines.length) {
        setDone(true);
        return;
      }
      ci += 2;
      const line = lines[li];
      if (ci >= line.length) {
        setShown(lines.slice(0, li + 1));
        li += 1;
        ci = 0;
        timer = window.setTimeout(tick, 90);
      } else {
        setShown([...lines.slice(0, li), line.slice(0, ci)]);
        if (Math.random() < 0.3) playSfx("type");
        timer = window.setTimeout(tick, speed);
      }
    };
    timer = window.setTimeout(tick, 200);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [active, lines, speed]);
  return { shown, done };
}
