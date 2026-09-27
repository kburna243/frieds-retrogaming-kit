import { FEEDBACK_CONFIG } from "./config";

/* ── Typen ─────────────────────────────────────────────── */

export type FeedbackType = "works" | "partial" | "bug" | "idea";
export type Frequency = "immer" | "oft" | "manchmal" | "einmal" | "unbekannt";

export interface FeedbackForm {
  type: FeedbackType | "";
  cabinetType: string;
  os: string;
  nodeVersion: string;
  fagentVersion: string;
  kitVersion: string;
  screens: string;
  gpu: string;
  lightgun: string;
  emulators: string[];
  model: string;
  title: string;
  summary: string;
  steps: string;
  expected: string;
  actual: string;
  frequency: Frequency | "";
  severity: number;
  doctorOutput: string;
  anonymize: boolean;
  includeBrowserInfo: boolean;
  nickname: string;
  contact: string;
  allowFollowUp: boolean;
  consent: boolean;
}

export interface BrowserMeta {
  browser: string;
  language: string;
  screen: string;
  timezone: string;
}

export interface ReportMeta {
  reportId: string;
  createdAt: string;
  browser: BrowserMeta;
}

export interface SavedReport {
  id: string;
  createdAt: string;
  type: FeedbackType | "";
  title: string;
  status: "gesendet" | "exportiert" | "entwurf";
  markdown: string;
  form: FeedbackForm;
}

export const EMPTY_FORM: FeedbackForm = {
  type: "",
  cabinetType: "",
  os: "",
  nodeVersion: "",
  fagentVersion: "",
  kitVersion: "",
  screens: "",
  gpu: "",
  lightgun: "",
  emulators: [],
  model: "",
  title: "",
  summary: "",
  steps: "",
  expected: "",
  actual: "",
  frequency: "",
  severity: 3,
  doctorOutput: "",
  anonymize: true,
  includeBrowserInfo: true,
  nickname: "",
  contact: "",
  allowFollowUp: true,
  consent: false,
};

/* ── Auswahl-Optionen (einfache Sprache, „Weiß nicht" überall) ── */

export interface PillOption {
  value: string;
  label: string;
}

export const TYPE_META: Record<
  FeedbackType,
  {
    label: string;
    tagline: string;
    titlePlaceholder: string;
    summaryPlaceholder: string;
    summaryHint: string;
    githubLabels: string;
  }
> = {
  works: {
    label: "Es läuft bei mir",
    tagline: "Erfolgsbericht – hilft genauso viel wie Fehlermeldungen.",
    titlePlaceholder: "z. B. VPX mit 3 Monitoren läuft stabil auf Windows 11",
    summaryPlaceholder: "Was hast du ausprobiert? Was hat funktioniert? Welche Spiele oder Tische hast du getestet?",
    summaryHint: "Kurz beschreiben, was du getestet hast – 2 bis 3 Sätze genügen.",
    githubLabels: "feedback,test-report",
  },
  partial: {
    label: "Läuft teilweise",
    tagline: "Manches geht, manches nicht – wir grenzen es gemeinsam ein.",
    titlePlaceholder: "z. B. Lightgun zielt in Spiel A, aber nicht in Spiel B",
    summaryPlaceholder: "Was funktioniert? Was funktioniert nicht? Wo ist der Unterschied (Spiel, Emulator, Controller)?",
    summaryHint: "Am wertvollsten: Was geht – und was genau geht nicht?",
    githubLabels: "feedback,test-report",
  },
  bug: {
    label: "Etwas geht nicht",
    tagline: "Problem melden – Schritt für Schritt, ganz ohne Fachwörter.",
    titlePlaceholder: "z. B. Zweite Wiimote zielt daneben",
    summaryPlaceholder: "Was wolltest du tun? Was ist stattdessen passiert? Gibt es eine Fehlermeldung (abschreiben genügt)?",
    summaryHint: "Einfach in eigenen Worten erzählen – Fachbegriffe sind nicht nötig.",
    githubLabels: "feedback,bug",
  },
  idea: {
    label: "Idee / Wunsch",
    tagline: "Was soll der Agent als Nächstes können?",
    titlePlaceholder: "z. B. Sinden-Lightgun automatisch erkennen",
    summaryPlaceholder: "Was wünschst du dir? Wobei würde es dir am Cabinet helfen?",
    summaryHint: "Auch kleine Wünsche sind willkommen – jede Idee wird gelesen.",
    githubLabels: "feedback,enhancement",
  },
};

export const CABINET_OPTIONS: PillOption[] = [
  { value: "pinball", label: "Virtual Pinball" },
  { value: "lightgun", label: "Lightgun / RetroBat" },
  { value: "beides", label: "Beides" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const OS_OPTIONS: PillOption[] = [
  { value: "win11", label: "Windows 11" },
  { value: "win10", label: "Windows 10" },
  { value: "linux", label: "Linux (Test)" },
  { value: "macos", label: "macOS (Test)" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const NODE_OPTIONS: PillOption[] = [
  { value: "node24", label: "Node 24 (empfohlen)" },
  { value: "node22", label: "Node 22" },
  { value: "node20", label: "Node 20 / älter" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const SCREEN_OPTIONS: PillOption[] = [
  { value: "1", label: "1 Monitor" },
  { value: "2", label: "2 Monitore" },
  { value: "3", label: "3 Monitore" },
  { value: "mehr", label: "Mehr als 3" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const GPU_OPTIONS: PillOption[] = [
  { value: "nvidia", label: "NVIDIA" },
  { value: "amd", label: "AMD" },
  { value: "intel", label: "Intel (onboard)" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const LIGHTGUN_OPTIONS: PillOption[] = [
  { value: "wiimote", label: "Wiimote + DolphinBar" },
  { value: "sinden", label: "Sinden" },
  { value: "gun4ir", label: "Gun4IR" },
  { value: "aimtrak", label: "AimTrak" },
  { value: "keine", label: "Keine Lightgun" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const EMULATOR_OPTIONS: PillOption[] = [
  { value: "vpx", label: "VPX" },
  { value: "future-pinball", label: "Future Pinball" },
  { value: "popper", label: "PinUP Popper" },
  { value: "retrobat", label: "RetroBat" },
  { value: "teknoparrot", label: "TeknoParrot" },
  { value: "demul", label: "Demul" },
];

export const MODEL_OPTIONS: PillOption[] = [
  { value: "ollama-qwen", label: "Ollama · Qwen 2.5" },
  { value: "ollama-llama", label: "Ollama · Llama 3" },
  { value: "ollama-mistral", label: "Ollama · Mistral" },
  { value: "cloud", label: "Cloud (OpenAI / Claude)" },
  { value: "keins", label: "Noch keins" },
  { value: "weiss-nicht", label: "Weiß nicht" },
];

export const FREQUENCY_OPTIONS: PillOption[] = [
  { value: "immer", label: "Immer" },
  { value: "oft", label: "Oft" },
  { value: "manchmal", label: "Manchmal" },
  { value: "einmal", label: "Einmal bisher" },
  { value: "unbekannt", label: "Weiß nicht" },
];

export const SEVERITY_LABELS = [
  "",
  "Nur ein Schönheitsfehler",
  "Kleines Problem",
  "Stört deutlich",
  "Fast nichts geht mehr",
  "Nichts geht mehr",
];

export function labelFor(options: PillOption[], value: string): string {
  if (!value) return "–";
  return options.find((o) => o.value === value)?.label ?? value;
}

/* ── IDs, Browser-Infos, Anonymisierung ─────────────────── */

export function generateReportId(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let suffix = "";
  const random = crypto.getRandomValues(new Uint8Array(4));
  for (const byte of random) suffix += chars[byte % chars.length];
  return `FR-${new Date().getFullYear()}-${suffix}`;
}

export function formatDateTime(iso: string): string {
  try {
    return new Date(iso).toLocaleString("de-DE", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

export function collectBrowserInfo(): BrowserMeta {
  if (typeof window === "undefined" || typeof navigator === "undefined") {
    return { browser: "–", language: "–", screen: "–", timezone: "–" };
  }
  const ua = navigator.userAgent ?? "";
  let browser = "Unbekannter Browser";
  if (/Edg\//.test(ua)) browser = "Microsoft Edge";
  else if (/Chrome\//.test(ua)) browser = "Chrome";
  else if (/Firefox\//.test(ua)) browser = "Firefox";
  else if (/Safari\//.test(ua)) browser = "Safari";
  let screen = "–";
  try {
    screen = `${window.screen.width}×${window.screen.height} px`;
  } catch {
    /* ignore */
  }
  let timezone = "–";
  try {
    timezone = Intl.DateTimeFormat().resolvedOptions().timeZone ?? "–";
  } catch {
    /* ignore */
  }
  return {
    browser,
    language: navigator.language ?? "–",
    screen,
    timezone,
  };
}

/** Maskiert Benutzernamen, Pfade, SIDs, IPs und E-Mails – läuft komplett lokal. */
export function anonymizeText(input: string): string {
  if (!input) return input;
  return input
    .replace(/C:\\Users\\([^\\/\s"']+)/gi, "C:\\Users\\[NAME]")
    .replace(/\/home\/([^/\s"']+)/g, "/home/[NAME]")
    .replace(/\/Users\/([^/\s"']+)/g, "/Users/[NAME]")
    .replace(/S-1-5-21(?:-\d+)+/g, "[WINDOWS-SID]")
    .replace(/\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/g, "[MAC]")
    .replace(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g, "[IP]")
    .replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, "[E-MAIL]")
    .replace(/discord\.gg\/\S+/gi, "[DISCORD-LINK]");
}

export function findSensitiveHints(input: string): string[] {
  const hints: string[] = [];
  if (!input) return hints;
  if (/C:\\Users\\[^\\/\s"']+/i.test(input)) hints.push("Windows-Benutzername im Pfad");
  if (/\bS-1-5-21(?:-\d+)+/.test(input)) hints.push("Windows-SID");
  if (/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/.test(input)) hints.push("IP-Adresse");
  if (/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/.test(input)) hints.push("E-Mail-Adresse");
  return hints;
}

/* ── Bericht erzeugen ───────────────────────────────────── */

function typeLabel(type: FeedbackType | ""): string {
  return type ? TYPE_META[type].label : "Feedback";
}

function systemLine(form: FeedbackForm): string {
  const parts = [
    labelFor(CABINET_OPTIONS, form.cabinetType),
    labelFor(OS_OPTIONS, form.os),
    form.screens ? `${labelFor(SCREEN_OPTIONS, form.screens)}` : "",
    labelFor(GPU_OPTIONS, form.gpu),
    form.lightgun ? labelFor(LIGHTGUN_OPTIONS, form.lightgun) : "",
  ].filter((p) => p && p !== "–");
  return parts.length > 0 ? parts.join(" · ") : "–";
}

function emulatorLine(form: FeedbackForm): string {
  if (form.emulators.length === 0) return "–";
  return form.emulators.map((e) => labelFor(EMULATOR_OPTIONS, e)).join(", ");
}

export function buildMarkdown(form: FeedbackForm, meta: ReportMeta): string {
  const lines: string[] = [];
  lines.push(`# Feedback ${meta.reportId} – ${typeLabel(form.type)}`);
  lines.push("");
  lines.push(`- **Bericht-ID:** ${meta.reportId}`);
  lines.push(`- **Datum:** ${formatDateTime(meta.createdAt)} Uhr`);
  lines.push(`- **Art:** ${typeLabel(form.type)}`);
  lines.push(`- **System:** ${systemLine(form)}`);
  lines.push(`- **Spitzname:** ${form.nickname.trim() || "– (anonym)"}`);
  lines.push(`- **Rückfragen erlaubt:** ${form.allowFollowUp ? "Ja" : "Nein"}`);
  if (form.contact.trim()) lines.push(`- **Kontakt:** ${form.contact.trim()}`);
  lines.push("");
  lines.push(`## Titel`);
  lines.push("");
  lines.push(form.title.trim() || "–");
  lines.push("");
  lines.push(`## Beschreibung`);
  lines.push("");
  lines.push(form.summary.trim() || "–");
  lines.push("");
  if (form.steps.trim()) {
    lines.push(`## Schritte zum Nachstellen`);
    lines.push("");
    lines.push(form.steps.trim());
    lines.push("");
  }
  if (form.expected.trim() || form.actual.trim()) {
    lines.push(`## Erwartet vs. tatsächlich`);
    lines.push("");
    if (form.expected.trim()) lines.push(`**Erwartet:** ${form.expected.trim()}`);
    if (form.actual.trim()) lines.push(`**Tatsächlich:** ${form.actual.trim()}`);
    lines.push("");
  }
  if (form.type === "bug" || form.type === "partial") {
    lines.push(`## Einordnung`);
    lines.push("");
    lines.push(`- **Häufigkeit:** ${form.frequency ? labelFor(FREQUENCY_OPTIONS, form.frequency) : "–"}`);
    lines.push(`- **Schwere:** ${form.severity}/5 – ${SEVERITY_LABELS[form.severity]}`);
    lines.push("");
  }
  lines.push(`## System im Detail`);
  lines.push("");
  lines.push(`| Feld | Angabe |`);
  lines.push(`| ---- | ------ |`);
  lines.push(`| Cabinet | ${labelFor(CABINET_OPTIONS, form.cabinetType)} |`);
  lines.push(`| Betriebssystem | ${labelFor(OS_OPTIONS, form.os)} |`);
  lines.push(`| Node.js | ${labelFor(NODE_OPTIONS, form.nodeVersion)} |`);
  lines.push(`| fagent-Version | ${form.fagentVersion.trim() || "–"} |`);
  lines.push(`| Kit-Version | ${form.kitVersion.trim() || "–"} |`);
  lines.push(`| Monitore | ${labelFor(SCREEN_OPTIONS, form.screens)} |`);
  lines.push(`| Grafik | ${labelFor(GPU_OPTIONS, form.gpu)} |`);
  lines.push(`| Lightgun | ${labelFor(LIGHTGUN_OPTIONS, form.lightgun)} |`);
  lines.push(`| Emulatoren | ${emulatorLine(form)} |`);
  lines.push(`| KI-Modell | ${labelFor(MODEL_OPTIONS, form.model)} |`);
  lines.push("");
  if (form.doctorOutput.trim()) {
    const output = form.anonymize ? anonymizeText(form.doctorOutput) : form.doctorOutput;
    lines.push(`## Diagnose-Ausgabe`);
    lines.push("");
    lines.push(`> Anonymisiert: ${form.anonymize ? "Ja (lokal maskiert)" : "Nein – bewusst unmaskiert mitgeschickt"}`);
    lines.push("");
    lines.push("```text");
    lines.push(output.trim());
    lines.push("```");
    lines.push("");
  }
  if (form.includeBrowserInfo) {
    lines.push(`## Browser-Infos (automatisch, unbedenklich)`);
    lines.push("");
    lines.push(`- Browser: ${meta.browser.browser}`);
    lines.push(`- Sprache: ${meta.browser.language}`);
    lines.push(`- Bildschirm: ${meta.browser.screen}`);
    lines.push(`- Zeitzone: ${meta.browser.timezone}`);
    lines.push("");
  }
  lines.push(`---`);
  lines.push(
    `Erstellt mit dem Feedback-Assistenten der Projekt-Homepage (v${FEEDBACK_CONFIG.projectVersion}) – kein GitHub-Account nötig.`
  );
  return lines.join("\n");
}

/** Kompakte Fassung zum Einfügen in Discord, Forum oder E-Mail. */
export function buildShort(form: FeedbackForm, meta: ReportMeta): string {
  const out: string[] = [];
  out.push(`[${meta.reportId}] ${typeLabel(form.type)}: ${form.title.trim() || "(ohne Titel)"}`);
  out.push(`System: ${systemLine(form)}`);
  if (form.fagentVersion.trim() || form.kitVersion.trim()) {
    out.push(
      `Versionen: fagent ${form.fagentVersion.trim() || "?"} / Kit ${form.kitVersion.trim() || "?"}`
    );
  }
  out.push("");
  out.push(form.summary.trim() || "–");
  if (form.type === "bug" || form.type === "partial") {
    out.push("");
    out.push(
      `Häufigkeit: ${form.frequency ? labelFor(FREQUENCY_OPTIONS, form.frequency) : "?"} · Schwere: ${form.severity}/5`
    );
  }
  if (form.nickname.trim()) out.push(`Von: ${form.nickname.trim()}`);
  return out.join("\n");
}

export function buildMailto(
  email: string,
  form: FeedbackForm,
  meta: ReportMeta
): { href: string; tooLong: boolean } {
  const subject = `[Feedback ${meta.reportId}] ${typeLabel(form.type)}: ${form.title.trim() || "Ohne Titel"}`.slice(0, 140);
  const body = buildMarkdown(form, meta);
  const href = `mailto:${email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  return { href, tooLong: body.length > 6000 };
}

export function buildGithubIssueUrl(form: FeedbackForm, meta: ReportMeta): string {
  const title = `[Feedback ${meta.reportId}] ${form.title.trim() || typeLabel(form.type)}`.slice(0, 140);
  let body = buildMarkdown(form, meta);
  if (body.length > 7500) {
    body = `${body.slice(0, 7300)}\n\n… (gekürzt für GitHub – Volltext bitte als Datei anhängen)`;
  }
  const labels = form.type ? TYPE_META[form.type].githubLabels : "feedback";
  const params = new URLSearchParams({ title, body, labels });
  return `${FEEDBACK_CONFIG.agentRepo}/issues/new?${params.toString()}`;
}

/* ── Vollständigkeit & Validierung ──────────────────────── */

export interface Completeness {
  score: number;
  missing: { step: number; label: string }[];
}

export function computeCompleteness(form: FeedbackForm): Completeness {
  const missing: Completeness["missing"] = [];
  let score = 0;
  if (form.type) score += 12;
  else missing.push({ step: 0, label: "Art der Meldung wählen" });
  if (form.title.trim().length >= 8) score += 16;
  else missing.push({ step: 2, label: "Titel mit mindestens 8 Zeichen" });
  if (form.summary.trim().length >= 20) score += 22;
  else missing.push({ step: 2, label: "Beschreibung mit mindestens 20 Zeichen" });
  if (form.cabinetType) score += 8;
  else missing.push({ step: 1, label: "Cabinet-Typ angeben (oder „Weiß nicht“)" });
  if (form.os) score += 8;
  else missing.push({ step: 1, label: "Betriebssystem angeben (oder „Weiß nicht“)" });
  if (form.nodeVersion || form.fagentVersion.trim() || form.kitVersion.trim()) score += 8;
  else missing.push({ step: 1, label: "Mindestens eine Versionsangabe" });
  if (form.type === "bug" || form.type === "partial") {
    if (form.frequency) score += 6;
    else missing.push({ step: 2, label: "Häufigkeit wählen" });
    if (form.steps.trim() || form.expected.trim() || form.actual.trim()) score += 10;
    else missing.push({ step: 2, label: "Schritte oder Erwartet/Tatsächlich ergänzen" });
  } else {
    score += 16;
  }
  if (form.doctorOutput.trim()) score += 10;
  else if (form.type === "bug" || form.type === "partial")
    missing.push({ step: 3, label: "Diagnose-Ausgabe einfügen (optional, aber hilfreich)" });
  else score += 0;
  return { score: Math.min(100, score), missing };
}

export function validateStep(form: FeedbackForm, step: number): string[] {
  const errors: string[] = [];
  if (step === 0 && !form.type) errors.push("Bitte wähle, was du melden möchtest.");
  if (step === 2) {
    if (form.title.trim().length < 8) errors.push("Bitte gib einen Titel mit mindestens 8 Zeichen ein.");
    if (form.summary.trim().length < 20)
      errors.push("Bitte beschreibe dein Anliegen mit mindestens 20 Zeichen.");
  }
  if (step === 4 && form.contact.trim() && form.contact.trim().length < 3) {
    errors.push("Die Kontaktangabe sieht zu kurz aus – oder lass das Feld einfach leer.");
  }
  return errors;
}

/* ── Lokale Ablage („Meine Meldungen") ──────────────────── */

const STORAGE_KEY = "fagent-feedback-reports-v1";
const TEST_EMAIL_KEY = "fagent-feedback-test-email";

export function loadReports(): SavedReport[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as SavedReport[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function persistReport(report: SavedReport): SavedReport[] {
  const current = loadReports().filter((r) => r.id !== report.id);
  const next = [report, ...current].slice(0, 50);
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    /* Speicher voll oder blockiert – Bericht bleibt trotzdem kopierbar */
  }
  return next;
}

export function removeReport(id: string): SavedReport[] {
  const next = loadReports().filter((r) => r.id !== id);
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    /* ignore */
  }
  return next;
}

export function getTestEmailOverride(): string {
  try {
    return (localStorage.getItem(TEST_EMAIL_KEY) ?? "").trim();
  } catch {
    return "";
  }
}

export function setTestEmailOverride(email: string): void {
  try {
    if (email.trim()) localStorage.setItem(TEST_EMAIL_KEY, email.trim());
    else localStorage.removeItem(TEST_EMAIL_KEY);
  } catch {
    /* ignore */
  }
}

export function getEffectiveEmail(): string {
  return getTestEmailOverride() || FEEDBACK_CONFIG.maintainerEmail.trim();
}

/* ── Versand ────────────────────────────────────────────── */

export async function sendViaFormSubmit(
  email: string,
  form: FeedbackForm,
  meta: ReportMeta,
  markdown: string
): Promise<void> {
  const response = await fetch(`https://formsubmit.co/ajax/${encodeURIComponent(email)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      _subject: `[Feedback ${meta.reportId}] ${typeLabel(form.type)}: ${form.title.trim() || "Ohne Titel"}`,
      _template: "table",
      _captcha: "false",
      Bericht_ID: meta.reportId,
      Art: typeLabel(form.type),
      Titel: form.title.trim() || "–",
      System: systemLine(form),
      Beschreibung: form.summary.trim() || "–",
      _replyto: form.contact.includes("@") ? form.contact.trim() : undefined,
      Volltext_Markdown: markdown,
    }),
  });
  if (!response.ok) throw new Error(`FormSubmit antwortete mit Status ${response.status}`);
}

export async function sendViaCustomEndpoint(
  endpoint: string,
  form: FeedbackForm,
  meta: ReportMeta,
  markdown: string
): Promise<void> {
  const isDiscord = endpoint.includes("discord.com/api/webhooks");
  const payload = isDiscord
    ? {
        content: `**[${meta.reportId}] ${typeLabel(form.type)}:** ${form.title.trim() || "(ohne Titel)"}\nSystem: ${systemLine(form)}\n\n${(form.summary.trim() || "–").slice(0, 1500)}`.slice(0, 1900),
      }
    : {
        reportId: meta.reportId,
        createdAt: meta.createdAt,
        type: form.type,
        title: form.title,
        summary: form.summary,
        system: systemLine(form),
        markdown,
        nickname: form.nickname,
        contact: form.contact,
        allowFollowUp: form.allowFollowUp,
      };
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error(`Endpunkt antwortete mit Status ${response.status}`);
}

/* ── Datei & Zwischenablage ─────────────────────────────── */

export function downloadFile(filename: string, content: string, mime = "text/markdown"): void {
  const blob = new Blob([content], { type: `${mime};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.setTimeout(() => URL.revokeObjectURL(url), 1500);
}

export async function copyText(text: string): Promise<void> {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }
  const area = document.createElement("textarea");
  area.value = text;
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  document.execCommand("copy");
  document.body.removeChild(area);
}
