import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
// Fonts are bundled locally (OFL, @fontsource) — no Google Fonts CDN.
import "@fontsource/playfair-display/latin-700.css";
import "@fontsource/playfair-display/latin-700-italic.css";
import "@fontsource/playfair-display/latin-900.css";
import "@fontsource/inter/latin-400.css";
import "@fontsource/inter/latin-500.css";
import "@fontsource/inter/latin-600.css";
import "@fontsource/inter/latin-700.css";
import "@fontsource/press-start-2p/latin-400.css";
import "@fontsource/vt323/latin-400.css";
import "./index.css";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
