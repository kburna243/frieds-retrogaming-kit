import { useEffect, useState, type ReactNode } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import {
  Bug,
  Check,
  ChevronDown,
  Copy,
  Download,
  FlaskConical,
  Info,
  Lightbulb,
  MessageSquare,
  Send,
  ShieldCheck,
  Trash2,
  Trophy,
} from "lucide-react";
import "./feedback.css";
import { FEEDBACK_CONFIG, MATRIX_CATEGORIES, MATRIX_ITEMS, NEED_META } from "./config";
import {
  EMPTY_FORM,
  TYPE_META,
  buildShort,
  collectBrowserInfo,
  copyText,
  downloadFile,
  formatDateTime,
  getEffectiveEmail,
  getTestEmailOverride,
  loadReports,
  removeReport,
  setTestEmailOverride,
  type FeedbackForm,
  type FeedbackType,
  type SavedReport,
} from "./report";
import FeedbackWizard from "./FeedbackWizard";

const ENTRY_ICONS: Record<FeedbackType, typeof Bug> = {
  works: Trophy,
  partial: FlaskConical,
  bug: Bug,
  idea: Lightbulb,
};

const FAQ_ITEMS = [
  {
    question: "Brauche ich einen GitHub-Account oder technisches Wissen?",
    answer:
      "Nein. Der Assistent führt dich in einfachen Worten durch – ohne Fachbegriffe, ohne Konto, ohne „Pull Request“. Am Ende sendest du mit einem Klick, kopierst deinen Bericht oder lädst ihn als Datei herunter.",
  },
  {
    question: "Was passiert mit meinen Daten?",
    answer:
      "Alles, was du eingibst, bleibt zuerst nur in deinem Browser. Erst wenn du aktiv auf „Direkt senden“ klickst, geht der Bericht per E-Mail an den Entwickler. Diagnose-Texte kannst du vorher automatisch bereinigen lassen (Benutzernamen, IPs und E-Mails werden maskiert). Ohne Kontaktangabe bleibst du vollständig anonym.",
  },
  {
    question: "Was ist eine gute Meldung?",
    answer:
      "Titel in einem Satz, 2–3 Sätze Beschreibung und dein System (Cabinet-Typ, Windows-Version). Bei Problemen hilft zusätzlich: Was geht – und was genau geht nicht? Erfolgsmeldungen („läuft bei mir“) sind übrigens genauso wertvoll, besonders für Systeme aus der Testmatrix.",
  },
  {
    question: "Wo finde ich fagent- und Kit-Version?",
    answer:
      "Am Cabinet ein Terminal öffnen und „fagent --version“ eingeben. Die Diagnose für Schritt 4 holst du mit „fagent doctor --transport mcp“ – im Assistenten gibt es dafür Kopieren-Knöpfe. Keine Ahnung? Einfach leer lassen.",
  },
  {
    question: "Ich habe wenig Zeit – geht es auch ganz kurz?",
    answer:
      "Ja. Titel und Beschreibung genügen für eine gültige Meldung – das dauert keine zwei Minuten. Alles andere (System, Diagnose, Kontakt) ist freiwillig und kann später ergänzt werden.",
  },
];

function Reveal({ children, className = "", delay = 0 }: { children: ReactNode; className?: string; delay?: number }) {
  const reducedMotion = useReducedMotion();
  return (
    <motion.div
      className={className}
      initial={reducedMotion ? false : { opacity: 0, y: 32 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.1 }}
      transition={{ duration: 0.72, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  );
}

function StatusBadge({ status }: { status: SavedReport["status"] }) {
  return <span className={`fb-status fb-status-${status}`}>{status === "gesendet" ? "Gesendet" : status === "exportiert" ? "Exportiert" : "Entwurf"}</span>;
}

export default function FeedbackCenter() {
  const reducedMotion = useReducedMotion();
  const [wizardOpen, setWizardOpen] = useState(false);
  const [wizardInitial, setWizardInitial] = useState<{ form: FeedbackForm; step: number; hint: string | null }>({
    form: { ...EMPTY_FORM },
    step: 0,
    hint: null,
  });
  const [matrixFilter, setMatrixFilter] = useState<string>("Alle");
  const [reports, setReports] = useState<SavedReport[]>(() => loadReports());
  const [openFaq, setOpenFaq] = useState<number | null>(0);
  const [setupOpen, setSetupOpen] = useState(false);
  const [expandedReport, setExpandedReport] = useState<string | null>(null);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [fabVisible, setFabVisible] = useState(false);
  const [testEmail, setTestEmail] = useState(() => getTestEmailOverride());
  const [testEmailSaved, setTestEmailSaved] = useState(false);

  useEffect(() => {
    const onScroll = () => setFabVisible(window.scrollY > 650);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const openWizard = (preset: Partial<FeedbackForm> = {}, step = 0, hint: string | null = null) => {
    setWizardInitial({ form: { ...EMPTY_FORM, ...preset }, step, hint });
    setWizardOpen(true);
  };

  const refreshReports = () => setReports(loadReports());

  const handleCopy = async (text: string, key: string) => {
    try {
      await copyText(text);
      setCopiedKey(key);
      window.setTimeout(() => setCopiedKey((current) => (current === key ? null : current)), 2200);
    } catch {
      /* ignore – Nutzer kann manuell kopieren */
    }
  };

  const handleDelete = (id: string) => {
    setReports(removeReport(id));
    if (expandedReport === id) setExpandedReport(null);
  };

  const handleExportAll = () => {
    downloadFile(`fagent-meine-meldungen-${reports.length}.json`, JSON.stringify(reports, null, 2), "application/json");
  };

  const handleSaveTestEmail = () => {
    setTestEmailOverride(testEmail);
    setTestEmailSaved(true);
    window.setTimeout(() => setTestEmailSaved(false), 2500);
  };

  const directReady = getEffectiveEmail() !== "" || FEEDBACK_CONFIG.customEndpoint.trim() !== "";
  const visibleMatrix =
    matrixFilter === "Alle" ? MATRIX_ITEMS : MATRIX_ITEMS.filter((item) => item.category === matrixFilter);
  const wantedCount = MATRIX_ITEMS.filter((item) => item.need === "gesucht").length;

  return (
    <>
      <section className="fb-section section-pad" id="feedback" aria-labelledby="feedback-title">
        <div className="container">
          <Reveal>
            <div className="section-label">
              <span className="section-label-number">06</span>
              <span className="section-label-line" />
              <span>COMMUNITY-FEEDBACK</span>
            </div>
            <h2 className="section-title" id="feedback-title">
              Dein System.
              <br />
              Dein Bericht. <span>Kein Konto.</span>
            </h2>
            <p className="section-intro">
              Viele Setups kann der Entwickler selbst nicht testen – <strong>{wantedCount} Systeme suchen dringend
              Tester:innen</strong>. Der Assistent fragt alles in einfachen Worten ab und erzeugt daraus einen
              sauberen Bericht. Ohne GitHub, ohne Fachchinesisch.
            </p>
            <ul className="fb-trust">
              <li><Check size={15} /> Kein Login nötig</li>
              <li><Check size={15} /> In 2 Minuten fertig</li>
              <li><Check size={15} /> Anonym möglich</li>
              <li><Check size={15} /> Vorschau vor dem Senden</li>
            </ul>
          </Reveal>

          <Reveal className="fb-how" delay={0.08}>
            <div className="fb-how-step">
              <span>01</span>
              <strong>Ausfüllen</strong>
              <p>6 kurze Schritte in Alltagssprache – „Weiß nicht“ ist immer okay.</p>
            </div>
            <div className="fb-how-step">
              <span>02</span>
              <strong>Prüfen</strong>
              <p>Private Daten werden auf Wunsch automatisch maskiert.</p>
            </div>
            <div className="fb-how-step">
              <span>03</span>
              <strong>Abschicken</strong>
              <p>Direkt senden, kopieren oder laden – du entscheidest.</p>
            </div>
          </Reveal>

          <Reveal delay={0.05}>
            <div className="fb-entry-grid">
              {(Object.keys(TYPE_META) as FeedbackType[]).map((type) => {
                const Icon = ENTRY_ICONS[type];
                return (
                  <button
                    key={type}
                    type="button"
                    className="fb-entry-card"
                    onClick={() => openWizard({ type }, 1)}
                  >
                    <span className="fb-entry-icon"><Icon size={27} strokeWidth={1.7} /></span>
                    <strong>{TYPE_META[type].label}</strong>
                    <small>{TYPE_META[type].tagline}</small>
                    <span className="fb-entry-cta">Assistent starten →</span>
                  </button>
                );
              })}
            </div>
          </Reveal>

          <Reveal delay={0.05}>
            <div className="fb-matrix-head">
              <div>
                <h3>Die Testmatrix: Diese Systeme brauchen dich</h3>
                <p>
                  Ein Klick füllt den Assistenten mit deinem System vor – du prüfst nur noch und ergänzt deine
                  Erfahrung.
                </p>
              </div>
              <div className="fb-filter" role="group" aria-label="Testmatrix filtern">
                {MATRIX_CATEGORIES.map((category) => (
                  <button
                    key={category}
                    type="button"
                    className={matrixFilter === category ? "is-active" : ""}
                    onClick={() => setMatrixFilter(category)}
                    aria-pressed={matrixFilter === category}
                  >
                    {category}
                  </button>
                ))}
              </div>
            </div>
            <div className="fb-matrix-grid">
              {visibleMatrix.map((item) => (
                <article key={item.id} className={`fb-matrix-card need-${item.need}`}>
                  <div className="fb-matrix-top">
                    <span className="fb-matrix-category">{item.category}</span>
                    <span className={`fb-need need-${item.need}`} title={NEED_META[item.need].hint}>
                      {NEED_META[item.need].label}
                    </span>
                  </div>
                  <h4>{item.title}</h4>
                  <p>{item.blurb}</p>
                  <button type="button" onClick={() => openWizard({ type: "works", ...item.prefill }, 1, item.title)}>
                    Ich habe das – berichten →
                  </button>
                </article>
              ))}
            </div>
          </Reveal>

          <div className="fb-two-col-section">
            <Reveal>
              <h3 className="fb-subheading">Häufige Fragen</h3>
              <div className="fb-faq">
                {FAQ_ITEMS.map((item, index) => (
                  <div key={item.question} className={`fb-faq-item${openFaq === index ? " is-open" : ""}`}>
                    <button
                      type="button"
                      onClick={() => setOpenFaq(openFaq === index ? null : index)}
                      aria-expanded={openFaq === index}
                    >
                      <strong>{item.question}</strong>
                      <ChevronDown size={19} className="fb-faq-chevron" />
                    </button>
                    <AnimatePresence initial={false}>
                      {openFaq === index && (
                        <motion.div
                          className="fb-faq-answer"
                          initial={reducedMotion ? false : { height: 0, opacity: 0 }}
                          animate={{ height: "auto", opacity: 1 }}
                          exit={reducedMotion ? { opacity: 0 } : { height: 0, opacity: 0 }}
                          transition={{ duration: 0.25 }}
                        >
                          <p>{item.answer}</p>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </div>
                ))}
              </div>
            </Reveal>

            <Reveal delay={0.08}>
              <h3 className="fb-subheading" id="meine-meldungen">Meine Meldungen</h3>
              <p className="fb-muted">
                Nur auf diesem Gerät gespeichert – als Entwurf, zum Nachreichen oder als Kopie deiner
                gesendeten Berichte.
              </p>
              {reports.length === 0 ? (
                <div className="fb-empty">
                  <MessageSquare size={26} strokeWidth={1.6} />
                  <p>Noch keine Meldungen. Starte den Assistenten – deine Berichte erscheinen hier automatisch.</p>
                  <button type="button" className="fb-btn fb-btn-primary" onClick={() => openWizard()}>
                    <Send size={16} /> Feedback-Assistent starten
                  </button>
                </div>
              ) : (
                <div className="fb-report-list">
                  {reports.map((report) => (
                    <div key={report.id} className="fb-report-item">
                      <button
                        type="button"
                        className="fb-report-head"
                        onClick={() => setExpandedReport(expandedReport === report.id ? null : report.id)}
                        aria-expanded={expandedReport === report.id}
                      >
                        <span className="fb-report-id-small">{report.id}</span>
                        <span className="fb-report-title">
                          <strong>{report.title}</strong>
                          <small>
                            {formatDateTime(report.createdAt)} · {report.type ? TYPE_META[report.type].label : "Feedback"}
                          </small>
                        </span>
                        <StatusBadge status={report.status} />
                        <ChevronDown size={18} className={`fb-faq-chevron${expandedReport === report.id ? " is-rotated" : ""}`} />
                      </button>
                      <AnimatePresence initial={false}>
                        {expandedReport === report.id && (
                          <motion.div
                            className="fb-report-detail"
                            initial={reducedMotion ? false : { height: 0, opacity: 0 }}
                            animate={{ height: "auto", opacity: 1 }}
                            exit={reducedMotion ? { opacity: 0 } : { height: 0, opacity: 0 }}
                            transition={{ duration: 0.25 }}
                          >
                            <pre>{report.markdown.slice(0, 2500)}{report.markdown.length > 2500 ? "\n… (gekürzt)" : ""}</pre>
                            <div className="fb-btn-row">
                              <button type="button" className="fb-btn fb-btn-ghost" onClick={() => handleCopy(report.markdown, report.id)}>
                                <Copy size={15} /> {copiedKey === report.id ? "Kopiert!" : "Kopieren"}
                              </button>
                              <button
                                type="button"
                                className="fb-btn fb-btn-ghost"
                                onClick={() => {
                                  const short = buildShort(report.form, {
                                    reportId: report.id,
                                    createdAt: report.createdAt,
                                    browser: collectBrowserInfo(),
                                  });
                                  handleCopy(short, `${report.id}-short`);
                                }}
                              >
                                {copiedKey === `${report.id}-short` ? "Kopiert!" : "Kurztext kopieren"}
                              </button>
                              <button
                                type="button"
                                className="fb-btn fb-btn-ghost"
                                onClick={() => downloadFile(`${report.id}-feedback.md`, report.markdown)}
                              >
                                <Download size={15} /> .md laden
                              </button>
                              <button
                                type="button"
                                className="fb-btn fb-btn-danger"
                                onClick={() => handleDelete(report.id)}
                              >
                                <Trash2 size={15} /> Löschen
                              </button>
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </div>
                  ))}
                  <button type="button" className="fb-save-link" onClick={handleExportAll}>
                    Alle {reports.length} Meldungen als JSON exportieren
                  </button>
                </div>
              )}
            </Reveal>
          </div>

          <Reveal>
            <div className="fb-setup">
              <button
                type="button"
                className="fb-setup-head"
                onClick={() => setSetupOpen(!setupOpen)}
                aria-expanded={setupOpen}
              >
                <span className="fb-setup-icon"><ShieldCheck size={19} /></span>
                <span className="fb-setup-title">
                  <strong>Für Betreiber: Direktversand in 5 Minuten einrichten</strong>
                  <small>
                    Status: {directReady ? "bereit – Berichte kommen direkt an." : "noch nicht eingerichtet – Kopieren & Laden funktionieren trotzdem."}
                  </small>
                </span>
                <ChevronDown size={20} className={`fb-faq-chevron${setupOpen ? " is-rotated" : ""}`} />
              </button>
              <AnimatePresence initial={false}>
                {setupOpen && (
                  <motion.div
                    className="fb-setup-body"
                    initial={reducedMotion ? false : { height: 0, opacity: 0 }}
                    animate={{ height: "auto", opacity: 1 }}
                    exit={reducedMotion ? { opacity: 0 } : { height: 0, opacity: 0 }}
                    transition={{ duration: 0.28 }}
                  >
                    <ol>
                      <li>
                        In <code>src/feedback/config.ts</code> bei <code>maintainerEmail</code> deine
                        E-Mail-Adresse eintragen.
                      </li>
                      <li>Seite neu bauen und auf GitHub Pages deployen.</li>
                      <li>Dir selbst einen Testbericht über den Assistenten schicken.</li>
                      <li>
                        Die einmalige <strong>Aktivierungs-Mail von FormSubmit</strong> bestätigen – fertig.
                        Alle weiteren Berichte landen als Tabelle in deinem Postfach.
                      </li>
                    </ol>
                    <p className="fb-muted">
                      <Info size={14} /> Alternativen: <code>customEndpoint</code> für einen eigenen Webhook –
                      Discord-Webhooks werden automatisch erkannt und bekommen eine Kurzfassung. Ohne
                      Konfiguration bleiben Mail-App, Kopieren, Download und GitHub-Issue als Wege bestehen.
                    </p>
                    <div className="fb-test-email">
                      <label htmlFor="fb-test-email">Test-Empfänger (nur in diesem Browser, zum Ausprobieren):</label>
                      <div>
                        <input
                          id="fb-test-email"
                          className="fb-input"
                          type="email"
                          value={testEmail}
                          onChange={(e) => setTestEmail(e.target.value)}
                          placeholder="deine-email"
                          autoComplete="email"
                        />
                        <button type="button" className="fb-btn fb-btn-ghost" onClick={handleSaveTestEmail}>
                          {testEmailSaved ? "Gespeichert!" : "Übernehmen"}
                        </button>
                        {testEmail && (
                          <button
                            type="button"
                            className="fb-btn fb-btn-ghost"
                            onClick={() => { setTestEmail(""); setTestEmailOverride(""); }}
                          >
                            Zurücksetzen
                          </button>
                        )}
                      </div>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </Reveal>
        </div>
      </section>

      <AnimatePresence>
        {fabVisible && !wizardOpen && (
          <motion.button
            type="button"
            className="fb-fab"
            onClick={() => openWizard()}
            initial={reducedMotion ? false : { opacity: 0, y: 18, scale: 0.94 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={reducedMotion ? { opacity: 0 } : { opacity: 0, y: 18, scale: 0.94 }}
            transition={{ duration: 0.25 }}
            aria-label="Feedback geben – Assistent öffnen"
          >
            <MessageSquare size={19} />
            <span>Feedback geben</span>
            <span className="fb-fab-dot" aria-hidden="true" />
          </motion.button>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {wizardOpen && (
          <FeedbackWizard
            initialForm={wizardInitial.form}
            initialStep={wizardInitial.step}
            matrixHint={wizardInitial.hint}
            onClose={() => { setWizardOpen(false); refreshReports(); }}
            onSaved={refreshReports}
          />
        )}
      </AnimatePresence>
    </>
  );
}
