import { ArrowRight, BookOpen, CircleDot, Crosshair, Heart, ListChecks, Route as RouteIcon, ShieldCheck, Package } from "lucide-react";
import Hero from "../sections/Hero";
import { SectionHeading } from "../components/ui";
import { Reveal } from "../lib/retro";
import { hrefOf, type Route } from "../lib/router";
import { useI18n } from "../i18n";

const CARDS: { id: "pinball" | "lightgun" | "skills"; icon: typeof CircleDot; accent: string }[] = [
  { id: "pinball", icon: CircleDot, accent: "border-gold text-gold" },
  { id: "lightgun", icon: Crosshair, accent: "border-retro text-retro" },
  { id: "skills", icon: BookOpen, accent: "border-pixel text-pixel" },
];

const HOW_ICONS = [RouteIcon, ListChecks, Package, ShieldCheck];

export default function Landing() {
  const { t } = useI18n();

  return (
    <>
      <Hero />

      {/* three building blocks */}
      <section id="kit" className="scroll-mt-28 bg-cream-2 py-20 text-night">
        <div className="mx-auto max-w-7xl px-5">
          <Reveal>
            <SectionHeading kicker={t.cards.kicker} title={t.cards.title} dark={false} />
          </Reveal>
          <div className="mt-12 grid gap-6 md:grid-cols-3">
            {CARDS.map((c, i) => {
              const card = t.cards[c.id];
              return (
                <Reveal key={c.id} delay={i * 90}>
                  <a
                    href={hrefOf(c.id as Route)}
                    className="btn-chunk group flex h-full flex-col border-[3px] border-night bg-cream p-6 shadow-chunk"
                  >
                    <span className={`flex h-12 w-12 items-center justify-center border-[3px] bg-night ${c.accent}`}>
                      <c.icon size={22} aria-hidden="true" />
                    </span>
                    <h3 className="mt-5 font-display text-2xl font-black leading-tight">{card.title}</h3>
                    <p className="mt-3 flex-1 leading-relaxed text-night/80">{card.text}</p>
                    <span className="mt-6 flex items-center justify-between border-t-2 border-night/15 pt-4 font-pixel text-[9px]">
                      <span className="text-retro">WIP</span>
                      <span className="flex items-center gap-2">
                        {t.cards.open} <ArrowRight size={13} className="transition-transform group-hover:translate-x-1" aria-hidden="true" />
                      </span>
                    </span>
                  </a>
                </Reveal>
              );
            })}
          </div>
        </div>
      </section>

      {/* how it works */}
      <section className="bg-night py-20">
        <div className="mx-auto max-w-7xl px-5">
          <Reveal>
            <SectionHeading kicker={t.how.kicker} title={t.how.title} />
          </Reveal>
          <ol className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {t.how.steps.map((s, i) => {
              const Icon = HOW_ICONS[i];
              return (
                <Reveal key={s.title} as="li" delay={i * 80}>
                  <div className="h-full border-[3px] border-night-3 bg-night-2 p-5">
                    <div className="flex items-center gap-3">
                      <span className="font-pixel text-[10px] text-gold">0{i + 1}</span>
                      <Icon size={18} className="text-pixel" aria-hidden="true" />
                    </div>
                    <h3 className="mt-4 font-pixel text-[11px] leading-relaxed text-cream">{s.title}</h3>
                    <p className="mt-3 leading-relaxed text-cream/80">{s.text}</p>
                  </div>
                </Reveal>
              );
            })}
          </ol>
        </div>
      </section>

      {/* credits teaser */}
      <section className="border-y-4 border-night bg-gold py-16 text-night">
        <div className="mx-auto flex max-w-5xl flex-col items-start gap-6 px-5 md:flex-row md:items-center md:justify-between">
          <div className="max-w-2xl">
            <div className="flex items-center gap-2 font-pixel text-[10px] text-night/80">
              <Heart size={13} className="fill-retro text-retro" aria-hidden="true" /> {t.creditsTeaser.kicker}
            </div>
            <h2 className="mt-3 font-display text-3xl font-black leading-tight sm:text-4xl">{t.creditsTeaser.title}</h2>
            <p className="mt-3 text-lg leading-relaxed text-night/85">{t.creditsTeaser.text}</p>
          </div>
          <a
            href={hrefOf("credits")}
            className="btn-chunk inline-flex shrink-0 items-center gap-2.5 border-[3px] border-night bg-night px-6 py-3.5 font-pixel text-[11px] text-gold shadow-chunk-sm"
          >
            {t.creditsTeaser.cta} <ArrowRight size={14} aria-hidden="true" />
          </a>
        </div>
      </section>
    </>
  );
}
