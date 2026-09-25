import type { ReactNode } from "react";
import { ArrowLeft, BookOpen, CheckCircle2, Construction, Download, Info, Package } from "lucide-react";
import { FriedCharacter, type FriedExpression, type FriedPose } from "../components/FriedCharacter";
import { LegalNote } from "../sections/Footer";
import { Reveal } from "../lib/retro";
import { hrefOf } from "../lib/router";
import { useI18n } from "../i18n";
import { REPO_URL } from "../config";

/** Renders `code` spans inside dictionary strings. */
export function Txt({ s }: { s: string }) {
  return (
    <>
      {s.split(/(`[^`]+`)/g).map((p, i) =>
        p.startsWith("`") ? (
          <code key={i} className="break-all border border-pixel-dim/60 bg-screen px-1 font-term text-[1.05em] text-pixel">
            {p.slice(1, -1)}
          </code>
        ) : (
          <span key={i}>{p}</span>
        )
      )}
    </>
  );
}

export function GuideShell({
  kicker,
  title,
  lead,
  mascot,
  children,
}: {
  kicker: string;
  title: string;
  lead: string;
  mascot: { exp: FriedExpression; pose: FriedPose };
  children: ReactNode;
}) {
  const { t } = useI18n();
  return (
    <div className="bg-night">
      <section className="relative overflow-hidden pb-12 pt-12">
        <div className="grid-bg absolute inset-0 opacity-60" />
        <div className="relative mx-auto grid max-w-6xl items-center gap-8 px-5 md:grid-cols-[1fr_auto]">
          <Reveal>
            <a href={hrefOf("landing")} className="inline-flex items-center gap-2 font-pixel text-[8px] text-cream/70 hover:text-gold">
              <ArrowLeft size={12} aria-hidden="true" /> {t.guide.back}
            </a>
            <div className="mt-6 font-pixel text-[10px] text-pixel">{kicker}</div>
            <h1 className="mt-3 font-display text-4xl font-black leading-[1.05] text-cream sm:text-6xl">{title}</h1>
            <div className="mt-5 h-1.5 w-16 bg-retro" />
            <p className="mt-6 max-w-2xl text-lg leading-relaxed text-cream/85">{lead}</p>
            <div className="mt-6 inline-flex max-w-full items-start gap-3 border-[3px] border-retro bg-night-2 px-4 py-3">
              <Construction size={18} className="mt-0.5 shrink-0 text-retro" aria-hidden="true" />
              <div>
                <div className="font-pixel text-[9px] leading-relaxed text-retro">{t.guide.wipBadge}</div>
                <p className="mt-1 text-cream/85">{t.guide.wipNote}</p>
              </div>
            </div>
          </Reveal>
          <div className="hidden md:block">
            <FriedCharacter size="lg" expression={mascot.exp} pose={mascot.pose} showCable={false} />
          </div>
        </div>
      </section>
      <div className="mx-auto max-w-6xl space-y-14 px-5 pb-20">{children}</div>
    </div>
  );
}

export function H2({ children, icon: Icon }: { children: ReactNode; icon: typeof Info }) {
  return (
    <h2 className="flex items-center gap-3 font-pixel text-[12px] leading-relaxed text-gold">
      <Icon size={16} aria-hidden="true" /> {children}
    </h2>
  );
}

function List({ items, marker }: { items: string[]; marker: string }) {
  return (
    <ul className="mt-5 space-y-3">
      {items.map((it) => (
        <li key={it} className="flex gap-3 leading-relaxed text-cream/85">
          <span className={`mt-2 h-2 w-2 shrink-0 ${marker}`} aria-hidden="true" />
          <span><Txt s={it} /></span>
        </li>
      ))}
    </ul>
  );
}

export function Notes({ items }: { items: string[] }) {
  const { t } = useI18n();
  return (
    <section>
      <H2 icon={Info}>{t.guide.notes}</H2>
      <List items={items} marker="bg-cream/60" />
    </section>
  );
}

export default function GuidePage({ kind }: { kind: "pinball" | "lightgun" }) {
  const { lang, t } = useI18n();
  const g = t[kind];
  const docFile = `${kind}-guide${lang === "de" ? ".de" : ""}.md`;
  const docUrl = `${REPO_URL}/blob/main/docs/${docFile}`;

  return (
    <GuideShell
      kicker={g.kicker}
      title={g.title}
      lead={g.lead}
      mascot={kind === "pinball" ? { exp: "friendly", pose: "controller" } : { exp: "winking", pose: "thumbs-up" }}
    >
      {kind === "pinball" && (
        <section>
          <H2 icon={Info}>{t.guide.modes}</H2>
          <div className="mt-5 grid gap-5 md:grid-cols-2">
            {t.pinball.modes.map((m) => (
              <div key={m.title} className="border-[3px] border-night-3 bg-night-2 p-5">
                <h3 className="font-display text-xl font-bold text-cream">{m.title}</h3>
                <p className="mt-2 leading-relaxed text-cream/80">{m.text}</p>
              </div>
            ))}
          </div>
        </section>
      )}

      <div className="grid gap-10 md:grid-cols-2">
        <section>
          <H2 icon={Package}>{t.guide.bring}</H2>
          <List items={g.bring} marker="bg-gold" />
        </section>
        <section>
          <H2 icon={Download}>{t.guide.loads}</H2>
          <List items={g.loads} marker="bg-pixel" />
        </section>
      </div>

      <LegalNote />

      <section>
        <H2 icon={CheckCircle2}>{t.guide.steps}</H2>
        <ol className="mt-6 grid gap-4 md:grid-cols-2">
          {g.steps.map((s, i) => (
            <li key={s.title} className="flex gap-4 border-[3px] border-night-3 bg-night-2 p-5">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center border-2 border-pixel font-pixel text-[10px] text-pixel">
                {i + 1}
              </span>
              <div className="min-w-0">
                <h3 className="font-pixel text-[10px] leading-relaxed text-cream">{s.title}</h3>
                <p className="mt-2 leading-relaxed text-cream/80"><Txt s={s.text} /></p>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <Notes items={g.notes} />

      <div className="border-[3px] border-pixel/60 bg-night-2 p-5 sm:flex sm:items-center sm:justify-between">
        <div>
          <h3 className="font-pixel text-[10px] text-pixel">{t.guide.viewDoc}</h3>
          <p className="mt-1 font-term text-base text-cream/80">docs/{docFile}</p>
        </div>
        <a
          href={docUrl}
          target="_blank"
          rel="noreferrer"
          className="mt-4 inline-flex items-center gap-2 border-2 border-pixel bg-pixel/10 px-4 py-2 font-pixel text-[9px] text-pixel transition hover:bg-pixel hover:text-night sm:mt-0"
        >
          <BookOpen size={14} aria-hidden="true" /> {docFile}
        </a>
      </div>
    </GuideShell>
  );
}
