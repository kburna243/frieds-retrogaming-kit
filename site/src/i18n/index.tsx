import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import de, { type Dict } from "./de";
import en from "./en";

export type Lang = "de" | "en";
const DICTS: Record<Lang, Dict> = { de, en };
const KEY = "rck-lang";

function initialLang(): Lang {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved === "de" || saved === "en") return saved;
  } catch {
    /* storage blocked — fall back to browser language */
  }
  return (navigator.language || "").toLowerCase().startsWith("de") ? "de" : "en";
}

type I18nCtx = { lang: Lang; t: Dict; setLang: (l: Lang) => void };
const Ctx = createContext<I18nCtx | null>(null);

export function LangProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(initialLang);

  useEffect(() => {
    document.documentElement.lang = lang;
    document.title = DICTS[lang].meta.title;
    document.querySelector('meta[name="description"]')?.setAttribute("content", DICTS[lang].meta.description);
  }, [lang]);

  const setLang = (l: Lang) => {
    setLangState(l);
    try {
      localStorage.setItem(KEY, l);
    } catch {
      /* ignore */
    }
  };

  return <Ctx.Provider value={{ lang, t: DICTS[lang], setLang }}>{children}</Ctx.Provider>;
}

export function useI18n(): I18nCtx {
  const v = useContext(Ctx);
  if (!v) throw new Error("useI18n outside LangProvider");
  return v;
}
