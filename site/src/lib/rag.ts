import { SOURCES, FACTS, TEMPLATES, PLAYBOOKS, type Confidence } from "../data/knowledge";
import type { Dict } from "../i18n/de";

/* ---------------- tokenize / score ---------------- */
const STOP = new Set(
  "a,an,the,and,or,but,if,then,else,for,to,of,in,on,at,by,with,from,as,is,are,was,were,be,been,being,it,its,this,that,these,those,i,you,he,she,we,they,my,your,his,her,our,their,me,him,us,them,do,does,did,doing,have,has,had,having,can,could,should,would,will,not,no,yes,so,than,too,very,just,also,how,what,when,where,which,who,why,there,here,into,out,up,down,over,under,again,once,my".split(",")
);

export function tokenize(q: string): string[] {
  return q
    .toLowerCase()
    .replace(/[^a-z0-9äöüß+.#\-/\s]/g, " ")
    .split(/\s+/)
    .map((t) => t.trim())
    .filter((t) => t.length > 1 && !STOP.has(t));
}

function fieldScore(field: string, terms: string[], weight: number): number {
  const f = field.toLowerCase();
  let s = 0;
  for (const t of terms) {
    if (!t) continue;
    if (f === t) s += 6 * weight;
    else if (f.includes(t)) s += (t.length >= 5 ? 2.4 : 1.4) * weight;
  }
  return s;
}

/* ---------------- unified search ---------------- */
export type HitKind = "fact" | "template" | "playbook" | "source";

export interface Hit {
  kind: HitKind;
  id: string;
  title: string;
  snippet: string;
  category: string;
  confidence: Confidence;
  score: number;
  matched: string[];
  needs_validation?: boolean;
}

export function searchKB(
  query: string,
  opts: { category?: string; kinds?: HitKind[]; limit?: number } = {}
): { hits: Hit[]; terms: string[] } {
  const terms = tokenize(query);
  const { category, kinds, limit = 12 } = opts;
  const hits: Hit[] = [];
  const allow = (k: HitKind) => !kinds || kinds.includes(k);

  if (allow("fact")) {
    for (const f of FACTS) {
      if (category && f.category !== category) continue;
      const matched = terms.filter((t) =>
        (f.statement + " " + f.tags.join(" ") + " " + f.subcategory + " " + Object.values(f.payload).join(" ")).toLowerCase().includes(t)
      );
      let s =
        fieldScore(f.statement, terms, 3) +
        fieldScore(f.tags.join(" "), terms, 2.2) +
        fieldScore(f.subcategory, terms, 1.6) +
        fieldScore(Object.values(f.payload).join(" "), terms, 1.4) +
        fieldScore(f.category, terms, 1);
      if (f.confidence === "high") s *= 1.08;
      if (terms.length && matched.length) hits.push({ kind: "fact", id: f.id, title: f.statement, snippet: f.payload.notes || f.payload.command || f.payload.key || f.payload.endpoint || "", category: f.category, confidence: f.confidence, score: s, matched, needs_validation: f.needs_validation });
    }
  }
  if (allow("template")) {
    for (const t of TEMPLATES) {
      const matched = terms.filter((x) => (t.title + " " + t.purpose + " " + t.platform).toLowerCase().includes(x));
      const s = fieldScore(t.title + " " + t.purpose, terms, 2.4) + fieldScore(t.platform, terms, 1.2);
      if (terms.length && matched.length) hits.push({ kind: "template", id: t.id, title: t.title, snippet: t.purpose, category: "templates", confidence: t.confidence, score: s, matched, needs_validation: t.needs_validation });
    }
  }
  if (allow("playbook")) {
    for (const p of PLAYBOOKS) {
      const body = p.title + " " + p.goal + " " + p.known_issues.join(" ") + " " + p.error_signs.join(" ");
      const matched = terms.filter((x) => body.toLowerCase().includes(x));
      const s = fieldScore(p.title + " " + p.goal, terms, 2.4) + fieldScore(p.known_issues.join(" "), terms, 1.4);
      if (terms.length && matched.length) hits.push({ kind: "playbook", id: p.id, title: p.title, snippet: p.goal, category: "playbooks", confidence: p.confidence, score: s, matched });
    }
  }
  if (allow("source")) {
    for (const s of SOURCES) {
      const matched = terms.filter((x) => (s.title + " " + s.summary + " " + s.tags.join(" ")).toLowerCase().includes(x));
      const sc = fieldScore(s.title, terms, 2) + fieldScore(s.summary, terms, 1.4) + fieldScore(s.tags.join(" "), terms, 1.6);
      if (terms.length && matched.length) hits.push({ kind: "source", id: s.id, title: s.title, snippet: s.summary, category: "sources", confidence: s.confidence, score: sc * 0.85, matched });
    }
  }

  hits.sort((a, b) => b.score - a.score);
  return { hits: hits.slice(0, limit), terms };
}

/* ---------------- answer synthesis ---------------- */
export interface ChatAnswer {
  text: string;
  hits: Hit[];
  mode: "grounded" | "weak" | "empty" | "meta";
}

const GREET = /^(hi|hey|hello|yo|servus|moin|hallo|good (morning|evening|day)|guten (morgen|tag|abend))\b/;
const THANKS = /(thank|thanks|danke|thx)/;
const HELP = /^(help|hilfe)\b|what can you|how do you work|who are you|was kannst du|wie funktionierst du/;

// Client-side only: nothing leaves the browser.
export function answerQuery(raw: string, c: Dict["chat"]): ChatAnswer {
  const q = raw.trim();
  const ql = q.toLowerCase();
  if (!q) return { text: "", hits: [], mode: "meta" };

  if (GREET.test(ql) && q.length < 30) return { mode: "meta", hits: [], text: c.greet };
  if (THANKS.test(ql) && q.length < 40) return { mode: "meta", hits: [], text: c.thanks };
  if (HELP.test(ql)) {
    return { mode: "meta", hits: [], text: c.help({ facts: FACTS.length, templates: TEMPLATES.length, playbooks: PLAYBOOKS.length }) };
  }

  const { hits } = searchKB(q, { limit: 6 });
  const strong = hits.filter((h) => h.score >= 4);
  const cited = (strong.length ? strong : hits).slice(0, 4);

  if (!hits.length || hits[0].score < 1.2) {
    return { mode: "empty", hits: [], text: c.empty({ facts: FACTS.length, q: q.slice(0, 80) }) };
  }

  const factHits = cited.filter((h) => h.kind === "fact");
  const pbHits = cited.filter((h) => h.kind === "playbook");
  const tplHits = cited.filter((h) => h.kind === "template");

  const lines: string[] = [];
  lines.push(`**${c.tldr}** — ${factHits[0] ? factHits[0].title : cited[0].title} \`[${cited[0].id}]\`\n`);

  if (factHits.length > 1) {
    lines.push(`**${c.records}**`);
    factHits.slice(0, 3).forEach((h) => {
      const f = FACTS.find((x) => x.id === h.id);
      const extra = f?.payload.command ? `\n  \`$ ${f.payload.command}\`` : f?.payload.key ? `\n  key: \`${f.payload.key}\`` : f?.payload.endpoint ? `\n  \`GET ${f.payload.endpoint}\`` : "";
      lines.push(`- ${h.title} \`[${h.id}]\`${extra}`);
    });
    lines.push(``);
  }
  if (pbHits.length) {
    const pb = PLAYBOOKS.find((p) => p.id === pbHits[0].id)!;
    lines.push(`**${c.playbook}: ${pb.title}** \`[${pb.id}]\``);
    pb.steps.slice(0, 4).forEach((s, i) => lines.push(`${i + 1}. ${s.action}`));
    if (pb.steps.length > 4) lines.push(c.moreSteps(pb.steps.length - 4));
    lines.push(``);
  }
  if (tplHits.length) {
    lines.push(`**${c.template}** ${tplHits[0].title} \`[${tplHits[0].id}]\`${tplHits[0].needs_validation ? " — " + c.verifyFirst : ""}`);
    lines.push(``);
  }

  const nv = cited.filter((h) => h.needs_validation);
  if (nv.length) lines.push(`${nv.map((h) => `\`${h.id}\``).join(", ")}: ${c.honesty}\n`);

  const doNot = PLAYBOOKS.find((p) => cited.some((h) => h.id === p.id))?.known_issues[0];
  lines.push(`**${c.doNot}** ${doNot || c.doNotDefault}`);
  lines.push(``);
  lines.push(c.snapshot);

  return { text: lines.join("\n"), hits: cited, mode: hits[0].score >= 4 ? "grounded" : "weak" };
}
