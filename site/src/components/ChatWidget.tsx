import { useState } from "react";
import { X, Maximize2 } from "lucide-react";
import ChatPanel from "./ChatPanel";
import { FriedCharacter } from "./FriedCharacter";
import { useRetro } from "../lib/retro";
import { useI18n } from "../i18n";
import { navigate, type Route } from "../lib/router";

export default function ChatWidget({ route }: { route: Route }) {
  const { play } = useRetro();
  const { t } = useI18n();
  const [open, setOpen] = useState(false);

  // the knowledge page embeds the full chat already
  if (route === "knowledge") return null;

  return (
    <>
      {!open && (
        <button
          type="button"
          onClick={() => { setOpen(true); play("power"); }}
          className="btn-chunk fixed bottom-5 right-5 z-[85] flex items-center gap-2.5 border-[3px] border-night bg-gold py-1.5 pl-1.5 pr-4 text-night shadow-chunk"
          aria-label={t.chat.openWidget}
        >
          <span className="relative">
            <FriedCharacter size="xs" expression="winking" showCable={false} glow={false} />
            <span className="absolute -right-0.5 -top-0.5 h-3 w-3 rounded-full border-2 border-night bg-pixel" style={{ animation: "pulse-dot 1.5s infinite" }} />
          </span>
          <span className="text-left">
            <span className="block font-pixel text-[9px]">{t.chat.widgetTitle}</span>
            <span className="hidden font-term text-sm leading-none text-night/80 sm:block">{t.chat.widgetSub}</span>
          </span>
        </button>
      )}

      {open && (
        <div role="dialog" aria-label={t.chat.header} className="fixed bottom-3 right-3 z-[85] w-[min(calc(100vw-1.5rem),430px)] sm:bottom-5 sm:right-5">
          <div className="mb-2 flex items-center justify-between">
            <button
              type="button"
              onClick={() => { setOpen(false); play("select"); navigate("knowledge"); }}
              className="flex items-center gap-1.5 border-2 border-gold bg-night px-2.5 py-1 font-pixel text-[7px] text-gold transition hover:bg-gold hover:text-night"
            >
              <Maximize2 size={10} aria-hidden="true" /> {t.chat.full}
            </button>
            <button
              type="button"
              onClick={() => { setOpen(false); play("blip"); }}
              className="flex items-center gap-1.5 border-2 border-retro bg-night px-2.5 py-1 font-pixel text-[7px] text-retro transition hover:bg-retro hover:text-cream"
            >
              <X size={10} aria-hidden="true" /> {t.chat.close}
            </button>
          </div>
          <div className="shadow-chunk" style={{ animation: "chat-in 0.25s ease-out" }}>
            <ChatPanel />
          </div>
        </div>
      )}
    </>
  );
}
