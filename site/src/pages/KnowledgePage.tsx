import { Info } from "lucide-react";
import ChatPanel from "../components/ChatPanel";
import { FriedCharacter } from "../components/FriedCharacter";
import { Reveal } from "../lib/retro";
import { useI18n } from "../i18n";

export default function KnowledgePage() {
  const { t } = useI18n();
  const c = t.chat;
  return (
    <div className="bg-night">
      <section className="relative overflow-hidden pb-20 pt-12">
        <div className="grid-bg absolute inset-0 opacity-60" />
        <div className="relative mx-auto max-w-5xl px-5">
          <Reveal>
            <div className="flex items-center gap-5">
              <FriedCharacter size="md" expression="friendly" pose="laptop" showCable={false} className="hidden shrink-0 sm:inline-flex" />
              <div>
                <div className="font-pixel text-[10px] text-pixel">{c.kicker}</div>
                <h1 className="mt-3 font-display text-4xl font-black leading-[1.05] text-cream sm:text-6xl">
                  {c.title} <span className="italic text-gold">{c.titleAccent}</span>
                </h1>
              </div>
            </div>
            <div className="mt-5 h-1.5 w-16 bg-retro" />
            <p className="mt-6 max-w-3xl text-lg leading-relaxed text-cream/85">{c.lead}</p>
            <p className="mt-3 flex max-w-3xl gap-2 text-cream/70">
              <Info size={16} className="mt-1 shrink-0 text-gold" aria-hidden="true" /> {c.kbNote}
            </p>
          </Reveal>
          <div className="mt-10 shadow-chunk-gold">
            <ChatPanel fullPage />
          </div>
        </div>
      </section>
    </div>
  );
}
