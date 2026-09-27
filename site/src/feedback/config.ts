import type { FeedbackForm } from "./report";

/**
 * ─────────────────────────────────────────────────────────────
 *  FEEDBACK-KONFIGURATION FÜR BETREIBER
 * ─────────────────────────────────────────────────────────────
 *  So aktivierst du den Direktversand (einmalig, ca. 5 Minuten):
 *
 *  1. Trage unten bei `maintainerEmail` deine E-Mail-Adresse ein.
 *  2. Seite neu bauen & auf GitHub Pages deployen.
 *  3. Schicke dir selbst einen Testbericht über das Formular.
 *  4. Bestätige die einmalige Aktivierungs-Mail von FormSubmit.
 *  5. Fertig: Alle weiteren Berichte landen direkt in deinem Postfach.
 *
 *  Hinweise:
 *  - FormSubmit ist kostenlos und braucht kein Konto.
 *  - Alternativ kannst du `customEndpoint` setzen (eigener Webhook
 *    oder Discord-Webhook – Discord wird automatisch erkannt).
 *  - Ohne E-Mail funktioniert die Seite trotzdem: Besucher können
 *    ihren Bericht kopieren, herunterladen oder per Mail-App senden.
 * ─────────────────────────────────────────────────────────────
 */
export const FEEDBACK_CONFIG = {
  /** E-Mail-Adresse für den Direktversand. Leer lassen = Direktversand deaktiviert. */
  maintainerEmail: "",
  /** Optional: eigener Webhook (POST mit JSON). Discord-Webhooks werden automatisch erkannt. */
  customEndpoint: "",
  /** Aktuelle Projektversion (wird in Berichten als Referenz mitgeschickt). */
  projectVersion: "0.1.0",
  agentRepo: "https://github.com/kburna243/frieds-retrogaming-agent",
  kitRepo: "https://github.com/kburna243/frieds-retrogaming-kit",
};

export type MatrixNeed = "gesucht" | "wenig" | "ok";

export interface MatrixItem {
  id: string;
  category: string;
  title: string;
  need: MatrixNeed;
  blurb: string;
  prefill: Partial<FeedbackForm>;
}

export const NEED_META: Record<MatrixNeed, { label: string; hint: string }> = {
  gesucht: { label: "Dringend gesucht", hint: "Dieses System kann der Entwickler selbst nicht prüfen." },
  wenig: { label: "Wenige Berichte", hint: "Erste Erfahrungen da – jede weitere hilft." },
  ok: { label: "Gut abgedeckt", hint: "Läuft stabil – sag trotzdem Bescheid, wenn es bei dir anders ist." },
};

export const MATRIX_CATEGORIES = ["Alle", "Windows", "Lightgun", "Pinball", "KI-Modell", "Emulator"] as const;

/**
 * Testmatrix: Systeme, für die Rückmeldungen gebraucht werden.
 * `prefill` füllt den Assistenten vor – Besucher prüfen nur noch und ergänzen.
 */
export const MATRIX_ITEMS: MatrixItem[] = [
  {
    id: "win11-vpx-nvidia",
    category: "Windows",
    title: "Windows 11 + VPX, 3 Monitore, NVIDIA",
    need: "ok",
    blurb: "Das Referenz-Setup für Virtual Pinball. Läuft es bei dir genauso rund?",
    prefill: { cabinetType: "pinball", os: "win11", screens: "3", gpu: "nvidia" },
  },
  {
    id: "win10-flipper",
    category: "Windows",
    title: "Windows 10 + Flipper-Setup",
    need: "wenig",
    blurb: "Viele Cabinets laufen noch auf Windows 10 – hier fehlen Vergleichswerte.",
    prefill: { cabinetType: "pinball", os: "win10" },
  },
  {
    id: "wiimote-dolphinbar",
    category: "Lightgun",
    title: "Wiimote + DolphinBar (Mode 4)",
    need: "ok",
    blurb: "Das Standard-Lightgun-Setup. Bestätige, dass Treiber und Zielen bei dir passen.",
    prefill: { cabinetType: "lightgun", lightgun: "wiimote", emulators: ["retrobat"] },
  },
  {
    id: "sinden",
    category: "Lightgun",
    title: "Sinden Lightgun",
    need: "gesucht",
    blurb: "Noch nie live getestet – jeder Bericht zählt, egal ob gut oder schlecht.",
    prefill: { cabinetType: "lightgun", lightgun: "sinden" },
  },
  {
    id: "gun4ir",
    category: "Lightgun",
    title: "Gun4IR",
    need: "gesucht",
    blurb: "DIY-Favorit ohne eigene Test-Hardware. Wie schlägt sich der Agent damit?",
    prefill: { cabinetType: "lightgun", lightgun: "gun4ir" },
  },
  {
    id: "aimtrak",
    category: "Lightgun",
    title: "AimTrak",
    need: "gesucht",
    blurb: "Ebenfalls ungeprüft – besonders Kalibrierung und Treiber-Erkennung.",
    prefill: { cabinetType: "lightgun", lightgun: "aimtrak" },
  },
  {
    id: "amd-zwei-monitore",
    category: "Pinball",
    title: "AMD-Grafik + 2 Monitore",
    need: "wenig",
    blurb: "Alternative GPU, kleineres Setup – DMD-Lage und Monitor-Rollen im Fokus.",
    prefill: { cabinetType: "pinball", gpu: "amd", screens: "2" },
  },
  {
    id: "intel-igpu",
    category: "Pinball",
    title: "Intel iGPU, 1 Monitor",
    need: "gesucht",
    blurb: "Sparsames Einstiegs-Cabinet ohne eigene Grafikkarte. Was erkennt der Agent?",
    prefill: { cabinetType: "pinball", gpu: "intel", screens: "1" },
  },
  {
    id: "ollama-qwen",
    category: "KI-Modell",
    title: "Ollama mit Qwen 2.5",
    need: "ok",
    blurb: "Empfohlenes Offline-Modell. Wie gut sind Diagnose und Pläne bei dir?",
    prefill: { model: "ollama-qwen" },
  },
  {
    id: "ollama-llama",
    category: "KI-Modell",
    title: "Ollama mit Llama 3",
    need: "wenig",
    blurb: "Alternative für lokale Diagnose – Vergleichswerte gesucht.",
    prefill: { model: "ollama-llama" },
  },
  {
    id: "cloud-modell",
    category: "KI-Modell",
    title: "Cloud-Modell (OpenAI / Claude)",
    need: "wenig",
    blurb: "Wie gut funktioniert die datengeschützte Cloud-Route in der Praxis?",
    prefill: { model: "cloud" },
  },
  {
    id: "teknoparrot",
    category: "Emulator",
    title: "TeknoParrot",
    need: "wenig",
    blurb: "Arcade-Shooter jenseits von RetroBat – Erkennung und Profile im Fokus.",
    prefill: { cabinetType: "lightgun", emulators: ["teknoparrot"] },
  },
  {
    id: "future-pinball",
    category: "Emulator",
    title: "Future Pinball",
    need: "wenig",
    blurb: "Neben VPX das zweite Flipper-Standbein – wer nutzt es mit dem Agenten?",
    prefill: { cabinetType: "pinball", emulators: ["future-pinball"] },
  },
];

export const QUICK_COMMANDS = {
  doctor: "fagent doctor --transport mcp",
  status: "fagent status",
  version: "fagent --version",
} as const;
