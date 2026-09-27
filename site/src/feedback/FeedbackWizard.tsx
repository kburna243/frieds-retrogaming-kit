import { useEffect, useMemo, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import {
  Bug,
  Check,
  ChevronLeft,
  ChevronRight,
  Copy,
  Download,
  ExternalLink,
  Eye,
  FileText,
  FlaskConical,
  Gamepad2,
  Info,
  Lightbulb,
  Mail,
  RotateCcw,
  Send,
  ShieldCheck,
  Trophy,
  X,
} from "lucide-react";
import { FEEDBACK_CONFIG, QUICK_COMMANDS } from "./config";
import {
  CABINET_OPTIONS,
  EMULATOR_OPTIONS,
  EMPTY_FORM,
  FREQUENCY_OPTIONS,
  GPU_OPTIONS,
  LIGHTGUN_OPTIONS,
  MODEL_OPTIONS,
  NODE_OPTIONS,
  OS_OPTIONS,
  SCREEN_OPTIONS,
  SEVERITY_LABELS,
  TYPE_META,
  anonymizeText,
  buildGithubIssueUrl,
  buildMailto,
  buildMarkdown,
  buildShort,
  collectBrowserInfo,
  computeCompleteness,
  copyText,
  downloadFile,
  findSensitiveHints,
  generateReportId,
  getEffectiveEmail,
  labelFor,
  persistReport,
  sendViaCustomEndpoint,
  sendViaFormSubmit,
  validateStep,
  type BrowserMeta,
  type FeedbackForm,
  type FeedbackType,
  type Frequency,
  type PillOption,
  type ReportMeta,
} from "./report";

const STEPS = [
  "Deine Meldung",
  "Dein System",
  "Was ist passiert?",
  "Diagnose",
  "Kontakt",
  "Prüfen & Senden",
];

const TYPE_ICONS: Record<FeedbackType, typeof Bug> = {
  works: Trophy,
  partial: FlaskConical,
  bug: Bug,
  idea: Lightbulb,
};

interface WizardProps {
  initialForm: FeedbackForm;
  initialStep: number;
  matrixHint: string | null;
  onClose: () => void;
  onSaved: () => void;
}

/* ── Kleine Bausteine ─────────────────────────────────── */

function FieldLabel({ children, optional = false }: { children: string; optional?: boolean }) {
  return (
    <p className="fb-field-label">
      {children}
      {optional && <span className="fb-optional">optional</span>}
    </p>
  );
}

function PillGroup({
  label,
  hint,
  options,
  value,
  onChange,
  optional = true,
}: {
  label: string;
  hint?: string;
  options: PillOption[];
  value: string;
  onChange: (value: string) => void;
  optional?: boolean;
}) {
  return (
    <div className="fb-field">
      <FieldLabel optional={optional}>{label}</FieldLabel>
      {hint && <p className="fb-hint">{hint}</p>}
      <div className="fb-pills" role="radiogroup" aria-label={label}>
        {options.map((option) => (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={value === option.value}
            className={`fb-pill${value === option.value ? " is-selected" : ""}`}
            onClick={() => onChange(option.value)}
          >
            {value === option.value && <Check size={13} />}
            {option.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function ToggleRow({
  checked,
  onChange,
  title,
  description,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  title: string;
  description: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      className={`fb-toggle${checked ? " is-on" : ""}`}
      onClick={() => onChange(!checked)}
    >
      <span className="fb-toggle-box" aria-hidden="true">
        {checked && <Check size={14} />}
      </span>
      <span className="fb-toggle-text">
        <strong>{title}</strong>
        <small>{description}</small>
      </span>
    </button>
  );
}

/* ── Assistent ────────────────────────────────────────── */

export default function FeedbackWizard({ initialForm, initialStep, matrixHint, onClose, onSaved }: WizardProps) {
  const reducedMotion = useReducedMotion();
  const [form, setForm] = useState<FeedbackForm>(initialForm);
  const [step, setStep] = useState(initialStep);
  const [errors, setErrors] = useState<string[]>([]);
  const [previewTab, setPreviewTab] = useState<"uebersicht" | "markdown" | "kurz">("uebersicht");
  const [sendState, setSendState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [sendError, setSendError] = useState("");
  const [successMode, setSuccessMode] = useState<"sent" | "saved" | null>(null);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [showAnonPreview, setShowAnonPreview] = useState(false);
  const [meta, setMeta] = useState<ReportMeta>(() => ({
    reportId: generateReportId(),
    createdAt: new Date().toISOString(),
    browser: collectBrowserInfo(),
  }));

  const set = <K extends keyof FeedbackForm>(key: K, value: FeedbackForm[K]) => {
    setForm((current) => ({ ...current, [key]: value }));
    setErrors([]);
  };

  const toggleEmulator = (value: string) => {
    setForm((current) => ({
      ...current,
      emulators: current.emulators.includes(value)
        ? current.emulators.filter((e) => e !== value)
        : [...current.emulators, value],
    }));
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = previous;
    };
  }, [onClose]);

  const markdown = useMemo(() => buildMarkdown(form, meta), [form, meta]);
  const shortText = useMemo(() => buildShort(form, meta), [form, meta]);
  const completeness = useMemo(() => computeCompleteness(form), [form]);
  const effectiveEmail = getEffectiveEmail();
  const customEndpoint = FEEDBACK_CONFIG.customEndpoint.trim();
  const directAvailable = effectiveEmail !== "" || customEndpoint !== "";
  const sensitiveHints = useMemo(() => findSensitiveHints(form.doctorOutput), [form.doctorOutput]);

  const goTo = (next: number) => {
    setErrors([]);
    setStep(Math.max(0, Math.min(STEPS.length - 1, next)));
  };

  const goNext = () => {
    const stepErrors = validateStep(form, step);
    if (stepErrors.length > 0) {
      setErrors(stepErrors);
      return;
    }
    goTo(step + 1);
  };

  const handleCopy = async (text: string, key: string) => {
    try {
      await copyText(text);
      setCopiedKey(key);
      window.setTimeout(() => setCopiedKey((current) => (current === key ? null : current)), 2200);
    } catch {
      setErrors(["Kopieren hat nicht geklappt – bitte Text manuell markieren und kopieren."]);
    }
  };

  const saveDraft = (status: "exportiert" | "entwurf") => {
    persistReport({
      id: meta.reportId,
      createdAt: meta.createdAt,
      type: form.type,
      title: form.title.trim() || "(ohne Titel)",
      status,
      markdown,
      form,
    });
    onSaved();
  };

  const basicsValid = () => {
    const problems = [...validateStep(form, 0), ...validateStep(form, 2), ...validateStep(form, 4)];
    if (problems.length === 0) return true;
    setErrors(problems);
    if (!form.type || form.title.trim().length < 8 || form.summary.trim().length < 20) {
      goTo(!form.type ? 0 : 2);
    } else {
      goTo(4);
    }
    return false;
  };

  const handleDirectSend = async () => {
    if (!basicsValid()) return;
    if (!form.consent) {
      setErrors(["Bitte setze oben den Haken bei der Einwilligung, damit wir deinen Bericht senden dürfen."]);
      return;
    }
    setSendState("sending");
    setSendError("");
    try {
      if (customEndpoint) {
        await sendViaCustomEndpoint(customEndpoint, form, meta, markdown);
      } else {
        await sendViaFormSubmit(effectiveEmail, form, meta, markdown);
      }
      persistReport({
        id: meta.reportId,
        createdAt: meta.createdAt,
        type: form.type,
        title: form.title.trim() || "(ohne Titel)",
        status: "gesendet",
        markdown,
        form,
      });
      onSaved();
      setSendState("sent");
      setSuccessMode("sent");
    } catch (error) {
      setSendState("error");
      setSendError(
        error instanceof Error
          ? error.message
          : "Unbekannter Fehler beim Senden. Bitte eine der Alternativen unten nutzen."
      );
    }
  };

  const handleMailto = () => {
    if (!basicsValid() || !effectiveEmail) return;
    const { href, tooLong } = buildMailto(effectiveEmail, form, meta);
    saveDraft("exportiert");
    if (tooLong) {
      setErrors([
        "Dein Bericht ist sehr lang – falls das Mail-Programm ihn abschneidet, lade stattdessen die Datei herunter und hänge sie an.",
      ]);
    }
    window.location.href = href;
  };

  const handleDownloadMarkdown = () => {
    downloadFile(`${meta.reportId}-feedback.md`, markdown);
    saveDraft("exportiert");
  };

  const handleDownloadJson = () => {
    const payload = JSON.stringify(
      { reportId: meta.reportId, createdAt: meta.createdAt, browser: meta.browser, form },
      null,
      2
    );
    downloadFile(`${meta.reportId}-feedback.json`, payload, "application/json");
    saveDraft("exportiert");
  };

  const handleGithub = () => {
    if (!basicsValid()) return;
    saveDraft("exportiert");
    window.open(buildGithubIssueUrl(form, meta), "_blank", "noopener,noreferrer");
  };

  const handleSaveOnly = () => {
    saveDraft("entwurf");
    setSuccessMode("saved");
  };

  const handleRestart = () => {
    setForm({ ...EMPTY_FORM });
    setMeta({ reportId: generateReportId(), createdAt: new Date().toISOString(), browser: collectBrowserInfo() });
    setStep(0);
    setErrors([]);
    setSendState("idle");
    setSuccessMode(null);
    setPreviewTab("uebersicht");
  };

  const showMyReports = () => {
    onClose();
    window.setTimeout(() => {
      document.getElementById("meine-meldungen")?.scrollIntoView({ behavior: "smooth" });
    }, 80);
  };

  const typeMeta = form.type ? TYPE_META[form.type] : null;

  return (
    <motion.div
      className="fb-modal-overlay"
      initial={reducedMotion ? false : { opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={reducedMotion ? { opacity: 0 } : { opacity: 0 }}
      onClick={onClose}
    >
      <motion.div
        className="fb-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Feedback-Assistent"
        initial={reducedMotion ? false : { opacity: 0, y: 44, scale: 0.985 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={reducedMotion ? { opacity: 0 } : { opacity: 0, y: 30, scale: 0.985 }}
        transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="fb-modal-header">
          <div className="fb-modal-title">
            <span className="fb-modal-kicker">
              <Gamepad2 size={15} /> FEEDBACK-ASSISTENT · KEIN KONTO NÖTIG
            </span>
            <h2>{successMode ? "Geschafft!" : `Schritt ${step + 1} von ${STEPS.length}: ${STEPS[step]}`}</h2>
          </div>
          <button type="button" className="fb-modal-close" onClick={onClose} aria-label="Assistent schließen">
            <X size={20} />
          </button>
        </header>

        {!successMode && (
          <div className="fb-modal-progress" aria-hidden="true">
            <div className="fb-modal-progress-bar" style={{ width: `${((step + 1) / STEPS.length) * 100}%` }} />
          </div>
        )}

        {!successMode && (
          <nav className="fb-stepper" aria-label="Fortschritt">
            {STEPS.map((label, index) => (
              <button
                key={label}
                type="button"
                className={`fb-step-dot${index === step ? " is-current" : ""}${index < step ? " is-done" : ""}`}
                onClick={() => goTo(index)}
                aria-label={`Zu Schritt ${index + 1}: ${label}`}
                aria-current={index === step ? "step" : undefined}
              >
                <span>{index < step ? <Check size={12} /> : `0${index + 1}`}</span>
                <small>{label}</small>
              </button>
            ))}
          </nav>
        )}

        <div className="fb-modal-body">
          {matrixHint && !successMode && (
            <p className="fb-matrix-hint">
              <Info size={15} /> Vorausgefüllt aus der Testmatrix: <strong>{matrixHint}</strong> – bitte kurz prüfen.
            </p>
          )}

          {errors.length > 0 && !successMode && (
            <div className="fb-errors" role="alert">
              {errors.map((error) => (
                <p key={error}>{error}</p>
              ))}
            </div>
          )}

          <AnimatePresence mode="wait">
            {successMode ? (
              <motion.div
                key="success"
                initial={reducedMotion ? false : { opacity: 0, y: 14 }}
                animate={{ opacity: 1, y: 0 }}
                exit={reducedMotion ? { opacity: 0 } : { opacity: 0 }}
                transition={{ duration: 0.25 }}
              >
                <div className="fb-success">
                  <span className="fb-success-icon">
                    <Check size={30} />
                  </span>
                  <h3>
                    {successMode === "sent"
                      ? "Dein Bericht ist unterwegs. Danke!"
                      : "Dein Bericht ist gemerkt."}
                  </h3>
                  <p>
                    {successMode === "sent"
                      ? "Er wurde direkt an den Entwickler geschickt. Bei Rückfragen meldet er sich – falls du Kontakt angegeben hast."
                      : "Er liegt jetzt unter „Meine Meldungen“ auf diesem Gerät. Du kannst ihn dort jederzeit kopieren, laden oder doch noch senden."}
                  </p>
                  <div className="fb-report-id">
                    <span>DEINE BERICHT-ID</span>
                    <strong>{meta.reportId}</strong>
                    <button type="button" onClick={() => handleCopy(meta.reportId, "report-id")}>
                      <Copy size={15} /> {copiedKey === "report-id" ? "Kopiert!" : "Kopieren"}
                    </button>
                  </div>
                  <ol className="fb-next-steps">
                    <li>
                      <strong>1. Lesen & einordnen</strong>
                      <span>Der Entwickler sichtet jede Meldung persönlich.</span>
                    </li>
                    <li>
                      <strong>2. Nachfragen (optional)</strong>
                      <span>Nur wenn du Kontakt hinterlassen hast – sonst bleibt alles anonym.</span>
                    </li>
                    <li>
                      <strong>3. Verbessern</strong>
                      <span>Dein System hilft, den Agenten für alle stabiler zu machen.</span>
                    </li>
                  </ol>
                  <div className="fb-success-actions">
                    <button type="button" className="fb-btn fb-btn-primary" onClick={showMyReports}>
                      Meine Meldungen ansehen
                    </button>
                    <button type="button" className="fb-btn fb-btn-ghost" onClick={handleRestart}>
                      <RotateCcw size={16} /> Weitere Meldung
                    </button>
                    <button type="button" className="fb-btn fb-btn-ghost" onClick={onClose}>
                      Schließen
                    </button>
                  </div>
                </div>
              </motion.div>
            ) : (
              <motion.div
                key={step}
                initial={reducedMotion ? false : { opacity: 0, x: 22 }}
                animate={{ opacity: 1, x: 0 }}
                exit={reducedMotion ? { opacity: 0 } : { opacity: 0, x: -18 }}
                transition={{ duration: 0.24 }}
              >
                {step === 0 && (
                  <div className="fb-type-grid" role="radiogroup" aria-label="Art der Meldung">
                    {(Object.keys(TYPE_META) as FeedbackType[]).map((type) => {
                      const Icon = TYPE_ICONS[type];
                      const selected = form.type === type;
                      return (
                        <button
                          key={type}
                          type="button"
                          role="radio"
                          aria-checked={selected}
                          className={`fb-type-card${selected ? " is-selected" : ""}`}
                          onClick={() => set("type", type)}
                        >
                          <span className="fb-type-icon">
                            <Icon size={26} strokeWidth={1.7} />
                          </span>
                          <strong>{TYPE_META[type].label}</strong>
                          <small>{TYPE_META[type].tagline}</small>
                          {selected && (
                            <span className="fb-type-check">
                              <Check size={14} /> Ausgewählt
                            </span>
                          )}
                        </button>
                      );
                    })}
                  </div>
                )}

                {step === 1 && (
                  <div className="fb-step-grid">
                    <p className="fb-step-intro">
                      Alles freiwillig – aber je mehr du ausfüllst, desto besser kann dein Bericht helfen.
                      „Weiß nicht“ ist immer eine gute Antwort.
                    </p>
                    <PillGroup
                      label="Welche Art Cabinet nutzt du?"
                      options={CABINET_OPTIONS}
                      value={form.cabinetType}
                      onChange={(value) => set("cabinetType", value)}
                    />
                    <PillGroup
                      label="Welches Betriebssystem läuft darauf?"
                      hint="Tipp: Windows-Taste + R, „winver“ eingeben – oder einfach raten."
                      options={OS_OPTIONS}
                      value={form.os}
                      onChange={(value) => set("os", value)}
                    />
                    <div className="fb-two-col">
                      <div className="fb-field">
                        <FieldLabel optional>fagent-Version</FieldLabel>
                        <input
                          className="fb-input"
                          value={form.fagentVersion}
                          onChange={(e) => set("fagentVersion", e.target.value)}
                          placeholder="z. B. 0.1.0"
                          autoComplete="off"
                        />
                        <p className="fb-hint">
                          Findest du mit <button type="button" className="fb-inline-copy" onClick={() => handleCopy(QUICK_COMMANDS.version, "cmd-version")}>kopieren</button>: <code>{QUICK_COMMANDS.version}</code>
                        </p>
                      </div>
                      <div className="fb-field">
                        <FieldLabel optional>Kit-Version</FieldLabel>
                        <input
                          className="fb-input"
                          value={form.kitVersion}
                          onChange={(e) => set("kitVersion", e.target.value)}
                          placeholder="z. B. 0.3.0"
                          autoComplete="off"
                        />
                        <p className="fb-hint">Steht in der Datei VERSION im Kit-Ordner.</p>
                      </div>
                    </div>
                    <PillGroup
                      label="Welche Node.js-Version ist installiert?"
                      hint="Tipp: Im Terminal „node --version“ eingeben. Keine Ahnung? Einfach „Weiß nicht“."
                      options={NODE_OPTIONS}
                      value={form.nodeVersion}
                      onChange={(value) => set("nodeVersion", value)}
                    />
                    <PillGroup
                      label="Wie viele Monitore hängen am Cabinet?"
                      options={SCREEN_OPTIONS}
                      value={form.screens}
                      onChange={(value) => set("screens", value)}
                    />
                    <PillGroup
                      label="Welche Grafikkarte steckt drin?"
                      options={GPU_OPTIONS}
                      value={form.gpu}
                      onChange={(value) => set("gpu", value)}
                    />
                    <PillGroup
                      label="Welche Lightgun nutzt du?"
                      options={LIGHTGUN_OPTIONS}
                      value={form.lightgun}
                      onChange={(value) => set("lightgun", value)}
                    />
                    <div className="fb-field">
                      <FieldLabel optional>Welche Emulatoren / Programme nutzt du? (Mehrfachauswahl)</FieldLabel>
                      <div className="fb-pills">
                        {EMULATOR_OPTIONS.map((option) => {
                          const active = form.emulators.includes(option.value);
                          return (
                            <button
                              key={option.value}
                              type="button"
                              aria-pressed={active}
                              className={`fb-pill${active ? " is-selected" : ""}`}
                              onClick={() => toggleEmulator(option.value)}
                            >
                              {active && <Check size={13} />}
                              {option.label}
                            </button>
                          );
                        })}
                      </div>
                    </div>
                    <PillGroup
                      label="Welches KI-Modell nutzt du mit dem Agenten?"
                      options={MODEL_OPTIONS}
                      value={form.model}
                      onChange={(value) => set("model", value)}
                    />
                  </div>
                )}

                {step === 2 && (
                  <div className="fb-step-grid">
                    <p className="fb-step-intro">
                      {typeMeta ? typeMeta.summaryHint : "Erzähle in eigenen Worten – das genügt völlig."}
                      {form.type === "works" && " Auch kurze Erfolgsmeldungen sind Gold wert."}
                    </p>
                    <div className="fb-field">
                      <FieldLabel>Titel – worum geht es in einem Satz?</FieldLabel>
                      <input
                        className="fb-input"
                        value={form.title}
                        onChange={(e) => set("title", e.target.value)}
                        placeholder={typeMeta?.titlePlaceholder ?? "Kurzer Titel …"}
                        maxLength={140}
                        autoComplete="off"
                      />
                    </div>
                    <div className="fb-field">
                      <FieldLabel>Beschreibung – was sollen wir wissen?</FieldLabel>
                      <textarea
                        className="fb-textarea"
                        rows={5}
                        value={form.summary}
                        onChange={(e) => set("summary", e.target.value)}
                        placeholder={typeMeta?.summaryPlaceholder ?? "Erzähle in eigenen Worten …"}
                      />
                      <p className="fb-hint">{form.summary.trim().length} Zeichen (mindestens 20).</p>
                    </div>
                    {(form.type === "bug" || form.type === "partial" || form.type === "") && (
                      <>
                        <div className="fb-field">
                          <FieldLabel optional>Was hast du Schritt für Schritt gemacht?</FieldLabel>
                          <textarea
                            className="fb-textarea"
                            rows={3}
                            value={form.steps}
                            onChange={(e) => set("steps", e.target.value)}
                            placeholder={"1. Ich habe …\n2. Dann habe ich …\n3. Danach ist … passiert"}
                          />
                        </div>
                        <div className="fb-two-col">
                          <div className="fb-field">
                            <FieldLabel optional>Was hast du erwartet?</FieldLabel>
                            <textarea
                              className="fb-textarea"
                              rows={2}
                              value={form.expected}
                              onChange={(e) => set("expected", e.target.value)}
                              placeholder="Was sollte passieren?"
                            />
                          </div>
                          <div className="fb-field">
                            <FieldLabel optional>Was ist stattdessen passiert?</FieldLabel>
                            <textarea
                              className="fb-textarea"
                              rows={2}
                              value={form.actual}
                              onChange={(e) => set("actual", e.target.value)}
                              placeholder="Was ist wirklich passiert?"
                            />
                          </div>
                        </div>
                        <PillGroup
                          label="Wie oft tritt es auf?"
                          options={FREQUENCY_OPTIONS}
                          value={form.frequency}
                          onChange={(value) => set("frequency", value as Frequency)}
                        />
                        <div className="fb-field">
                          <FieldLabel optional>Wie schlimm ist es für dich?</FieldLabel>
                          <div className="fb-severity">
                            <input
                              type="range"
                              min={1}
                              max={5}
                              step={1}
                              value={form.severity}
                              onChange={(e) => set("severity", Number(e.target.value))}
                              aria-label="Schwere des Problems"
                            />
                            <p>
                              <strong>{form.severity}/5</strong> – {SEVERITY_LABELS[form.severity]}
                            </p>
                          </div>
                        </div>
                      </>
                    )}
                    {form.type === "idea" && (
                      <div className="fb-info-box">
                        <Info size={16} />
                        <p>
                          Gute Wünsche nennen das <strong>Problem dahinter</strong>: Wobei soll der Agent
                          dir helfen? Ein Beispiel aus deinem Alltag am Cabinet sagt mehr als tausend Details.
                        </p>
                      </div>
                    )}
                  </div>
                )}

                {step === 3 && (
                  <div className="fb-step-grid">
                    <p className="fb-step-intro">
                      Eine Diagnose-Ausgabe hilft enorm – ist aber freiwillig. Alles wird{" "}
                      <strong>nur in deinem Browser</strong> verarbeitet und auf Wunsch automatisch bereinigt.
                    </p>
                    <div className="fb-command-box">
                      <p>
                        <strong>So holst du die Diagnose:</strong> Am Cabinet ein Terminal öffnen und einfügen:
                      </p>
                      <div className="fb-command-row">
                        <code>{QUICK_COMMANDS.doctor}</code>
                        <button type="button" onClick={() => handleCopy(QUICK_COMMANDS.doctor, "cmd-doctor")}>
                          <Copy size={14} /> {copiedKey === "cmd-doctor" ? "Kopiert!" : "Kopieren"}
                        </button>
                      </div>
                      <div className="fb-command-row">
                        <code>{QUICK_COMMANDS.status}</code>
                        <button type="button" onClick={() => handleCopy(QUICK_COMMANDS.status, "cmd-status")}>
                          <Copy size={14} /> {copiedKey === "cmd-status" ? "Kopiert!" : "Kopieren"}
                        </button>
                      </div>
                    </div>
                    <div className="fb-field">
                      <FieldLabel optional>Diagnose-Ausgabe hier einfügen</FieldLabel>
                      <textarea
                        className="fb-textarea fb-mono"
                        rows={6}
                        value={form.doctorOutput}
                        onChange={(e) => set("doctorOutput", e.target.value)}
                        placeholder="Ausgabe von fagent doctor oder fagent status hier einfügen …"
                        spellCheck={false}
                      />
                    </div>
                    <ToggleRow
                      checked={form.anonymize}
                      onChange={(value) => set("anonymize", value)}
                      title="Persönliche Daten automatisch maskieren (empfohlen)"
                      description="Benutzernamen, IP-Adressen, E-Mails und Windows-SIDs werden lokal durch Platzhalter ersetzt."
                    />
                    {sensitiveHints.length > 0 && (
                      <div className={`fb-info-box${form.anonymize ? " is-ok" : " is-warn"}`}>
                        {form.anonymize ? <ShieldCheck size={16} /> : <Info size={16} />}
                        <p>
                          {form.anonymize ? "Wird automatisch maskiert: " : "Achtung, unmaskiert enthalten: "}
                          {sensitiveHints.join(" · ")}.
                        </p>
                      </div>
                    )}
                    {form.doctorOutput.trim() && (
                      <button
                        type="button"
                        className="fb-preview-toggle"
                        onClick={() => setShowAnonPreview((v) => !v)}
                        aria-expanded={showAnonPreview}
                      >
                        <Eye size={15} /> {showAnonPreview ? "Vorschau ausblenden" : "Vorschau: So wird es mitgeschickt"}
                      </button>
                    )}
                    {showAnonPreview && form.doctorOutput.trim() && (
                      <pre className="fb-code-preview">
                        {(form.anonymize ? anonymizeText(form.doctorOutput) : form.doctorOutput).slice(0, 2000)}
                      </pre>
                    )}
                    <ToggleRow
                      checked={form.includeBrowserInfo}
                      onChange={(value) => set("includeBrowserInfo", value)}
                      title="Technische Browser-Infos mitsenden (empfohlen)"
                      description={`Aktuell: ${meta.browser.browser} · ${meta.browser.language} · ${meta.browser.screen} – harmlos, aber nützlich.`}
                    />
                  </div>
                )}

                {step === 4 && (
                  <div className="fb-step-grid">
                    <p className="fb-step-intro">
                      Alles auf dieser Seite ist freiwillig. Ohne Angaben bleibt deine Meldung{" "}
                      <strong>vollständig anonym</strong>.
                    </p>
                    <div className="fb-two-col">
                      <div className="fb-field">
                        <FieldLabel optional>Spitzname</FieldLabel>
                        <input
                          className="fb-input"
                          value={form.nickname}
                          onChange={(e) => set("nickname", e.target.value)}
                          placeholder="z. B. Flipper-Fan87"
                          autoComplete="nickname"
                        />
                      </div>
                      <div className="fb-field">
                        <FieldLabel optional>E-Mail oder Discord-Name</FieldLabel>
                        <input
                          className="fb-input"
                          value={form.contact}
                          onChange={(e) => set("contact", e.target.value)}
                          placeholder="Nur für Rückfragen"
                          autoComplete="email"
                        />
                      </div>
                    </div>
                    <ToggleRow
                      checked={form.allowFollowUp}
                      onChange={(value) => set("allowFollowUp", value)}
                      title="Rückfragen sind okay"
                      description="Der Entwickler darf sich bei Unklarheiten melden – keine Werbung, kein Verteiler."
                    />
                    <div className="fb-info-box">
                      <ShieldCheck size={16} />
                      <p>
                        <strong>Deine Daten bleiben bei dir</strong>, bis du aktiv sendest. Es gibt kein
                        Tracking und kein Konto. Was du kopierst oder lädst, verlässt diesen Browser nur,
                        wenn du es selbst verschickst.
                      </p>
                    </div>
                  </div>
                )}

                {step === 5 && (
                  <div className="fb-step-grid">
                    <div className="fb-complete">
                      <div className="fb-complete-head">
                        <strong>Vollständigkeit: {completeness.score} %</strong>
                        <span>{completeness.score >= 80 ? "Stark – so hilft es am meisten!" : completeness.score >= 50 ? "Solide – ein paar Angaben fehlen noch." : "Anfang gemacht – magst du noch etwas ergänzen?"}</span>
                      </div>
                      <div className="fb-complete-bar" aria-hidden="true">
                        <div style={{ width: `${completeness.score}%` }} />
                      </div>
                      {completeness.missing.length > 0 && (
                        <ul className="fb-missing">
                          {completeness.missing.slice(0, 5).map((item) => (
                            <li key={item.label}>
                              <button type="button" onClick={() => goTo(item.step)}>
                                {item.label} <ChevronRight size={14} />
                              </button>
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>

                    <div className="fb-tabs" role="tablist" aria-label="Berichtsvorschau">
                      {(
                        [
                          ["uebersicht", "Übersicht"],
                          ["markdown", "Datei-Vorschau"],
                          ["kurz", "Kurztext"],
                        ] as const
                      ).map(([key, label]) => (
                        <button
                          key={key}
                          type="button"
                          role="tab"
                          aria-selected={previewTab === key}
                          className={previewTab === key ? "is-active" : ""}
                          onClick={() => setPreviewTab(key)}
                        >
                          {label}
                        </button>
                      ))}
                    </div>

                    {previewTab === "uebersicht" && (
                      <div className="fb-overview">
                        <p className="fb-overview-type">{form.type ? TYPE_META[form.type].label : "– Keine Art gewählt –"}</p>
                        <h4>{form.title.trim() || "– Noch kein Titel –"}</h4>
                        <p className="fb-overview-summary">{form.summary.trim() || "– Noch keine Beschreibung –"}</p>
                        <div className="fb-overview-chips">
                          <span>{labelFor(CABINET_OPTIONS, form.cabinetType)}</span>
                          <span>{labelFor(OS_OPTIONS, form.os)}</span>
                          {form.screens && <span>{labelFor(SCREEN_OPTIONS, form.screens)}</span>}
                          {form.lightgun && <span>{labelFor(LIGHTGUN_OPTIONS, form.lightgun)}</span>}
                          {form.model && <span>{labelFor(MODEL_OPTIONS, form.model)}</span>}
                        </div>
                        {(form.type === "bug" || form.type === "partial") && (
                          <p className="fb-overview-meta">
                            {form.frequency ? labelFor(FREQUENCY_OPTIONS, form.frequency) : "Häufigkeit offen"} · Schwere {form.severity}/5
                            {form.doctorOutput.trim() ? " · Diagnose dabei" : " · ohne Diagnose"}
                            {form.nickname.trim() ? ` · von ${form.nickname.trim()}` : " · anonym"}
                          </p>
                        )}
                      </div>
                    )}
                    {previewTab === "markdown" && <pre className="fb-code-preview fb-tall">{markdown}</pre>}
                    {previewTab === "kurz" && <pre className="fb-code-preview">{shortText}</pre>}

                    <div className="fb-send-card is-featured">
                      <div className="fb-send-card-head">
                        <span className="fb-send-icon">
                          <Send size={18} />
                        </span>
                        <div>
                          <strong>Direkt senden</strong>
                          <small>Ein Klick – kein Konto, kein E-Mail-Programm nötig.</small>
                        </div>
                        {directAvailable ? (
                          <span className="fb-availability is-on">Bereit</span>
                        ) : (
                          <span className="fb-availability">Bald</span>
                        )}
                      </div>
                      {directAvailable ? (
                        <>
                          <label className="fb-consent">
                            <input
                              type="checkbox"
                              checked={form.consent}
                              onChange={(e) => set("consent", e.target.checked)}
                            />
                            <span>
                              Ich bin einverstanden, dass mein Bericht an den Entwickler gesendet und zur
                              Fehlerbehebung gespeichert wird.
                            </span>
                          </label>
                          <button
                            type="button"
                            className="fb-btn fb-btn-primary"
                            onClick={handleDirectSend}
                            disabled={sendState === "sending"}
                          >
                            {sendState === "sending" ? "Wird gesendet …" : "Jetzt direkt senden"}
                          </button>
                          {sendState === "error" && (
                            <p className="fb-send-error" role="alert">
                              Senden fehlgeschlagen ({sendError}). Bitte eine Alternative unten nutzen –
                              dein Text geht nicht verloren.
                            </p>
                          )}
                        </>
                      ) : (
                        <p className="fb-send-note">
                          Der Direktversand wird gerade eingerichtet. Bis dahin funktionieren alle Optionen
                          unten <strong>ohne Konto</strong> – versprochen.
                        </p>
                      )}
                    </div>

                    <div className="fb-send-grid">
                      <div className="fb-send-card">
                        <div className="fb-send-card-head">
                          <span className="fb-send-icon"><Mail size={18} /></span>
                          <div><strong>Per Mail-App senden</strong><small>Öffnet dein E-Mail-Programm, Text schon drin.</small></div>
                        </div>
                        <button
                          type="button"
                          className="fb-btn fb-btn-ghost"
                          onClick={handleMailto}
                          disabled={!effectiveEmail}
                        >
                          {effectiveEmail ? "E-Mail vorbereiten" : "Noch nicht verfügbar"}
                        </button>
                      </div>
                      <div className="fb-send-card">
                        <div className="fb-send-card-head">
                          <span className="fb-send-icon"><Copy size={18} /></span>
                          <div><strong>Kopieren</strong><small>Für Discord, Forum oder eigene Mail.</small></div>
                        </div>
                        <div className="fb-btn-row">
                          <button type="button" className="fb-btn fb-btn-ghost" onClick={() => { handleCopy(markdown, "md"); saveDraft("exportiert"); }}>
                            {copiedKey === "md" ? "Kopiert!" : "Bericht kopieren"}
                          </button>
                          <button type="button" className="fb-btn fb-btn-ghost" onClick={() => { handleCopy(shortText, "short"); saveDraft("exportiert"); }}>
                            {copiedKey === "short" ? "Kopiert!" : "Kurztext"}
                          </button>
                        </div>
                      </div>
                      <div className="fb-send-card">
                        <div className="fb-send-card-head">
                          <span className="fb-send-icon"><Download size={18} /></span>
                          <div><strong>Herunterladen</strong><small>Als Datei sichern oder anhängen.</small></div>
                        </div>
                        <div className="fb-btn-row">
                          <button type="button" className="fb-btn fb-btn-ghost" onClick={handleDownloadMarkdown}>
                            <FileText size={15} /> .md-Datei
                          </button>
                          <button type="button" className="fb-btn fb-btn-ghost" onClick={handleDownloadJson}>
                            .json-Datei
                          </button>
                        </div>
                      </div>
                      <div className="fb-send-card">
                        <div className="fb-send-card-head">
                          <span className="fb-send-icon"><ExternalLink size={18} /></span>
                          <div><strong>GitHub Issue</strong><small>Nur für Kenner mit Konto.</small></div>
                        </div>
                        <button type="button" className="fb-btn fb-btn-ghost" onClick={handleGithub}>
                          Issue vorausfüllen
                        </button>
                      </div>
                    </div>

                    <button type="button" className="fb-save-link" onClick={handleSaveOnly}>
                      Erst mal nur in „Meine Meldungen“ speichern – später entscheiden.
                    </button>
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {!successMode && (
          <footer className="fb-modal-footer">
            <button
              type="button"
              className="fb-btn fb-btn-ghost"
              onClick={() => goTo(step - 1)}
              disabled={step === 0}
            >
              <ChevronLeft size={17} /> Zurück
            </button>
            <span className="fb-footer-meta">
              Bericht-ID <strong>{meta.reportId}</strong>
            </span>
            {step < STEPS.length - 1 ? (
              <button type="button" className="fb-btn fb-btn-primary" onClick={goNext}>
                Weiter <ChevronRight size={17} />
              </button>
            ) : (
              <button type="button" className="fb-btn fb-btn-ghost" onClick={onClose}>
                Schließen
              </button>
            )}
          </footer>
        )}
      </motion.div>
    </motion.div>
  );
}

export type { BrowserMeta };
