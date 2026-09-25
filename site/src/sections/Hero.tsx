import { useEffect, useState } from "react";
import { ChevronDown, BookOpen } from "lucide-react";
import { FriedCharacter, type FriedExpression, type FriedPose } from "../components/FriedCharacter";
import { ChunkButton, GithubButton } from "../components/ui";
import { useRetro } from "../lib/retro";
import { useI18n } from "../i18n";

// one mood + pose per speech bubble (same order as t.hero.bubbles)
const MOODS: { exp: FriedExpression; pose: FriedPose }[] = [
  { exp: "friendly", pose: "controller" },
  { exp: "winking", pose: "thumbs-up" },
  { exp: "neutral", pose: "laptop" },
  { exp: "surprised", pose: "controller" },
  { exp: "happy", pose: "celebrate" },
];

const PIXELS = [
  { l: "6%", d: "11s", dl: "0s", c: "#3DDC84", s: 6 },
  { l: "16%", d: "14s", dl: "2s", c: "#FFC857", s: 4 },
  { l: "28%", d: "9s", dl: "4s", c: "#FF4B3A", s: 5 },
  { l: "41%", d: "13s", dl: "1s", c: "#3DDC84", s: 4 },
  { l: "55%", d: "10s", dl: "3s", c: "#FFC857", s: 6 },
  { l: "67%", d: "15s", dl: "0.5s", c: "#3DDC84", s: 5 },
  { l: "78%", d: "12s", dl: "2.5s", c: "#FF4B3A", s: 4 },
  { l: "88%", d: "9.5s", dl: "1.5s", c: "#FFC857", s: 6 },
];

const reducedMotion = () => window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

export default function Hero() {
  const { play, credits, addCoins } = useRetro();
  const { t } = useI18n();
  const [bi, setBi] = useState(0);

  useEffect(() => {
    if (reducedMotion()) return; // no auto-rotating content
    const id = window.setInterval(() => setBi((i) => (i + 1) % MOODS.length), 3600);
    return () => window.clearInterval(id);
  }, []);

  const mood = MOODS[bi];

  return (
    <section className="relative overflow-hidden bg-night pb-16 pt-10 lg:pt-14" id="top">
      <div className="grid-bg absolute inset-0" />
      {PIXELS.map((p, i) => (
        <span
          key={i}
          aria-hidden="true"
          className="pointer-events-none absolute bottom-0"
          style={{ left: p.l, width: p.s, height: p.s, background: p.c, animation: `float-pixel ${p.d} linear ${p.dl} infinite` }}
        />
      ))}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute right-[-10%] top-1/4 h-[520px] w-[520px] rounded-full opacity-60"
        style={{ background: "radial-gradient(circle, rgba(61,220,132,0.13), transparent 65%)", animation: "glowpulse 5s ease-in-out infinite" }}
      />

      <div className="absolute right-4 top-6 z-10 hidden sm:right-10 sm:block">
        <div className="stamp border-[3px] border-retro px-3 py-2 font-pixel text-[9px] text-retro" style={{ transform: "rotate(6deg)" }}>
          {t.hero.wip}
          <span className="mt-1 block text-[7px] text-retro/80">{t.hero.wipSub}</span>
        </div>
      </div>

      <div className="relative mx-auto grid max-w-7xl items-center gap-12 px-5 lg:grid-cols-[1.05fr_0.95fr] lg:gap-8">
        <div className="min-w-0">
          <div className="mb-6 flex flex-wrap items-center gap-3 font-pixel text-[10px] text-pixel">
            <span className="h-2.5 w-2.5 rounded-full bg-pixel" style={{ animation: "pulse-dot 1.6s infinite" }} />
            {t.hero.kicker}
            <span className="border-2 border-retro px-1.5 py-0.5 text-retro sm:hidden">{t.hero.wip}</span>
          </div>

          <h1 className="font-display text-cream">
            <span className="block text-6xl font-black leading-none sm:text-7xl lg:text-[6.2rem]">{t.hero.title1}</span>
            <span className="mt-2 block text-3xl font-bold leading-tight text-cream/90 sm:text-4xl lg:text-5xl">{t.hero.title2}</span>
          </h1>
          <div className="mt-6 h-1.5 w-24 bg-retro" />

          <p className="mt-7 max-w-xl border-l-4 border-gold pl-5 font-display text-xl italic leading-snug text-gold sm:text-2xl">
            {t.hero.claim}
          </p>
          <p className="mt-5 max-w-xl text-lg leading-relaxed text-cream/80">{t.hero.sub}</p>

          <div className="mt-9 flex flex-wrap items-center gap-5">
            <ChunkButton
              variant="gold"
              onClick={() => {
                play("select");
                document.getElementById("kit")?.scrollIntoView({ behavior: reducedMotion() ? "auto" : "smooth" });
              }}
            >
              <BookOpen size={15} aria-hidden="true" /> {t.hero.ctaGuides}
            </ChunkButton>
            <GithubButton />
          </div>
        </div>

        {/* Fried on his pedestal */}
        <div className="relative mx-auto w-full max-w-md">
          <div className="absolute -top-2 left-1/2 z-10 w-max max-w-[260px] -translate-x-1/2" aria-live="polite">
            <div className="relative border-[3px] border-night bg-cream px-4 py-2.5 shadow-chunk-sm">
              <p key={bi} className="font-term text-xl leading-tight text-night" style={{ animation: "flicker 0.4s" }}>
                {t.hero.bubbles[bi]}
              </p>
              <span className="absolute -bottom-[9px] left-1/2 h-4 w-4 -translate-x-1/2 rotate-45 border-b-[3px] border-r-[3px] border-night bg-cream" />
            </div>
          </div>

          <div className="mt-14 rounded-[2rem] border-[3px] border-night-3 bg-night-2/60 p-6 sm:p-8">
            <div className="flex justify-center">
              <FriedCharacter
                size="xl"
                expression={mood.exp}
                pose={mood.pose}
                interactive
                label={t.hero.mascot}
                className="anim-bob"
              />
            </div>
            <div className="mt-4 flex items-center justify-between border-t-2 border-night-3 pt-4 font-pixel text-[8px] text-cream/70">
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full bg-pixel" style={{ animation: "pulse-dot 1.4s infinite" }} />
                PWR
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full bg-gold" style={{ animation: "glowpulse 2s infinite" }} />
                KIT.LOAD
              </span>
              <button
                type="button"
                onClick={() => { addCoins(1); play("coin"); }}
                className="text-retro transition hover:text-gold"
                aria-label={t.hud.coin}
              >
                INSERT COIN {credits > 0 && `(${credits})`}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-14 flex justify-center" aria-hidden="true">
        <ChevronDown className="h-6 w-6 text-cream/50" style={{ animation: "bob 1.8s ease-in-out infinite" }} />
      </div>
    </section>
  );
}
