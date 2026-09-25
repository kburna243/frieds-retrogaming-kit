import { Heart, Scale, ShieldAlert } from "lucide-react";
import { GithubMark } from "../components/ui";
import { REPO_URL } from "../config";
import { hrefOf } from "../lib/router";
import { useI18n } from "../i18n";

export function LegalNote({ className = "" }: { className?: string }) {
  const { t } = useI18n();
  return (
    <aside className={`flex gap-3 border-[3px] border-retro/70 bg-retro/10 p-4 sm:p-5 ${className}`} aria-label={t.legal.title}>
      <ShieldAlert size={20} className="mt-0.5 shrink-0 text-retro" aria-hidden="true" />
      <div>
        <div className="font-pixel text-[9px] text-retro">{t.legal.title.toUpperCase()}</div>
        <p className="mt-2 leading-relaxed text-cream/85">{t.legal.text}</p>
      </div>
    </aside>
  );
}

export default function Footer({ showLegal = true }: { showLegal?: boolean }) {
  const { t } = useI18n();
  return (
    <footer className="relative overflow-hidden border-t-2 border-night-3 bg-night pt-14">
      <div className="grid-bg absolute inset-0 opacity-50" />
      <div className="relative mx-auto max-w-5xl px-5">
        {showLegal && <LegalNote />}

        <p className="mt-4 pt-8 text-center font-pixel text-[10px] leading-loose tracking-wider text-cream sm:text-xs">
          {t.footer.tagline}
        </p>

        <div className="mt-10 flex flex-col items-center justify-between gap-4 border-t-2 border-night-3 py-8 font-term text-lg text-cream/70 sm:flex-row">
          <span className="flex items-center gap-2">
            <Scale size={15} className="text-gold" aria-hidden="true" />
            {t.footer.license}
          </span>
          <nav aria-label="Footer" className="flex flex-wrap items-center justify-center gap-5">
            <a href={hrefOf("credits")} className="flex items-center gap-1.5 text-gold underline-offset-4 hover:underline">
              <Heart size={14} aria-hidden="true" /> {t.footer.credits}
            </a>
            <a href={REPO_URL} target="_blank" rel="noreferrer" className="flex items-center gap-1.5 text-cream/80 underline-offset-4 hover:text-cream hover:underline">
              <GithubMark size={15} /> {t.footer.repo}
            </a>
          </nav>
        </div>

        <div className="flex flex-col items-center gap-3 pb-24 text-center">
          <span className="font-pixel text-[8px] text-cream/60">{t.footer.status}</span>
          <span className="font-pixel text-[8px] text-cream/40" aria-hidden="true">↑ ↑ ↓ ↓ ← → ← → B A</span>
        </div>
      </div>
    </footer>
  );
}
