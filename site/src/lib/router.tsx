import { useEffect, useState } from "react";

// Hash routing: works on GitHub Pages without server rewrites.
export const ROUTES = ["landing", "pinball", "lightgun", "skills", "knowledge", "credits"] as const;
export type Route = (typeof ROUTES)[number];

export function parseHash(): Route {
  const h = (window.location.hash || "#/").replace(/^#\/?/, "").split(/[?/]/)[0];
  return (ROUTES as readonly string[]).includes(h) ? (h as Route) : "landing";
}

export const hrefOf = (route: Route) => (route === "landing" ? "#/" : `#/${route}`);

export function navigate(route: Route) {
  const target = hrefOf(route);
  if (window.location.hash === target) window.scrollTo({ top: 0, behavior: "smooth" });
  else window.location.hash = target;
}

export function useHashRoute(): Route {
  const [route, setRoute] = useState<Route>(parseHash);

  useEffect(() => {
    const onChange = () => {
      setRoute(parseHash());
      window.scrollTo({ top: 0, behavior: "instant" as ScrollBehavior });
    };
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);

  return route;
}
