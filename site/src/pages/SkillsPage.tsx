import { BookOpen, Bot, Terminal } from "lucide-react";
import { GuideShell, H2, Notes, Txt } from "./GuidePage";
import { useI18n } from "../i18n";

function Steps({ items }: { items: string[] }) {
  return (
    <ol className="mt-5 space-y-3">
      {items.map((s, i) => (
        <li key={s} className="flex gap-3 leading-relaxed text-cream/85">
          <span className="flex h-7 w-7 shrink-0 items-center justify-center border-2 border-pixel font-pixel text-[9px] text-pixel">{i + 1}</span>
          <span className="min-w-0 pt-0.5"><Txt s={s} /></span>
        </li>
      ))}
    </ol>
  );
}

export default function SkillsPage() {
  const { t } = useI18n();
  const s = t.skills;

  return (
    <GuideShell kicker={s.kicker} title={s.title} lead={s.lead} mascot={{ exp: "neutral", pose: "laptop" }}>
      <section>
        <H2 icon={BookOpen}>{s.coversTitle}</H2>
        <ul className="mt-5 grid gap-3 sm:grid-cols-2">
          {s.covers.map((c, i) => (
            <li key={c} className="flex items-center gap-3 border-2 border-night-3 bg-night-2 px-4 py-3 text-cream/85">
              <span className="font-pixel text-[9px] text-gold">{String(i + 1).padStart(2, "0")}</span>
              {c}
            </li>
          ))}
        </ul>
      </section>

      <div className="grid gap-8 md:grid-cols-2">
        <section className="border-[3px] border-night-3 bg-night-2 p-6">
          <H2 icon={Terminal}>{s.claudeTitle}</H2>
          <Steps items={s.claude} />
        </section>
        <section className="border-[3px] border-night-3 bg-night-2 p-6">
          <H2 icon={Bot}>{s.otherTitle}</H2>
          <Steps items={s.other} />
        </section>
      </div>

      <Notes items={s.notes} />
    </GuideShell>
  );
}
