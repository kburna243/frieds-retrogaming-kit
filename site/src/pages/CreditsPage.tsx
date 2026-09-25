import { ExternalLink, Heart } from "lucide-react";
import { FriedCharacter } from "../components/FriedCharacter";
import { Reveal } from "../lib/retro";
import { REPO_URL } from "../config";
import { useI18n } from "../i18n";
import type { Dict } from "../i18n/de";

type RoleKey = keyof Dict["credits"]["roles"];
type Entry = { name: string; role: RoleKey; url?: string };

// Names and links from CREDITS.md; role texts live in the dictionaries.
const GROUPS: { key: keyof Dict["credits"]["groups"]; items: Entry[] }[] = [
  {
    key: "communities",
    items: [
      { name: "Lightgun Lunatics", role: "lightgunLunatics" },
      { name: "Pinball Lunatics", role: "pinballLunatics" },
    ],
  },
  {
    key: "lightgun",
    items: [
      { name: "Lichtknarre", role: "lichtknarre" },
      { name: "Touchmote", role: "touchmote" },
      { name: "Gunmote (gunmotelabs)", role: "gunmote", url: "https://github.com/gunmotelabs/Gunmote" },
      { name: "DemulShooter (argonlefou)", role: "demulshooter" },
      { name: "RetroBat (RetroBat-Team)", role: "retrobat" },
      { name: "ViGEmBus (Nefarius)", role: "vigembus" },
      { name: "MAMEHooker (Howard Casto), OutputHooker, QMamehook", role: "mamehooker" },
      { name: "TeknoParrot (Teknogods)", role: "teknoparrot" },
      { name: "Emulators", role: "emulators" },
    ],
  },
  {
    key: "pinball",
    items: [
      { name: "PinUP Popper / PinUP Player (nailbuster)", role: "popper", url: "https://www.nailbuster.com/wikipinup/" },
      { name: "Baller-Installer", role: "baller", url: "https://www.nailbuster.com/wikipinup/" },
      { name: "Visual Pinball X, VPinMAME/PinMAME (vpinball)", role: "vpx", url: "https://github.com/vpinball" },
      { name: "B2S Backglass Server", role: "b2s", url: "https://github.com/vpinball/b2s-backglass" },
      { name: "DMD Extensions (Freezy)", role: "dmdext", url: "https://github.com/freezy/dmd-extensions" },
      { name: "FlexDMD (vbousquet)", role: "flexdmd", url: "https://github.com/vbousquet/flexdmd" },
      { name: "Future Pinball (BSP Software), BAM (Ravarcade)", role: "futurepinball" },
      { name: "DOFLinx", role: "doflinx" },
      { name: "Moster (flippermarkt.de)", role: "moster", url: "https://vpinball.de" },
    ],
  },
];

export default function CreditsPage() {
  const { t } = useI18n();
  const c = t.credits;

  return (
    <div className="bg-night">
      <section className="relative overflow-hidden pb-20 pt-12">
        <div className="grid-bg absolute inset-0 opacity-60" />
        <div className="relative mx-auto max-w-6xl px-5">
          <Reveal>
            <div className="flex flex-col gap-6 sm:flex-row sm:items-center">
              <FriedCharacter size="lg" expression="happy" pose="celebrate" showCable={false} className="self-start" />
              <div>
                <div className="flex items-center gap-2 font-pixel text-[10px] text-pixel">
                  <Heart size={13} className="fill-retro text-retro" aria-hidden="true" /> {c.kicker}
                </div>
                <h1 className="mt-3 font-display text-5xl font-black leading-none text-cream sm:text-7xl">{c.title}</h1>
                <p className="mt-5 max-w-2xl text-lg leading-relaxed text-cream/85">{c.lead}</p>
                <p className="mt-3 max-w-2xl text-cream/65">{c.draft}</p>
              </div>
            </div>
          </Reveal>

          {GROUPS.map((g) => (
            <section key={g.key} className="mt-14">
              <h2 className="font-pixel text-[12px] text-gold">{c.groups[g.key].toUpperCase()}</h2>
              <ul className="mt-5 grid gap-4 md:grid-cols-2">
                {g.items.map((it) => (
                  <li key={it.name} className="flex flex-col border-[3px] border-night-3 bg-night-2 p-5">
                    <h3 className="font-display text-xl font-bold leading-snug text-cream">{it.role === "emulators" ? c.emulatorsTitle : it.name}</h3>
                    <p className="mt-2 flex-1 leading-relaxed text-cream/80">{c.roles[it.role]}</p>
                    <div className="mt-3 font-term text-lg">
                      {it.url ? (
                        <a href={it.url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1.5 break-all text-pixel underline-offset-4 hover:underline">
                          {it.url.replace(/^https?:\/\//, "")} <ExternalLink size={13} aria-hidden="true" />
                        </a>
                      ) : (
                        <span className="text-cream/55">{c.linkPending}</span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          ))}

          <section className="mt-14">
            <h2 className="font-pixel text-[12px] text-gold">{c.groups.microsoft.toUpperCase()}</h2>
            <p className="mt-4 max-w-3xl leading-relaxed text-cream/80">{c.microsoft}</p>
          </section>

          <div className="mt-14 flex flex-col items-start gap-4 border-t-2 border-night-3 pt-8 sm:flex-row sm:items-center sm:justify-between">
            <p className="max-w-2xl text-cream/85">{c.missing}</p>
            <a
              href={`${REPO_URL}/issues`}
              target="_blank"
              rel="noreferrer"
              className="btn-chunk inline-flex shrink-0 items-center gap-2 border-[3px] border-night bg-gold px-5 py-3 font-pixel text-[10px] text-night shadow-chunk-sm"
            >
              {c.issue} <ExternalLink size={13} aria-hidden="true" />
            </a>
          </div>
        </div>
      </section>
    </div>
  );
}
