import { useState } from "react";
import { RetroProvider } from "./lib/retro";
import { useHashRoute } from "./lib/router";
import { LangProvider, useI18n } from "./i18n";
import { BootSequence, Hud, CrtOverlay, Toast } from "./components/ui";
import Nav from "./components/Nav";
import ChatWidget from "./components/ChatWidget";
import Footer from "./sections/Footer";
import Landing from "./pages/Landing";
import GuidePage from "./pages/GuidePage";
import SkillsPage from "./pages/SkillsPage";
import KnowledgePage from "./pages/KnowledgePage";
import CreditsPage from "./pages/CreditsPage";

const BOOT_KEY = "rck-booted";

// Boot animation only on the first visit per session, never with reduced motion.
function shouldBoot(): boolean {
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return false;
  try {
    return sessionStorage.getItem(BOOT_KEY) !== "1";
  } catch {
    return false;
  }
}

function Shell() {
  const route = useHashRoute();
  const { t } = useI18n();
  const isGuide = route === "pinball" || route === "lightgun" || route === "skills";

  return (
    <>
      {/* a button, not an anchor: "#main" would be read as a route by the hash router */}
      <button
        type="button"
        onClick={() => document.getElementById("main")?.focus()}
        className="sr-only z-[120] bg-gold px-4 py-2 font-pixel text-[10px] text-night focus:not-sr-only focus:fixed focus:left-3 focus:top-3"
      >
        {t.nav.skip}
      </button>
      <div className="fixed inset-x-0 top-0 z-[80]">
        <Hud />
        <Nav route={route} />
      </div>
      <CrtOverlay />
      {/* offset for fixed HUD + Nav */}
      <main id="main" tabIndex={-1} className="page-enter pt-[94px] outline-none" key={route}>
        {route === "landing" && <Landing />}
        {route === "pinball" && <GuidePage kind="pinball" />}
        {route === "lightgun" && <GuidePage kind="lightgun" />}
        {route === "skills" && <SkillsPage />}
        {route === "knowledge" && <KnowledgePage />}
        {route === "credits" && <CreditsPage />}
      </main>
      <Footer showLegal={!isGuide} />
      <ChatWidget route={route} />
      <Toast />
    </>
  );
}

export default function App() {
  const [booting, setBooting] = useState(shouldBoot);

  const done = () => {
    try {
      sessionStorage.setItem(BOOT_KEY, "1");
    } catch {
      /* ignore */
    }
    setBooting(false);
  };

  return (
    <LangProvider>
      <RetroProvider>
        {booting && <BootSequence onDone={done} />}
        <div className={booting ? "pointer-events-none select-none" : ""} aria-hidden={booting || undefined}>
          <Shell />
        </div>
      </RetroProvider>
    </LangProvider>
  );
}
