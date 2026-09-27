import FeedbackCenter from "../feedback/FeedbackCenter";
import { FriedCharacter } from "../components/FriedCharacter";
import { Reveal } from "../lib/retro";
import { useI18n } from "../i18n";

export default function FeedbackPage() {
  const { lang } = useI18n();
  const isDe = lang === "de";

  return (
    <div className="bg-night">
      <section className="relative overflow-hidden pb-12 pt-10 border-b border-night-3">
        <div className="grid-bg absolute inset-0 opacity-60" />
        <div className="relative mx-auto max-w-5xl px-5">
          <Reveal>
            <div className="flex items-center gap-5">
              <FriedCharacter size="md" expression="happy" pose="thumbs-up" showCable={false} className="hidden shrink-0 sm:inline-flex" />
              <div>
                <div className="font-pixel text-[10px] text-pixel">COMMUNITY & FEEDBACK</div>
                <h1 className="mt-3 font-display text-4xl font-black leading-[1.05] text-cream sm:text-6xl">
                  {isDe ? "Feedback &" : "Feedback &"}{" "}
                  <span className="italic text-gold">{isDe ? "Testmatrix" : "Test Matrix"}</span>
                </h1>
              </div>
            </div>
            <div className="mt-5 h-1.5 w-16 bg-pixel" />
            <p className="mt-6 max-w-3xl text-lg leading-relaxed text-cream/85">
              {isDe
                ? "Teile deine Erfahrungen vom Cabinet, melde funktionierende Setups oder reiche gefundene Probleme ein – direkt im Browser, ohne GitHub-Account."
                : "Share your cabinet experience, report working setups or submit issues – directly in your browser without a GitHub account."}
            </p>
          </Reveal>
        </div>
      </section>

      <div>
        <FeedbackCenter />
      </div>
    </div>
  );
}
