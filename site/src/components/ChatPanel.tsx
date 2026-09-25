import { useEffect, useRef, useState } from "react";
import { Send, User, Trash2, ChevronDown, Sparkles } from "lucide-react";
import { useRetro } from "../lib/retro";
import { answerQuery, type Hit } from "../lib/rag";
import { useI18n } from "../i18n";
import { FriedCharacter } from "./FriedCharacter";

/* ---------- markdown-lite renderer ---------- */
function Rich({ text }: { text: string }) {
  const lines = text.split("\n");
  return (
    <div className="space-y-1.5">
      {lines.map((l, i) => {
        if (!l.trim()) return <div key={i} className="h-1" />;
        // list items
        if (/^(\-|\d+\.)\s/.test(l.trim())) {
          return (
            <div key={i} className="flex gap-2">
              <span className="mt-[7px] h-1.5 w-1.5 shrink-0 bg-pixel" />
              <span><Inline t={l.replace(/^(\-|\d+\.)\s/, "")} /></span>
            </div>
          );
        }
        return (
          <p key={i}>
            <Inline t={l} />
          </p>
        );
      })}
    </div>
  );
}

function Inline({ t }: { t: string }) {
  const parts = t.split(/(\*\*[^*]+\*\*|`[^`]+`)/g);
  return (
    <>
      {parts.map((p, i) => {
        if (p.startsWith("**") && p.endsWith("**")) {
          return (
            <strong key={i} className="font-bold text-cream">
              {p.slice(2, -2)}
            </strong>
          );
        }
        if (p.startsWith("`") && p.endsWith("`")) {
          return (
            <code key={i} className="border border-pixel-dim/60 bg-screen px-1 font-term text-[0.95em] text-pixel">
              {p.slice(1, -1)}
            </code>
          );
        }
        return <span key={i}>{p}</span>;
      })}
    </>
  );
}

/* ---------- types ---------- */
interface Msg {
  role: "user" | "bot";
  text: string;
  hits?: Hit[];
  time: string;
}

function now() {
  return new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export default function ChatPanel({ fullPage = false }: { fullPage?: boolean }) {
  const { play } = useRetro();
  const { t } = useI18n();
  const c = t.chat;
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [typing, setTyping] = useState(false);
  const [openTrace, setOpenTrace] = useState<number | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // scroll only inside the message list, never the page
    const el = bottomRef.current?.parentElement;
    if (el) el.scrollTop = el.scrollHeight;
  }, [msgs, typing]);

  const send = (raw?: string) => {
    const q = (raw ?? input).trim();
    if (!q || typing) return;
    play("select");
    const umsg: Msg = { role: "user", text: q, time: now() };
    setMsgs((m) => [...m, umsg]);
    setInput("");
    setTyping(true);
    // simulate retrieval latency for drama (and honesty: it IS searching)
    window.setTimeout(() => {
      const ans = answerQuery(q, c);
      setMsgs((m) => [...m, { role: "bot", text: ans.text, hits: ans.hits, time: now() }]);
      setTyping(false);
      play(ans.mode === "empty" ? "error" : "blip");
    }, 650 + Math.min(900, q.length * 8));
  };

  return (
    <div className={`flex flex-col overflow-hidden border-[3px] border-night-3 bg-night ${fullPage ? "h-[min(640px,80vh)]" : "h-[min(480px,68vh)]"}`}>
      {/* header */}
      <div className="flex items-center justify-between gap-2 border-b-[3px] border-night-3 bg-night-2 px-4 py-2.5">
        <div className="flex items-center gap-2.5">
          <FriedCharacter size="xs" expression="friendly" showCable={false} glow={false} />
          <div>
            <div className="font-pixel text-[9px] text-cream">{c.header}</div>
            <div className="flex items-center gap-1.5 font-term text-sm leading-none text-pixel">
              <span className="h-1.5 w-1.5 rounded-full bg-pixel" style={{ animation: "pulse-dot 1.5s infinite" }} />
              {c.status}
            </div>
          </div>
        </div>
        <button
          type="button"
          onClick={() => { setMsgs([]); play("blip"); }}
          title={c.clear}
          aria-label={c.clear}
          className="border-2 border-cream/30 p-1.5 text-cream/70 transition hover:border-retro hover:text-retro"
        >
          <Trash2 size={12} />
        </button>
      </div>

      {/* messages */}
      <div className="chat-scroll flex-1 space-y-4 overflow-y-auto p-4" aria-live="polite">
        {[{ role: "bot", text: c.welcome, time: "" } as Msg, ...msgs].map((m, i) => (
          <div key={i} className={`flex gap-2.5 ${m.role === "user" ? "flex-row-reverse" : ""}`}>
            <span className={`flex h-7 w-7 shrink-0 items-center justify-center border-2 ${m.role === "user" ? "border-gold bg-gold/15 text-gold" : "border-pixel bg-pixel/15 text-pixel"}`}>
              {m.role === "user" ? <User size={13} /> : <FriedCharacter size="xxs" expression="friendly" showCable={false} glow={false} />}
            </span>
            <div className={`max-w-[85%] ${m.role === "user" ? "border-2 border-gold/50 bg-gold/10 px-3.5 py-2.5 text-cream" : "border-2 border-night-3 bg-night-2 px-3.5 py-2.5 text-sm leading-relaxed text-cream/85"}`}>
              {m.role === "user" ? <span className="font-term text-lg">{m.text}</span> : <Rich text={m.text} />}
              <div className="mt-1.5 flex items-center justify-between gap-3">
                <span className="font-term text-sm text-cream/50">{m.time}</span>
                {m.role === "bot" && m.hits && m.hits.length > 0 && (
                  <button
                    type="button"
                    aria-expanded={openTrace === i}
                    onClick={() => { setOpenTrace(openTrace === i ? null : i); play("blip"); }}
                    className="flex items-center gap-1 font-pixel text-[7px] text-pixel/70 hover:text-pixel"
                  >
                    {c.trace} [{m.hits.length}] <ChevronDown size={10} className={openTrace === i ? "rotate-180" : ""} />
                  </button>
                )}
              </div>
              {m.role === "bot" && m.hits && openTrace === i && (
                <div className="mt-2 space-y-1.5 border-t border-night-3 pt-2">
                  {m.hits.map((h) => (
                    <div key={h.id} className="flex items-center justify-between gap-2 font-term text-sm">
                      <span className="flex items-center gap-1.5">
                        <code className="border border-pixel-dim/50 bg-screen px-1 text-pixel">{h.id}</code>
                        <span className="text-cream/50">{h.kind} · {h.category}</span>
                      </span>
                      <span className={`font-pixel text-[7px] ${h.confidence === "high" ? "text-pixel" : h.confidence === "medium" ? "text-gold" : "text-retro"}`}>
                        {h.confidence.toUpperCase()} · {h.score.toFixed(1)}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        ))}
        {typing && (
          <div className="flex gap-2.5">
            <span className="flex h-7 w-7 items-center justify-center border-2 border-pixel bg-pixel/15 text-pixel">
              <FriedCharacter size="xxs" expression="neutral" showCable={false} glow={false} />
            </span>
            <div className="border-2 border-night-3 bg-night-2 px-4 py-3 font-pixel text-[9px] text-pixel">
              <span className="typing-dots">{c.retrieving}<span>.</span><span>.</span><span>.</span></span>
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      {/* quick prompts */}
      <div className="flex gap-2 overflow-x-auto border-t-2 border-night-3 bg-night-2 px-3 py-2">
        <Sparkles size={13} className="mt-1 shrink-0 text-gold" />
        {c.quick.map((q) => (
          <button
            key={q}
            type="button"
            onClick={() => send(q)}
            className="shrink-0 border border-cream/25 px-2.5 py-1 font-term text-base text-cream/80 transition hover:border-pixel hover:text-pixel"
          >
            {q}
          </button>
        ))}
      </div>

      {/* input */}
      <form
        onSubmit={(e) => { e.preventDefault(); send(); }}
        className="flex gap-2 border-t-[3px] border-night-3 bg-night-2 p-3"
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          aria-label={c.input}
          placeholder={c.placeholder}
          className="min-w-0 flex-1 border-[3px] border-night bg-cream px-3 py-2 font-term text-lg text-night placeholder:text-night/35 focus:border-pixel-dim"
        />
        <button
          type="submit"
          aria-label={c.ask}
          disabled={!input.trim() || typing}
          className="btn-chunk flex shrink-0 items-center gap-2 border-[3px] border-night bg-pixel px-4 py-2 font-pixel text-[9px] text-night shadow-chunk-sm disabled:opacity-40"
        >
          <Send size={13} aria-hidden="true" /> <span className="hidden sm:inline">{c.ask}</span>
        </button>
      </form>
    </div>
  );
}
