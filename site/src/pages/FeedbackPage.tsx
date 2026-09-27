import { useState } from "react";
import {
  ArrowLeft,
  Check,
  Copy,
  Download,
  Flame,
  Sparkles,
  Terminal,
} from "lucide-react";
import { ChunkButton, GithubMark } from "../components/ui";
import { FriedCharacter } from "../components/FriedCharacter";
import { Reveal, useRetro } from "../lib/retro";
import { hrefOf } from "../lib/router";
import { useI18n } from "../i18n";
import { KIT_VERSION, REPO_URL } from "../config";

type ReportType = "works" | "partial" | "bug" | "idea";

interface MostWanted {
  id: string;
  tag: string;
  title: string;
  desc: string;
  cabinet: string;
  os: string;
  hw: string;
}

const MOST_WANTED: MostWanted[] = [
  {
    id: "vpx-3screen",
    tag: "PINBALL",
    title: "VPX · 3 Monitore + NVIDIA",
    desc: "Referenz-Setup für Virtual Pinball. Playfield, Backglass und DMD-Positionierung.",
    cabinet: "Virtual Pinball (3 Screens)",
    os: "Windows 11",
    hw: "NVIDIA GPU, DirectOutput (DOF)",
  },
  {
    id: "sinden-lightgun",
    tag: "LIGHTGUN",
    title: "Sinden Lightgun (im Feinschliff)",
    desc: "Wird aktuell finalisiert. Weißer Rand, Software-Kalibrierung & Recoil-Profile im Test.",
    cabinet: "Lightgun Cabinet",
    os: "Windows 11 / 10",
    hw: "Sinden Lightgun (mit/ohne Recoil)",
  },
  {
    id: "diy-gun4ir-aimtrak",
    tag: "HARDWARE",
    title: "Gun4IR & AimTrak",
    desc: "DIY-Infrarot- und LED-Lightguns. Sensor-Balken, COM-Ports & Tasten-Mapping.",
    cabinet: "Lightgun Cabinet",
    os: "Windows 11",
    hw: "Gun4IR / AimTrak",
  },
  {
    id: "pinup-popper",
    tag: "FRONTEND",
    title: "PinUP Popper + Future Pinball",
    desc: "Alternative Frontends und BAM-Integration jenseits von purem VPX.",
    cabinet: "Virtual Pinball",
    os: "Windows 10 / 11",
    hw: "PinUP Player / Popper, Future Pinball BAM",
  },
  {
    id: "amd-dual",
    tag: "GPU",
    title: "AMD Radeon + 2 Monitore",
    desc: "Pinball auf AMD-Grafikkarten. Bildschirm-Reihenfolge und Eyefinity-Verhalten.",
    cabinet: "Virtual Pinball (2 Screens)",
    os: "Windows 10 / 11",
    hw: "AMD Radeon GPU",
  },
  {
    id: "ollama-local",
    tag: "AGENT / AI",
    title: "Lokale KI (Ollama Qwen / Llama)",
    desc: "Offline-Diagnose und Plan-Generierung mit fagent am geschützten Kabinett.",
    cabinet: "Pinball / Lightgun Cabinet",
    os: "Windows 11",
    hw: "Ollama (qwen2.5:3b / llama3)",
  },
];

export default function FeedbackPage() {
  const { t } = useI18n();
  const { play } = useRetro();

  const [type, setType] = useState<ReportType>("works");
  const [cabinet, setCabinet] = useState("Virtual Pinball");
  const [os, setOs] = useState("Windows 11");
  const [hw, setHw] = useState("");
  const [kitVer, setKitVer] = useState(KIT_VERSION);
  const [title, setTitle] = useState("");
  const [summary, setSummary] = useState("");
  const [expected, setExpected] = useState("");
  const [diagnostics, setDiagnostics] = useState("");
  const [nickname, setNickname] = useState("");
  const [copied, setCopied] = useState(false);

  const applyPrefill = (mw: MostWanted) => {
    play("select");
    setCabinet(mw.cabinet);
    setOs(mw.os);
    setHw(mw.hw);
    if (!title) {
      setTitle(`${mw.title} – Testergebnis`);
    }
  };

  const sanitizeText = (txt: string) => {
    return txt
      .replace(/([A-Za-z]:\\+Users\\+)[^\\/\s"'`]+/gi, "$1{user}")
      .replace(/(\/(?:home|Users)\/)[^/\s"'`]+/g, "$1{user}")
      .replace(/S-1-5-21(?:-\d+){3,4}/g, "{sid}")
      .replace(/\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/g, "{mac}")
      .replace(/\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b/g, "{private-ip}");
  };

  const buildMarkdownReport = () => {
    const typeLabel = {
      works: "Es läuft bei mir (Erfolgsbericht)",
      partial: "Läuft teilweise (Eingrenzung)",
      bug: "Problem / Fehlerbericht",
      idea: "Idee / Wunsch",
    }[type];

    const safeTitle = sanitizeText(title.trim() || `[Feedback] ${cabinet} – ${os}`);
    const safeSummary = sanitizeText(summary.trim() || "Keine Details angegeben.");
    const safeExpected = sanitizeText(expected.trim());
    const safeDiag = sanitizeText(diagnostics.trim());
    const safeNick = nickname.trim() || "Anonym";

    const lines: string[] = [
      `## [Cabinet Report] ${safeTitle}`,
      "",
      `> Eingereicht von **${safeNick}** für Fried's Retro Cabinet Kit.`,
      "",
      "### System & Hardware",
      `| Feld | Angabe |`,
      `| :--- | :--- |`,
      `| **Art der Meldung** | ${typeLabel} |`,
      `| **Cabinet-Typ** | ${cabinet} |`,
      `| **Betriebssystem** | ${os} |`,
      `| **Hardware / Controller** | ${hw || "–"} |`,
      `| **Kit-Version** | v${kitVer} |`,
      "",
      "### Was ist passiert?",
      safeSummary,
      "",
    ];

    if (safeExpected) {
      lines.push("### Was hättest du erwartet?", safeExpected, "");
    }

    if (safeDiag) {
      lines.push(
        "### Diagnose / Log-Ausgabe (Client-anonymisiert)",
        "<details><summary>Log anzeigen</summary>",
        "",
        "```text",
        safeDiag.slice(0, 15000),
        "```",
        "",
        "</details>",
        ""
      );
    }

    lines.push(
      "---",
      `_Erstellt über Retro Cabinet Kit Website · ${new Date().toLocaleDateString("de-DE")}_`
    );

    return lines.join("\n");
  };

  const handleCopy = async () => {
    play("blip");
    const md = buildMarkdownReport();
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(md);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    }
  };

  const handleDownload = () => {
    play("blip");
    const md = buildMarkdownReport();
    const blob = new Blob([md], { type: "text/markdown;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `cabinet-report-${Date.now().toString().slice(-4)}.md`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleOpenGithub = () => {
    play("select");
    const md = buildMarkdownReport();
    const issueTitle = `[Cabinet Report] ${title.trim() || cabinet}`;
    const params = new URLSearchParams({
      title: issueTitle.slice(0, 120),
      body: md.slice(0, 6500),
      labels: `feedback,${type}`,
    });
    window.open(`${REPO_URL}/issues/new?${params.toString()}`, "_blank");
  };

  return (
    <div className="bg-night text-cream">
      {/* Header Shell */}
      <section className="relative overflow-hidden pb-12 pt-12">
        <div className="grid-bg absolute inset-0 opacity-60" />
        <div className="relative mx-auto grid max-w-6xl items-center gap-8 px-5 md:grid-cols-[1fr_auto]">
          <Reveal>
            <a
              href={hrefOf("landing")}
              onClick={() => play("select")}
              className="inline-flex items-center gap-2 font-pixel text-[8px] text-cream/70 hover:text-gold"
            >
              <ArrowLeft size={12} aria-hidden="true" /> {t.guide.back}
            </a>
            <div className="mt-6 font-pixel text-[10px] text-pixel">
              PLAYER 2 · FEEDBACK & TESTMATRIX
            </div>
            <h1 className="mt-3 font-display text-4xl font-black leading-[1.05] text-cream sm:text-6xl">
              System melden & <span className="italic text-gold">Testergebnisse</span>
            </h1>
            <div className="mt-5 h-1.5 w-16 bg-retro" />
            <p className="mt-6 max-w-2xl text-lg leading-relaxed text-cream/85">
              Ein reales Cabinet ist kein steriles Labor: VPX mit 3 Displays, Wiimotes an
              DolphinBars, Sinden-Kameras und Popper-Datenbanken lassen sich nur gemeinsam
              validieren. Sag uns in wenigen Schritten, wie es bei dir läuft – direkt im
              Browser, ohne Login.
            </p>
          </Reveal>
          <div className="hidden md:block">
            <FriedCharacter size="lg" expression="happy" pose="thumbs-up" showCable={false} />
          </div>
        </div>
      </section>

      {/* Main Content */}
      <div className="mx-auto max-w-6xl space-y-12 px-5 pb-20">
        {/* Most Wanted Box */}
        <Reveal>
          <div className="border-[3px] border-night-3 bg-night-2 p-6 shadow-chunk">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b-2 border-night-3 pb-4">
              <div className="flex items-center gap-2.5">
                <Flame size={18} className="text-gold" />
                <span className="font-pixel text-[11px] text-gold">★ MOST WANTED SETUPS ★</span>
                <span className="text-xs text-cream/60">
                  (Klick übernimmt das Setup direkt in das Formular)
                </span>
              </div>
              <span className="border border-pixel/40 bg-screen px-2.5 py-1 font-pixel text-[9px] text-pixel">
                6 PROFILE
              </span>
            </div>

            <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {MOST_WANTED.map((mw) => (
                <button
                  key={mw.id}
                  type="button"
                  onClick={() => applyPrefill(mw)}
                  className="btn-chunk group flex flex-col text-left border-2 border-night-3 bg-night p-4 transition hover:border-gold"
                >
                  <div className="flex items-center justify-between">
                    <span className="font-pixel text-[9px] text-pixel group-hover:text-gold">
                      {mw.tag}
                    </span>
                    <Sparkles size={13} className="text-cream/40 group-hover:text-gold" />
                  </div>
                  <h3 className="mt-2 font-display text-base font-bold text-cream group-hover:text-gold">
                    {mw.title}
                  </h3>
                  <p className="mt-2 text-xs leading-relaxed text-cream/70 flex-1">
                    {mw.desc}
                  </p>
                  <div className="mt-4 border-t border-night-3 pt-2 font-mono text-[10px] text-cream/50">
                    {mw.hw}
                  </div>
                </button>
              ))}
            </div>
          </div>
        </Reveal>

        {/* Wizard Form */}
        <Reveal>
          <div className="border-[3px] border-night-3 bg-night p-6 shadow-chunk-gold">
            <div className="mb-6 flex items-center gap-3">
              <Terminal size={20} className="text-pixel" />
              <h2 className="font-pixel text-[13px] text-cream">
                BERICHT ERFASSEN
              </h2>
            </div>

            {/* Step 1: Type */}
            <div className="mb-8">
              <label className="mb-3 block font-pixel text-[10px] text-gold">
                01 · ART DER MELDUNG
              </label>
              <div className="grid gap-3 sm:grid-cols-4">
                {[
                  { id: "works", label: "Läuft super", tone: "border-pixel text-pixel bg-screen" },
                  { id: "partial", label: "Läuft teilweise", tone: "border-gold text-gold bg-screen" },
                  { id: "bug", label: "Problem / Fehler", tone: "border-retro text-retro bg-screen" },
                  { id: "idea", label: "Idee / Wunsch", tone: "border-cream/40 text-cream bg-screen" },
                ].map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => {
                      play("blip");
                      setType(item.id as ReportType);
                    }}
                    className={`btn-chunk flex items-center justify-center border-2 p-3 font-pixel text-[10px] transition ${
                      type === item.id
                        ? `${item.tone} shadow-chunk-sm scale-[1.02]`
                        : "border-night-3 text-cream/60 hover:border-cream/40"
                    }`}
                  >
                    {type === item.id && <Check size={12} className="mr-1.5" />}
                    {item.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Step 2: System */}
            <div className="mb-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  CABINET-TYP
                </label>
                <select
                  value={cabinet}
                  onChange={(e) => setCabinet(e.target.value)}
                  className="w-full border-2 border-night-3 bg-screen px-3 py-2.5 font-term text-lg text-pixel outline-none focus:border-gold"
                >
                  <option value="Virtual Pinball">Virtual Pinball</option>
                  <option value="Virtual Pinball (3 Screens)">Virtual Pinball (3 Screens)</option>
                  <option value="Virtual Pinball (2 Screens)">Virtual Pinball (2 Screens)</option>
                  <option value="Lightgun Cabinet">Lightgun Cabinet</option>
                  <option value="Pinball + Lightgun Combo">Pinball + Lightgun Combo</option>
                  <option value="Arcade / Desktop Test">Arcade / Desktop Test</option>
                </select>
              </div>

              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  BETRIEBSSYSTEM
                </label>
                <select
                  value={os}
                  onChange={(e) => setOs(e.target.value)}
                  className="w-full border-2 border-night-3 bg-screen px-3 py-2.5 font-term text-lg text-pixel outline-none focus:border-gold"
                >
                  <option value="Windows 11">Windows 11</option>
                  <option value="Windows 10">Windows 10</option>
                  <option value="Linux / Steam Deck">Linux / Steam Deck</option>
                  <option value="macOS">macOS</option>
                </select>
              </div>

              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  HARDWARE / CONTROLLER
                </label>
                <input
                  type="text"
                  value={hw}
                  onChange={(e) => setHw(e.target.value)}
                  placeholder="z. B. Wiimote Mode 4, NVIDIA RTX"
                  className="w-full border-2 border-night-3 bg-screen px-3 py-2 font-term text-lg text-pixel outline-none focus:border-gold"
                />
              </div>

              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  KIT-VERSION
                </label>
                <input
                  type="text"
                  value={kitVer}
                  onChange={(e) => setKitVer(e.target.value)}
                  className="w-full border-2 border-night-3 bg-screen px-3 py-2 font-term text-lg text-pixel outline-none focus:border-gold"
                />
              </div>
            </div>

            {/* Step 3: Details */}
            <div className="mb-8 space-y-4">
              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  TITEL DER MELDUNG
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="z. B. VPX 3-Monitor Setup läuft stabil mit NVIDIA"
                  className="w-full border-2 border-night-3 bg-screen px-3 py-2.5 font-term text-lg text-pixel outline-none focus:border-gold"
                />
              </div>

              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  WAS IST PASSIERT? (BESCHREIBUNG)
                </label>
                <textarea
                  rows={4}
                  value={summary}
                  onChange={(e) => setSummary(e.target.value)}
                  placeholder="Beschreibe kurz in eigenen Worten, was du gemacht hast und wie das Cabinet reagiert hat..."
                  className="w-full border-2 border-night-3 bg-screen p-3 font-term text-lg text-pixel outline-none focus:border-gold"
                />
              </div>

              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  WAS HÄTTEST DU ERWARTET? (OPTIONAL)
                </label>
                <input
                  type="text"
                  value={expected}
                  onChange={(e) => setExpected(e.target.value)}
                  placeholder="z. B. DMD soll auf Monitor 3 starten"
                  className="w-full border-2 border-night-3 bg-screen px-3 py-2 font-term text-lg text-pixel outline-none focus:border-gold"
                />
              </div>

              <div>
                <label className="mb-2 flex items-center justify-between font-pixel text-[9px] text-cream/70">
                  <span>DIAGNOSE / LOG-AUSGABE (AUTOMATISCH ANONYMISIERT)</span>
                  <span className="text-pixel">PFADE WERDEN ZU {"{user}"}</span>
                </label>
                <textarea
                  rows={4}
                  value={diagnostics}
                  onChange={(e) => setDiagnostics(e.target.value)}
                  placeholder="Füge hier optional Log-Zeilen aus Get-CabinetStatus.ps1 oder der Konsole ein..."
                  className="w-full border-2 border-night-3 bg-screen p-3 font-term text-base text-pixel outline-none focus:border-gold"
                  spellCheck={false}
                />
              </div>

              <div>
                <label className="mb-2 block font-pixel text-[9px] text-cream/70">
                  DEIN NICKNAME / FORUM-HANDLE (OPTIONAL)
                </label>
                <input
                  type="text"
                  value={nickname}
                  onChange={(e) => setNickname(e.target.value)}
                  placeholder="z. B. FlipperFriedel"
                  className="w-full max-w-sm border-2 border-night-3 bg-screen px-3 py-2 font-term text-lg text-pixel outline-none focus:border-gold"
                />
              </div>
            </div>

            {/* Step 4: Action Buttons */}
            <div className="border-t-2 border-night-3 pt-6">
              <div className="mb-4 font-pixel text-[10px] text-gold">
                04 · BERICHT ABSENDEN ODER EXPORTIEREN
              </div>
              <div className="flex flex-wrap items-center gap-4">
                <ChunkButton onClick={handleOpenGithub} variant="gold">
                  <GithubMark size={16} /> Auf GitHub melden
                </ChunkButton>
                <ChunkButton onClick={handleCopy} variant="red">
                  {copied ? <Check size={15} /> : <Copy size={15} />}
                  {copied ? "In Zwischenablage kopiert!" : "Report kopieren"}
                </ChunkButton>
                <ChunkButton onClick={handleDownload} variant="ghost-light">
                  <Download size={15} /> Als .md herunterladen
                </ChunkButton>
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </div>
  );
}
