import { useState } from "react";
import { Home, CircleDot, Crosshair, BookOpen, Bot, Heart, Menu, X } from "lucide-react";
import { ROUTES, hrefOf, type Route } from "../lib/router";
import { useRetro } from "../lib/retro";
import { useI18n, type Lang } from "../i18n";
import { FriedCharacter } from "./FriedCharacter";

const ICONS: Record<Route, typeof Home> = {
  landing: Home,
  pinball: CircleDot,
  lightgun: Crosshair,
  skills: BookOpen,
  knowledge: Bot,
  credits: Heart,
};

function LangSwitch() {
  const { lang, setLang, t } = useI18n();
  const { play } = useRetro();
  return (
    <div role="group" aria-label={t.nav.language} className="flex border-2 border-cream/30">
      {(["de", "en"] as Lang[]).map((l) => (
        <button
          key={l}
          type="button"
          lang={l}
          aria-pressed={lang === l}
          onClick={() => { if (l !== lang) { setLang(l); play("blip"); } }}
          className={`px-2 py-1.5 font-pixel text-[9px] transition ${lang === l ? "bg-gold text-night" : "text-cream/75 hover:text-cream"}`}
        >
          {l.toUpperCase()}
        </button>
      ))}
    </div>
  );
}

export default function Nav({ route }: { route: Route }) {
  const { play } = useRetro();
  const { t } = useI18n();
  const [open, setOpen] = useState(false);

  const label = (r: Route) =>
    ({ landing: t.nav.home, pinball: t.nav.pinball, lightgun: t.nav.lightgun, skills: t.nav.skills, knowledge: t.nav.chat, credits: t.nav.credits })[r];

  const link = (r: Route, mobile = false) => {
    const Icon = ICONS[r];
    const active = r === route;
    return (
      <a
        key={r}
        href={hrefOf(r)}
        aria-current={active ? "page" : undefined}
        onClick={() => { if (!active) play("select"); setOpen(false); }}
        className={
          mobile
            ? `mt-1 flex w-full items-center gap-2.5 border-2 px-3 py-2.5 font-pixel text-[9px] ${active ? "border-gold bg-gold text-night" : "border-night-3 text-cream/80"}`
            : `flex items-center gap-2 border-2 px-2.5 py-2 font-pixel text-[8px] transition ${active ? "border-gold bg-gold text-night" : "border-transparent text-cream/75 hover:border-cream/30 hover:text-cream"}`
        }
      >
        <Icon size={13} aria-hidden="true" /> {label(r).toUpperCase()}
      </a>
    );
  };

  return (
    <nav aria-label="Main" className="border-b-2 border-night-3 bg-night-2/95 backdrop-blur-sm">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-2 px-3 py-2">
        <a href={hrefOf("landing")} className="group flex min-w-0 items-center gap-2" aria-label={t.nav.home}>
          <FriedCharacter size="xs" expression="happy" showCable={false} glow={false} className="transition-transform group-hover:-rotate-6" />
          <span className="hidden truncate font-pixel text-[10px] text-cream sm:block">
            FRIED'S <span className="text-pixel">RETRO</span> <span className="text-gold">KIT</span>
          </span>
        </a>

        <div className="hidden items-center gap-0.5 lg:flex">{ROUTES.map((r) => link(r))}</div>

        <div className="flex items-center gap-2">
          <LangSwitch />
          <button
            type="button"
            onClick={() => { play("blip"); setOpen((o) => !o); }}
            className="border-2 border-cream/30 p-2 text-cream lg:hidden"
            aria-label={t.nav.menu}
            aria-expanded={open}
            aria-controls="mobile-nav"
          >
            {open ? <X size={16} /> : <Menu size={16} />}
          </button>
        </div>
      </div>

      {open && (
        <div id="mobile-nav" className="border-t-2 border-night-3 bg-night-2 px-3 pb-3 pt-1 lg:hidden">
          {ROUTES.map((r) => link(r, true))}
        </div>
      )}
    </nav>
  );
}
