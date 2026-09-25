import { useEffect, useRef, useState, type ReactNode } from "react";
import { Volume2, VolumeX, Tv, Coins } from "lucide-react";

export function GithubMark({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.56 0-.27-.01-1.17-.02-2.12-3.2.7-3.88-1.36-3.88-1.36-.52-1.33-1.28-1.68-1.28-1.68-1.04-.71.08-.7.08-.7 1.15.08 1.76 1.18 1.76 1.18 1.03 1.76 2.69 1.25 3.35.96.1-.75.4-1.25.72-1.54-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.05 0 0 .96-.31 3.15 1.18a10.9 10.9 0 0 1 2.87-.39c.97 0 1.95.13 2.87.39 2.19-1.49 3.15-1.18 3.15-1.18.62 1.59.23 2.76.11 3.05.73.81 1.18 1.83 1.18 3.09 0 4.41-2.69 5.38-5.25 5.67.41.35.77 1.05.77 2.12 0 1.53-.01 2.76-.01 3.14 0 .31.21.67.8.55A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5z" />
    </svg>
  );
}
import { useRetro, useTypedLines, store } from "../lib/retro";
import { useI18n } from "../i18n";
import { REPO_URL } from "../config";

/* ------------------------------------------------ boot sequence */
export function BootSequence({ onDone }: { onDone: () => void }) {
  const { t } = useI18n();
  const [phase, setPhase] = useState<"boot" | "off">("boot");
  const { shown, done } = useTypedLines(t.boot.lines, phase === "boot", 8);
  const finished = useRef(false);

  const skip = () => {
    if (finished.current) return;
    finished.current = true;
    setPhase("off");
    window.setTimeout(onDone, 520);
  };

  useEffect(() => {
    if (done && !finished.current) {
      const t = window.setTimeout(skip, 650);
      return () => window.clearTimeout(t);
    }
  }, [done]);

  useEffect(() => {
    window.addEventListener("keydown", skip);
    return () => window.removeEventListener("keydown", skip);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div
      onClick={skip}
      role="dialog"
      aria-label="Boot"
      className={`fixed inset-0 z-[100] flex cursor-pointer items-center justify-center bg-screen ${
        phase === "off" ? "pointer-events-none" : ""
      }`}
      style={phase === "off" ? { animation: "crtoff 0.5s ease-in forwards" } : undefined}
    >
      <div className="w-full max-w-2xl px-6 font-term text-xl leading-relaxed text-pixel sm:text-2xl">
        {shown.map((l, i) => (
          <div key={i} className="whitespace-pre-wrap">
            {/(OK|WIP)$/.test(l) ? (
              <>
                {l.replace(/(OK|WIP)$/, "")}
                <span className={l.endsWith("WIP") ? "text-retro" : "text-gold"}>{l.endsWith("WIP") ? "WIP" : "OK"}</span>
              </>
            ) : (
              l
            )}
          </div>
        ))}
        {!done && <span className="caret" />}
        <div className="mt-4 font-pixel text-[10px] text-cream/70" aria-hidden="true">
          {t.boot.hint}
        </div>
      </div>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); skip(); }}
        autoFocus
        className="absolute bottom-6 right-6 border-2 border-pixel px-3 py-2 font-pixel text-[10px] text-pixel hover:bg-pixel hover:text-night"
      >
        {t.boot.skip} ▸
      </button>
      <div className="crt-overlay" />
    </div>
  );
}

/* ------------------------------------------------ HUD */
function pad(n: number) {
  return n.toString().padStart(6, "0");
}

export function Hud() {
  const { sfxOn, toggleSfx, crtOn, toggleCrt, credits, addCoins, play } = useRetro();
  const { t } = useI18n();
  const [score, setScore] = useState(0);
  const [hi, setHi] = useState(0);
  const [pops, setPops] = useState<number[]>([]);

  useEffect(() => {
    const saved = Number(store("fried-hi") || 0);
    setHi(saved);
    let raf = 0;
    const onScroll = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const s = Math.min(999900, Math.floor(window.scrollY / 6) * 50);
        setScore(s);
        setHi((h) => {
          const nh = Math.max(h, s);
          if (nh !== h) store("fried-hi", String(nh));
          return nh;
        });
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => {
      window.removeEventListener("scroll", onScroll);
      cancelAnimationFrame(raf);
    };
  }, []);

  const coin = () => {
    addCoins(1);
    play("coin");
    const id = Date.now();
    setPops((p) => [...p, id]);
    window.setTimeout(() => setPops((p) => p.filter((x) => x !== id)), 800);
  };

  return (
    <header className="border-b-2 border-night-3 bg-night/95 backdrop-blur-sm">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-2 px-3 py-2 font-pixel text-[9px] sm:text-[10px]">
        <div className="flex items-center gap-3 sm:gap-5">
          <span className="text-retro">1UP</span>
          <span className="text-pixel tabular-nums">{pad(score)}</span>
          <span className="hidden text-gold sm:inline">HI</span>
          <span className="hidden text-cream/80 tabular-nums sm:inline">{pad(hi)}</span>
        </div>

        <div className="hidden items-center gap-2 text-cream/70 md:flex">
          <svg viewBox="0 0 40 24" className="h-4 w-6" aria-hidden="true">
            <polygon points="4,22 9,6 15,15 20,2 25,15 31,6 36,22" fill="#FFC857" />
          </svg>
          <span>{t.hud.title}</span>
        </div>

        <div className="relative flex items-center gap-2 sm:gap-4">
          {pops.map((id) => (
            <span
              key={id}
              className="pointer-events-none absolute -top-1 right-16 text-gold"
              style={{ animation: "coin-pop 0.7s ease-out forwards" }}
            >
              +1
            </span>
          ))}
          <span className="text-cream/70">
            {t.hud.credit} <span className="text-gold tabular-nums">{String(credits).padStart(2, "0")}</span>
          </span>
          <button
            onClick={coin}
            aria-label={t.hud.coin}
            title={t.hud.coin}
            className="flex items-center gap-1 border-2 border-gold px-2 py-1 text-gold transition hover:bg-gold hover:text-night"
          >
            <Coins size={12} /> <span className="hidden sm:inline">COIN</span>
          </button>
          <button
            onClick={toggleSfx}
            aria-label={sfxOn ? t.hud.soundOff : t.hud.soundOn}
            aria-pressed={sfxOn}
            title={sfxOn ? t.hud.soundOff : t.hud.soundOn}
            className={`border-2 px-2 py-1 transition ${
              sfxOn ? "border-pixel text-pixel" : "border-cream/30 text-cream/40"
            } hover:bg-cream/10`}
          >
            {sfxOn ? <Volume2 size={12} /> : <VolumeX size={12} />}
          </button>
          <button
            onClick={toggleCrt}
            aria-label={crtOn ? t.hud.crtOff : t.hud.crtOn}
            aria-pressed={crtOn}
            title={crtOn ? t.hud.crtOff : t.hud.crtOn}
            className={`border-2 px-2 py-1 transition ${
              crtOn ? "border-pixel text-pixel" : "border-cream/30 text-cream/40"
            } hover:bg-cream/10`}
          >
            <Tv size={12} />
          </button>
        </div>
      </div>
    </header>
  );
}

/* ------------------------------------------------ overlays + toast */
export function CrtOverlay() {
  const { crtOn, konami } = useRetro();
  if (!crtOn) return null;
  return (
    <>
      <div className={`crt-overlay ${konami ? "rainbow" : ""}`} />
      <div className="crt-vignette" />
    </>
  );
}

export function Toast() {
  const { toast } = useRetro();
  if (!toast) return null;
  return (
    <div role="status" className="fixed bottom-6 left-1/2 z-[95] w-[min(92vw,560px)] -translate-x-1/2">
      <div className="border-4 border-night bg-gold px-5 py-4 font-term text-xl leading-snug text-night shadow-chunk">
        <span className="mr-2 font-pixel text-[10px] text-retro">★</span>
        {toast}
      </div>
    </div>
  );
}

/* ------------------------------------------------ primitives */
export function SectionHeading({
  kicker,
  title,
  intro,
  dark = true,
  className = "",
}: {
  kicker: string;
  title: ReactNode;
  intro?: ReactNode;
  dark?: boolean;
  className?: string;
}) {
  return (
    <div className={`max-w-3xl ${className}`}>
      <div className={`mb-4 flex items-center gap-3 font-pixel text-[10px] ${dark ? "text-pixel" : "text-retro"}`}>
        <span className="inline-block h-[3px] w-8 bg-current" />
        {kicker}
      </div>
      <h2
        className={`font-display text-4xl font-black leading-[1.05] sm:text-5xl lg:text-6xl ${
          dark ? "text-cream" : "text-night"
        }`}
      >
        {title}
      </h2>
      <div className="mt-5 h-1.5 w-16 bg-retro" />
      {intro && (
        <p className={`mt-6 text-lg leading-relaxed ${dark ? "text-cream/75" : "text-night/75"}`}>
          {intro}
        </p>
      )}
    </div>
  );
}

export function ChunkButton({
  children,
  href,
  onClick,
  variant = "red",
  className = "",
}: {
  children: ReactNode;
  href?: string;
  onClick?: () => void;
  variant?: "red" | "gold" | "ghost-dark" | "ghost-light";
  className?: string;
}) {
  const styles = {
    red: "bg-retro text-cream border-night shadow-chunk",
    gold: "bg-gold text-night border-night shadow-chunk",
    "ghost-dark": "bg-transparent text-night border-night shadow-chunk-sm hover:bg-night hover:text-cream",
    "ghost-light": "bg-transparent text-cream border-cream shadow-chunk-sm hover:bg-cream hover:text-night",
  }[variant];
  const cls = `btn-chunk inline-flex max-w-full items-center gap-2.5 border-[3px] px-6 py-3.5 font-pixel text-[11px] ${styles} ${className}`;
  if (href) {
    return (
      <a href={href} target={href.startsWith("http") ? "_blank" : undefined} rel="noreferrer" className={cls}>
        {children}
      </a>
    );
  }
  return (
    <button onClick={onClick} className={cls}>
      {children}
    </button>
  );
}

export function GithubButton({ className = "" }: { className?: string }) {
  const { t } = useI18n();
  return (
    <ChunkButton href={REPO_URL} variant="red" className={className}>
      <GithubMark size={16} /> {t.hero.ctaRepo}
    </ChunkButton>
  );
}
