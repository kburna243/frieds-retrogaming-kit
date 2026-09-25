/* ------------------------------------------------------------------
 * Fried's Retro Gaming Skills — Knowledge Base (web demo subset)
 * Consolidated from the Final Knowledge Pack (2026-08-06).
 * Full pack: 199 records + QA report. This file ships a curated,
 * representative subset that runs 100% client-side in the browser
 * (no server). Kit entries (FCT-KIT-*) are derived from the project
 * plan and describe work in progress.
 * ------------------------------------------------------------------ */

import { REPO_URL } from "../config";

export type Confidence = "high" | "medium" | "low";

export interface KBSource {
  id: string;
  title: string;
  url: string;
  url_status: "verified" | "unverified" | "moved" | "dead";
  authority: "official" | "community" | "vendor" | "archive";
  confidence: Confidence;
  legal: "ok" | "review";
  evergreen: boolean;
  summary: string;
  tags: string[];
}

export interface KBFact {
  id: string;
  source_id: string;
  category: string;
  subcategory: string;
  fact_type: "cli" | "config" | "api" | "hardware" | "error" | "concept" | "rule";
  statement: string;
  payload: Record<string, string>;
  confidence: Confidence;
  needs_validation?: boolean;
  tags: string[];
}

export interface KBTemplate {
  id: string;
  title: string;
  purpose: string;
  platform: string;
  template: string;
  placeholders: string[];
  validation_rules: string[];
  source_ids: string[];
  confidence: Confidence;
  needs_validation?: boolean;
}

export interface KBPlaybookStep {
  action: string;
  check?: string;
  rollback?: string;
}

export interface KBPlaybook {
  id: string;
  title: string;
  goal: string;
  steps: KBPlaybookStep[];
  safety_checks: string[];
  error_signs: string[];
  known_issues: string[];
  source_ids: string[];
  confidence: Confidence;
}

export interface KBGaps {
  id: string;
  severity: "warning" | "info";
  issue: string;
  affected: string;
  action: string;
}

export const CATEGORIES: { id: string; label: string; blurb: string }[] = [
  { id: "mame", label: "MAME", blurb: "Setup, audit, CHD, input, version drift" },
  { id: "retroarch", label: "RetroArch", blurb: "Config hierarchy, autoconfig, latency, netplay" },
  { id: "roms", label: "ROM Management", blurb: "No-Intro, Redump, TOSEC, RomVault, clrmame" },
  { id: "scrapers", label: "Scraper APIs", blurb: "ScreenScraper v2, TheGamesDB" },
  { id: "lightguns", label: "Lightguns", blurb: "Sinden, AimTrak, GUN4IR/OpenFIRE, DemulShooter" },
  { id: "crt", label: "CRT / 15 kHz", blurb: "GroovyMAME, Switchres, CRT Emudriver" },
  { id: "vpin", label: "Virtual Pinball", blurb: "VPX, VPinMAME, B2S, DOF, Pinscape" },
  { id: "frontend", label: "Frontends", blurb: "LaunchBox, RetroBat, ES-DE, Batocera gaps" },
  { id: "kit", label: "Retro Cabinet Kit", blurb: "Installers and skills of this project (work in progress)" },
  { id: "agent", label: "Agent Rules", blurb: "Permanent guardrails derived from QA" },
];

export const SOURCES: KBSource[] = [
  { id: "SRC-KIT-001", title: "retro-cabinet-kit — project plan and README", url: REPO_URL, url_status: "unverified", authority: "official", confidence: "medium", legal: "ok", evergreen: false, summary: "Plan of the retro-cabinet-kit: guided pinball and lightgun installers on a shared core, plus retro skills. Work in progress.", tags: ["kit", "installer", "pinball", "lightgun", "skills"] },
  { id: "SRC-MAME-001", title: "MAME Official Documentation", url: "https://docs.mamedev.org/", url_status: "verified", authority: "official", confidence: "high", legal: "ok", evergreen: false, summary: "Canonical MAME docs: setup, CLI, mame.ini, ROM audit, CHD handling. Note Rust migration in progress around 0.289.", tags: ["mame", "docs", "setup"] },
  { id: "SRC-MAME-002", title: "MAME Command-Line Reference (-listxml, -verifyroms)", url: "https://docs.mamedev.org/commandline/", url_status: "verified", authority: "official", confidence: "high", legal: "ok", evergreen: false, summary: "CLI surface for set auditing and machine metadata. Prefer -listxml at runtime over static copies.", tags: ["mame", "cli", "audit"] },
  { id: "SRC-RA-001", title: "Libretro Docs — RetroArch Configuration", url: "https://docs.libretro.com/", url_status: "verified", authority: "official", confidence: "high", legal: "ok", evergreen: false, summary: "Config hierarchy (global → core → content-directory → per-game overrides), autoconfig profiles, playlists, latency features, netplay.", tags: ["retroarch", "config"] },
  { id: "SRC-ROM-001", title: "No-Intro DAT-o-MATIC", url: "https://datomatic.no-intro.org/", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "DATs for cartridge/disc dumps excluding bad dumps and hacks. Standard for console ROM auditing.", tags: ["dat", "no-intro", "audit"] },
  { id: "SRC-ROM-002", title: "Redump.org", url: "http://redump.org/", url_status: "verified", authority: "community", confidence: "medium", legal: "ok", evergreen: false, summary: "Optical-disc preservation DATs. Service disrupted June 2026 — monitor availability before recommending.", tags: ["dat", "redump", "optical"] },
  { id: "SRC-ROM-003", title: "TOSEC — The Old School Emulation Center", url: "https://www.tosecdev.org/", url_status: "verified", authority: "archive", confidence: "high", legal: "ok", evergreen: true, summary: "Naming convention and DATs for home-computer software. Evergreen naming reference; cite with age context.", tags: ["dat", "tosec", "naming"] },
  { id: "SRC-ROM-004", title: "RomVault", url: "https://www.romvault.com/", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "ROM manager with DAT-driven fix/merge workflow. Strong for MAME full-set maintenance.", tags: ["rom-manager", "dat"] },
  { id: "SRC-ROM-005", title: "clrmamepro", url: "https://mamedev.emulab.it/clrmamepro/", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "Classic DAT auditor/rebuilder. A community successor project exists — verify current fork before deep CLI advice.", tags: ["rom-manager", "dat", "audit"] },
  { id: "SRC-SCR-001", title: "ScreenScraper API v2 Documentation", url: "https://www.screenscraper.fr/api.php", url_status: "verified", authority: "official", confidence: "high", legal: "ok", evergreen: false, summary: "Full v2 API incl. quota fields, error codes, systemesListe.php. Free-apps-only license.", tags: ["scraper", "api", "quota"] },
  { id: "SRC-SCR-002", title: "TheGamesDB API + OpenAPI Spec", url: "https://api.thegamesdb.net/", url_status: "verified", authority: "official", confidence: "high", legal: "ok", evergreen: false, summary: "Games metadata API with OpenAPI spec, hash lookup, delta sync. Cache /v1/Platforms and /v1/Genres at runtime.", tags: ["scraper", "api", "metadata"] },
  { id: "SRC-GUN-001", title: "Sinden Lightgun Wiki & Support", url: "https://www.sindenlightgun.com/", url_status: "verified", authority: "vendor", confidence: "high", legal: "ok", evergreen: false, summary: "Camera gun requiring visible border for tracking. Documented traps: border off, HDR/warped screens, multi-gun assignment.", tags: ["sinden", "lightgun"] },
  { id: "SRC-GUN-002", title: "Ultimarc AimTrak Utilities", url: "https://www.ultimarc.com/aimtrak.html", url_status: "verified", authority: "vendor", confidence: "medium", legal: "ok", evergreen: false, summary: "IR-bar gun with firmware util. Detail values in ctrlr XML template need validation against AimTrak PDF.", tags: ["aimtrak", "lightgun"] },
  { id: "SRC-GUN-003", title: "GUN4IR / OpenFIRE (open-source lightgun)", url: "https://github.com/OpenFIREGame/OpenFIRE", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "DIY camera/IMU gun firmware. Calibration per display, LED placement matters, multi-gun via distinct device IDs.", tags: ["gun4ir", "openfire", "diy"] },
  { id: "SRC-GUN-004", title: "DemulShooter Documentation", url: "https://github.com/argonlefou/DemulShooter", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "Per-game lightgun injection for arcade dumps. Critical: per-ROM args (-target / -rom), calibration files, multi-gun ordering.", tags: ["demulshooter", "args"] },
  { id: "SRC-CRT-001", title: "GroovyMAME & Switchres", url: "https://github.com/antonioginer/GroovyMAME", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "Modeline generation for 15 kHz arcade monitors. Super resolutions (2560) simplify setup. Always pair with 31 kHz boot warning.", tags: ["groovymame", "15khz", "modeline"] },
  { id: "SRC-CRT-002", title: "CRT Emudriver", url: "https://geedorah.com/eiusdemmodi/forum/viewforum.php?id=9", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "Patched AMD drivers exposing 15 kHz modes. GPU compatibility constrained (no RDNA). Install order matters.", tags: ["crt-emudriver", "amd", "driver"] },
  { id: "SRC-CRT-003", title: "GroovyArcade Linux", url: "https://github.com/substring/os2d-groovymame", url_status: "verified", authority: "community", confidence: "medium", legal: "ok", evergreen: false, summary: "Arch-based live distro with GroovyMAME pre-tuned. Verify current ISO lineage before recommending.", tags: ["groovyarcade", "linux"] },
  { id: "SRC-VP-001", title: "Visual Pinball X (VPX) Wiki", url: "https://github.com/vpinball/pinmame/wiki", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "VPX setup: tables, VPinMAME ROMs, B2S backglass, DOF teatime. Version-pin everything.", tags: ["vpx", "pinball"] },
  { id: "SRC-VP-002", title: "DOF — DirectOutput Framework", url: "http://directoutput.github.io/DirectOutput/", url_status: "verified", authority: "community", confidence: "medium", legal: "ok", evergreen: false, summary: "Three codebases: 32-bit original R3, 64-bit mjrgh R3++, standalone libdof/WIP. NEVER recommend without bitness question.", tags: ["dof", "force-feedback"] },
  { id: "SRC-VP-003", title: "B2S Backglass Server Docs", url: "https://github.com/vpinball/b2s-backglass", url_status: "verified", authority: "community", confidence: "medium", legal: "ok", evergreen: false, summary: "Backglass rendering + ScreenRes.txt layout. Exact ScreenRes format needs validation — mark as verify-first.", tags: ["b2s", "backglass"] },
  { id: "SRC-VP-004", title: "dmd-extensions (freezy)", url: "https://github.com/freezy/dmd-extensions", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "DMD routing to real/virtual displays incl. ZeDMD/Pin2DMD. DmdDevice.ini is the control surface.", tags: ["dmd", "display"] },
  { id: "SRC-FE-001", title: "LaunchBox / BigBox Docs", url: "https://www.launchbox-app.com/", url_status: "verified", authority: "vendor", confidence: "medium", legal: "review", confidence_note: "Games DB has usage restrictions; no public API — never invent endpoints or DB schemas.",
  legal_note: "LaunchBox Games DB scraping restricted; link, don't mirror.", evergreen: false, summary: "Windows frontend. SQLite migration noted. No public Games-DB API exists.", tags: ["launchbox", "frontend"] } as KBSource,
  { id: "SRC-FE-002", title: "RetroBat Wiki", url: "https://wiki.retrobat.ovh/", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "Windows EmulationStation fork with RetroArch cores. Bios checker + ES config surface.", tags: ["retrobat", "frontend"] },
  { id: "SRC-FE-003", title: "EmuDeck / ES-DE Documentation", url: "https://es-de.org/", url_status: "verified", authority: "community", confidence: "high", legal: "ok", evergreen: false, summary: "EmulationStation Desktop Edition. 3.4.1 noted April 2026 — verify current before version-specific advice.", tags: ["es-de", "frontend"] },
];

export const FACTS: KBFact[] = [
  // ---- Kit (work in progress, derived from the project plan) ----
  { id: "FCT-KIT-001", source_id: "SRC-KIT-001", category: "kit", subcategory: "pinball", fact_type: "concept", statement: "The pinball installer (work in progress) sets up a PinUP Popper build you bring (Baller structure): move it on this PC or rebuild on a fresh Windows, rewrite paths, register components, calibrate screens, back up.", payload: { notes: "Steps: source, target, prerequisites, copy, rewrite paths, register, Future Pinball/BAM, screens, finish. Each step is checked, run and verified." }, confidence: "medium", tags: ["kit", "pinball", "installer", "popper", "pinup", "baller", "umzug", "neuaufbau", "relocate"] },
  { id: "FCT-KIT-002", source_id: "SRC-KIT-001", category: "kit", subcategory: "lightgun", fact_type: "concept", statement: "The lightgun installer (work in progress) makes RetroBat Wiimote-ready: Gunmote, ViGEmBus, DolphinBar in Mode 4, profile automation, TeknoParrot, MAME, Demul + DemulShooter, Model 2/3, DuckStation, PCSX2, game lists — calibration comes last.", payload: { notes: "Gunmote is a guided download from github.com/gunmotelabs/Gunmote. DuckStation and PCSX2 are guided only, no automatic mapping in v1." }, confidence: "medium", tags: ["kit", "lightgun", "installer", "retrobat", "wiimote", "gunmote", "dolphinbar", "vigembus", "demulshooter", "teknoparrot"] },
  { id: "FCT-KIT-003", source_id: "SRC-KIT-001", category: "kit", subcategory: "legal", fact_type: "rule", statement: "The kit contains no ROMs, BIOS files, purchased builds or PinUP Popper — you bring them. Free tools and drivers are downloaded only from their official sources and never redistributed.", payload: { notes: "Download allowlist of official hosts; Authenticode signature required where available, otherwise shown as unsigned." }, confidence: "high", tags: ["kit", "roms", "rom", "bios", "legal", "download", "rechtlich", "popper", "official"] },
  { id: "FCT-KIT-004", source_id: "SRC-KIT-001", category: "kit", subcategory: "method", fact_type: "rule", statement: "Every kit step follows Test (precondition), Invoke (supports -WhatIf) and Verify (mandatory); a step turns green only after Verify, and each step can run as its own script.", payload: { notes: "Progress is stored per package so an interrupted run resumes without redoing work." }, confidence: "high", tags: ["kit", "step", "verify", "check", "schritt", "geprüft", "whatif", "resume"] },
  { id: "FCT-KIT-005", source_id: "SRC-KIT-001", category: "kit", subcategory: "skills", fact_type: "concept", statement: "Install a skill in Claude Code by copying its folder (with SKILL.md) to .claude/skills/ in the project or ~/.claude/skills/; for other agents, provide SKILL.md as context.", payload: { notes: "The public retro skills are being depersonalized and will be published in English as a separate step." }, confidence: "medium", tags: ["kit", "skill", "skills", "install", "installieren", "claude", "agent", "skill.md"] },
  { id: "FCT-KIT-006", source_id: "SRC-KIT-001", category: "kit", subcategory: "safety", fact_type: "rule", statement: "Before writing, the kit checks running programs (it asks, never kills) and backs up to a ZIP with a SHA256 manifest plus registry exports.", payload: { notes: "Registry imports always pass a relocate filter; reg import merges and deletes nothing." }, confidence: "high", tags: ["kit", "backup", "sicherung", "processes", "registry", "zip", "sha256"] },
  // ---- MAME ----
  { id: "FCT-MAME-001", source_id: "SRC-MAME-002", category: "mame", subcategory: "audit", fact_type: "cli", statement: "Audit a MAME set against the exact emulator build with -verifyroms before changing anything; version mismatch is the #1 false 'broken ROM' cause.", payload: { command: "mame.exe -verifyroms", notes: "Run from the MAME dir. Missing/dump-status lines are data, not errors per se.", related: "FCT-MAME-002" }, confidence: "high", tags: ["audit", "verifyroms", "version"] },
  { id: "FCT-MAME-002", source_id: "SRC-MAME-002", category: "mame", subcategory: "metadata", fact_type: "cli", statement: "Use mame -listxml at runtime to obtain machine metadata for the installed build instead of trusting static third-party lists.", payload: { command: "mame.exe -listxml > mame-list.xml", notes: "Large output (~100MB+). Parse, don't eyeball. Regenerate after every MAME update." }, confidence: "high", tags: ["listxml", "metadata", "runtime"] },
  { id: "FCT-MAME-003", source_id: "SRC-MAME-001", category: "mame", subcategory: "config", fact_type: "config", statement: "mame.ini rompath can hold multiple semicolon-separated paths; MAME searches them in order. Wrong order silently shadows fixed sets.", payload: { key: "rompath", example: "rompath roms;roms-fixed;../mame-merged", notes: "Generate a fresh baseline with 'mame -createconfig' after major upgrades, then re-apply your diffs." }, confidence: "high", tags: ["mame.ini", "rompath"] },
  { id: "FCT-MAME-004", source_id: "SRC-MAME-001", category: "mame", subcategory: "chd", fact_type: "cli", statement: "Convert and verify optical images with chdman (createcd/createdvd/verify). CHDs are version-tied: a 0.250 CHD is not guaranteed valid on 0.280.", payload: { command: "chdman verify -i game.chd", notes: "createcd needs cue+bin; createdvd needs ISO. Keep source until verify passes." }, confidence: "high", tags: ["chd", "chdman", "optical"] },
  { id: "FCT-MAME-005", source_id: "SRC-MAME-001", category: "mame", subcategory: "input", fact_type: "config", statement: "MAME lightgun input needs both the OS-visible mouse device AND correct in-game input mapping; multi-mouse setups require -multimouse.", payload: { key: "-multimouse", notes: "Without -multimouse, two guns collapse into one cursor. Verify in Windows Game Controllers first." }, confidence: "high", tags: ["lightgun", "multimouse", "input"] },
  { id: "FCT-MAME-006", source_id: "SRC-MAME-001", category: "mame", subcategory: "versions", fact_type: "concept", statement: "MAME configs and ROM definitions drift between releases (0.250 → 0.280 broke assumptions). Always state the exact build; never port advice across versions unverified.", payload: { notes: "Rust migration in progress ~0.289. Treat pre-2024 forum advice as expired until re-verified." }, confidence: "high", tags: ["version-drift", "0.280"] },
  // ---- RetroArch ----
  { id: "FCT-RA-001", source_id: "SRC-RA-001", category: "retroarch", subcategory: "config", fact_type: "concept", statement: "RetroArch config hierarchy: retroarch.cfg (global) → core override → content-directory override → per-game override. Lower levels win.", payload: { notes: "Edits in the wrong layer 'mysteriously revert'. Check Overrides menu before hand-editing files." }, confidence: "high", tags: ["overrides", "hierarchy"] },
  { id: "FCT-RA-002", source_id: "SRC-RA-001", category: "retroarch", subcategory: "input", fact_type: "config", statement: "Autoconfig profiles in autoconfig/ match pads by VID/PID + name. A renamed device silently falls back to defaults.", payload: { key: "input_joypad_driver", notes: "Keep custom profiles in a separate dir and back them up before RetroArch updates." }, confidence: "high", tags: ["autoconfig", "gamepad", "vid-pid"] },
  { id: "FCT-RA-003", source_id: "SRC-RA-001", category: "retroarch", subcategory: "playlists", fact_type: "concept", statement: "Playlists reference ROM paths + core path + database entry. Moving the ROM folder without updating playlists yields 'file not found' on scan-clean setups.", payload: { notes: "Prefer directory scans over manual entries; validate playlist JSON after moves." }, confidence: "medium", tags: ["playlists", "scan"] },
  { id: "FCT-RA-004", source_id: "SRC-RA-001", category: "retroarch", subcategory: "latency", fact_type: "config", statement: "Runahead reduces input latency by re-simulating frames but doubles core CPU cost per frame and breaks on some cores. Measure, don't assume.", payload: { key: "run_ahead_enabled / run_ahead_frames", notes: "Start at 1 frame. Preemptive frames is the less invasive alternative on supported cores." }, confidence: "high", tags: ["runahead", "latency"] },
  { id: "FCT-RA-005", source_id: "SRC-RA-001", category: "retroarch", subcategory: "netplay", fact_type: "concept", statement: "Netplay requires identical core version + identical content checksum on both peers. 'Same game' is not enough — same file hash is.", payload: { notes: "Share the exact ROM + core .dll/.so version first. Desyncs are a fingerprint problem." }, confidence: "high", tags: ["netplay", "sync"] },
  // ---- ROM management ----
  { id: "FCT-ROM-001", source_id: "SRC-ROM-001", category: "roms", subcategory: "dat", fact_type: "concept", statement: "No-Intro DATs cover 'clean' dumps (no bad dumps, hacks, or overdumps) — the right reference for console cartridge auditing.", payload: { notes: "Pair No-Intro DAT + your set in RomVault/clrmame; fixdat loop until zero missing." }, confidence: "high", tags: ["no-intro", "dat"] },
  { id: "FCT-ROM-002", source_id: "SRC-ROM-002", category: "roms", subcategory: "dat", fact_type: "concept", statement: "Redump DATs are the optical-disc reference, but the service was disrupted in June 2026. Verify availability and mirror DATs locally before promising results.", payload: { notes: "Status watch item (QA-0018). Never link ROM downloads — DATs only." }, confidence: "medium", tags: ["redump", "dat", "status-watch"] },
  { id: "FCT-ROM-003", source_id: "SRC-ROM-003", category: "roms", subcategory: "naming", fact_type: "concept", statement: "TOSEC naming encodes publisher/year/media flags in brackets. Parse it for organization; never hand-rename large sets.", payload: { notes: "Evergreen reference — cite with age context for tooling advice." }, confidence: "high", tags: ["tosec", "naming"] },
  { id: "FCT-ROM-004", source_id: "SRC-ROM-004", category: "roms", subcategory: "tools", fact_type: "cli", statement: "RomVault 'Fix DATs' workflow: load DAT → scan → fix with trrntzip-aware rebuild. Work on a COPY of the set; keep the fixDAT until verified.", payload: { notes: "MAME full-set + matching DAT version is the only sane input pair." }, confidence: "high", tags: ["romvault", "rebuild"] },
  { id: "FCT-ROM-005", source_id: "SRC-ROM-005", category: "roms", subcategory: "tools", fact_type: "concept", statement: "clrmamepro remains the deep-audit reference, but CLI details and the community successor need verification before scripting advice.", payload: { notes: "Gap QA-0009/QA-0013: don't generate clrmame CLI scripts or FBNeo DAT pipelines from memory." }, confidence: "medium", tags: ["clrmame", "audit", "gap"] },
  { id: "FCT-ROM-006", source_id: "SRC-ROM-001", category: "roms", subcategory: "firmware", fact_type: "error", statement: "'0 files' on a BIOS/firmware folder that is clearly populated almost always means wrong expected path or wrong DAT profile — not missing files.", payload: { notes: "Triangulate: frontend-expected path vs actual path vs DAT name. Case sensitivity on network shares bites." }, confidence: "high", tags: ["bios", "firmware", "0-files"] },
  // ---- Scrapers ----
  { id: "FCT-SCR-001", source_id: "SRC-SCR-001", category: "scrapers", subcategory: "api", fact_type: "api", statement: "ScreenScraper v2 requires devid/devpassword plus ssid/sspassword for quota-bearing calls. Quota fields must be read before every scrape run — mandatory, not a tip.", payload: { endpoint: "https://www.screenscraper.fr/api2/ssuserInfos.php", notes: "Cache aggressively. A 29-hour scan can be healthy if throttled by quota + 100Mbit link." }, confidence: "high", tags: ["screenscraper", "quota", "api"] },
  { id: "FCT-SCR-002", source_id: "SRC-SCR-001", category: "scrapers", subcategory: "mapping", fact_type: "api", statement: "Resolve frontend system names via systemesListe.php at runtime (nom_recalbox/retropie/launchbox/hyperspin) instead of hardcoding mappings.", payload: { endpoint: "https://www.screenscraper.fr/api2/systemesListe.php", notes: "Mappings drift; runtime lookup is the documented pattern." }, confidence: "high", tags: ["screenscraper", "mapping"] },
  { id: "FCT-SCR-003", source_id: "SRC-SCR-001", category: "scrapers", subcategory: "legal", fact_type: "rule", statement: "ScreenScraper data may only power free applications. Commercial use needs separate clearance — route around it, don't rationalize it.", payload: { notes: "License guardrail. Applies to any agent-suggested integration." }, confidence: "high", tags: ["license", "commercial"] },
  { id: "FCT-SCR-004", source_id: "SRC-SCR-002", category: "scrapers", subcategory: "api", fact_type: "api", statement: "TheGamesDB exposes Games/ByGameName, hash lookup, Platforms and Genres endpoints plus an OpenAPI spec. Cache Platforms/Genres; sync deltas, not full dumps.", payload: { endpoint: "https://api.thegamesdb.net/v1/Games/ByGameName", notes: "Spec: api.thegamesdb.net/spec.yaml. API key required; handle 429 with backoff." }, confidence: "high", tags: ["thegamesdb", "api", "openapi"] },
  // ---- Lightguns ----
  { id: "FCT-GUN-001", source_id: "SRC-GUN-001", category: "lightguns", subcategory: "sinden", fact_type: "hardware", statement: "Sinden guns need the white border visible on screen to track. Missing/covered border = drift or total loss, usually misdiagnosed as 'bad calibration'.", payload: { notes: "Check: border enabled in Sinden software, no HDR tone-mapping washing it out, no windowed-mode cropping." }, confidence: "high", tags: ["sinden", "border", "tracking"] },
  { id: "FCT-GUN-002", source_id: "SRC-GUN-001", category: "lightguns", subcategory: "sinden", fact_type: "error", statement: "Two Sindens need stable, distinct camera assignment. Swapped guns after reboot is a USB-enumeration issue — fix with port pinning, not recalibration.", payload: { notes: "Label physical ports. Recalibrating a swapped gun corrupts the working profile." }, confidence: "high", tags: ["sinden", "multi-gun", "usb"] },
  { id: "FCT-GUN-003", source_id: "SRC-GUN-002", category: "lightguns", subcategory: "aimtrak", fact_type: "hardware", statement: "AimTrak accuracy depends on IR-bar geometry and sensor firmware. Exact ctrlr-XML values need validation against the AimTrak PDF — structure known, magic numbers not guessed.", payload: { notes: "Template TPL-GUN-0002 flagged needs_validation. Verify-first, don't invent values." }, confidence: "medium", tags: ["aimtrak", "ir-bar", "needs-validation"] },
  { id: "FCT-GUN-004", source_id: "SRC-GUN-003", category: "lightguns", subcategory: "gun4ir", fact_type: "hardware", statement: "GUN4IR/OpenFIRE calibration is per-display and LED-placement sensitive. Changing monitor or LED strip invalidates prior calibration by design.", payload: { notes: "Multi-gun works via distinct device IDs. Document LED positions with photos." }, confidence: "high", tags: ["gun4ir", "openfire", "calibration"] },
  { id: "FCT-GUN-005", source_id: "SRC-GUN-004", category: "lightguns", subcategory: "demulshooter", fact_type: "cli", statement: "DemulShooter injects per-ROM: wrong -target/-rom pairing silently does nothing. Offsets live in per-game config — global recalibration is the classic dead end.", payload: { command: "DemulShooter.exe -target=ringwide -rom=lgj", notes: "After updates, re-check per-game profiles first; defaults may have reset." }, confidence: "high", tags: ["demulshooter", "args", "offset"] },
  { id: "FCT-GUN-006", source_id: "SRC-GUN-004", category: "lightguns", subcategory: "demulshooter", fact_type: "error", statement: "Gun 'aims left by N cm in exactly one game' points at that game's DemulShooter profile/offset — not at hardware calibration.", payload: { notes: "Contra-test: other gun games still on target? Then hardware is innocent." }, confidence: "high", tags: ["demulshooter", "offset", "diagnosis"] },
  // ---- CRT ----
  { id: "FCT-CRT-001", source_id: "SRC-CRT-001", category: "crt", subcategory: "groovymame", fact_type: "config", statement: "GroovyMAME + Switchres generate authentic 15 kHz modelines per game. Super resolutions (e.g. 2560-wide) reduce modeline count and stabilize picky chassis.", payload: { key: "super_width / monitor preset", notes: "Start from the preset matching your chassis (arcade_15, d9800, etc.), then tune." }, confidence: "high", tags: ["groovymame", "switchres", "modeline"] },
  { id: "FCT-CRT-002", source_id: "SRC-CRT-002", category: "crt", subcategory: "driver", fact_type: "hardware", statement: "CRT Emudriver requires compatible AMD cards — RDNA and newer are NOT supported. Verify the card against the compatibility list before install day.", payload: { notes: "Install order: clean DDU → Emudriver → VMMaker → test 15kHz on a safe display first." }, confidence: "high", tags: ["crt-emudriver", "amd", "compatibility"] },
  { id: "FCT-CRT-003", source_id: "SRC-CRT-001", category: "crt", subcategory: "safety", fact_type: "rule", statement: "SAFETY: 15 kHz monitors can be damaged by 31 kHz+ signals during boot. Always plan the boot chain (BIOS splash, Windows logo) before first power-on.", payload: { notes: "Mandatory warning with every 15kHz recommendation. No exceptions." }, confidence: "high", tags: ["safety", "15khz", "boot"] },
  { id: "FCT-CRT-004", source_id: "SRC-CRT-003", category: "crt", subcategory: "distro", fact_type: "concept", statement: "GroovyArcade is a pre-tuned Arch live environment for GroovyMAME. Verify current ISO lineage and kernel/driver pairing before recommending.", payload: { notes: "Good for dedicated cabs; less flexible than a hand-built setup." }, confidence: "medium", tags: ["groovyarcade", "linux"] },
  // ---- VPin ----
  { id: "FCT-VP-001", source_id: "SRC-VP-001", category: "vpin", subcategory: "vpx", fact_type: "concept", statement: "VPX stack order: table (.vpx) → VPinMAME ROM → B2S backglass → DOF/DMD routing. Version-pin every layer; mixed-era components cause 'black backglass' mysteries.", payload: { notes: "Fingerprint must include VPX build + VPinMAME build + B2S version." }, confidence: "high", tags: ["vpx", "stack", "versions"] },
  { id: "FCT-VP-002", source_id: "SRC-VP-002", category: "vpin", subcategory: "dof", fact_type: "rule", statement: "DOF has THREE codebases: 32-bit original R3, 64-bit mjrgh R3++, standalone libdof/WIP. Never recommend a DOF build without asking bitness + standalone-vs-VPX first.", payload: { notes: "Permanent agent rule QA-0017. Wrong-bitness DOF fails silently or crashes tables." }, confidence: "high", tags: ["dof", "bitness", "rule"] },
  { id: "FCT-VP-003", source_id: "SRC-VP-003", category: "vpin", subcategory: "b2s", fact_type: "config", statement: "B2S ScreenRes.txt defines playfield/backglass/DMD rectangles. Exact format details need validation — deliver as verify-first, never as gospel.", payload: { notes: "Template TPL-VPIN-0003 flagged needs_validation." }, confidence: "medium", tags: ["b2s", "screenres", "needs-validation"] },
  { id: "FCT-VP-004", source_id: "SRC-VP-004", category: "vpin", subcategory: "dmd", fact_type: "config", statement: "dmd-extensions routes the DMD via DmdDevice.ini to virtual, Pin2DMD, or ZeDMD targets. One active output section at a time — stacked sections fight.", payload: { key: "DmdDevice.ini [virtualdmd] / [pin2dmd] / [zedmd]", notes: "After driver updates, re-verify the [browserstream] and vsync settings." }, confidence: "high", tags: ["dmd", "zedmd", "pin2dmd"] },
  { id: "FCT-VP-005", source_id: "SRC-VP-001", category: "vpin", subcategory: "power", fact_type: "error", statement: "Smart-plug cabinets: Windows must fully shut down BEFORE the plug cuts power, or NTFS/config corruption follows. TVs in standby may still report 'connected'.", payload: { notes: "Observed traps: session-end process kills over SSH, phantom-connected standby TVs, IR wake races." }, confidence: "high", tags: ["smart-plug", "shutdown", "standby"] },
  { id: "FCT-VP-006", source_id: "SRC-VP-001", category: "vpin", subcategory: "frontend", fact_type: "concept", statement: "PinballY / PinballX are VPIN frontends with per-table media + launch scripts. Keep launch scripts in version control; they ARE the setup.", payload: { notes: "Gap QA-0014: PinballX-XML, Pinscape calibration, DOF toy events are next deep-dive." }, confidence: "medium", tags: ["pinbally", "pinballx", "frontend"] },
  // ---- Frontends ----
  { id: "FCT-FE-001", source_id: "SRC-FE-001", category: "frontend", subcategory: "launchbox", fact_type: "rule", statement: "No public LaunchBox Games-DB API or documented schema exists. Never generate endpoints, DB paths, or SQL for it — link to official docs instead.", payload: { notes: "Permanent agent rule QA-0003. SQLite migration noted; internals still private." }, confidence: "high", tags: ["launchbox", "api", "rule"] },
  { id: "FCT-FE-002", source_id: "SRC-FE-002", category: "frontend", subcategory: "retrobat", fact_type: "concept", statement: "RetroBat bundles EmulationStation + RetroArch cores with a BIOS checker. Run the BIOS checker before blaming cores for boot failures.", payload: { notes: "RetroBat 4.x layout assumed — verify on 5.x before path-specific advice." }, confidence: "high", tags: ["retrobat", "bios"] },
  { id: "FCT-FE-003", source_id: "SRC-FE-003", category: "frontend", subcategory: "es-de", fact_type: "concept", statement: "ES-DE 3.4.1 (April 2026) changed theming/scraper surfaces. Pin the ES-DE version in the fingerprint before config advice.", payload: { notes: "Verify current release; ES-DE moves fast." }, confidence: "medium", tags: ["es-de", "versions"] },
  { id: "FCT-FE-004", source_id: "SRC-FE-002", category: "frontend", subcategory: "batocera", fact_type: "concept", statement: "Batocera/Recalbox/Pegasus/Attract-Mode have Phase-1 index coverage only — no verified artifacts yet. Say so explicitly instead of improvising.", payload: { notes: "Gap QA-0011. Next expansion wave." }, confidence: "low", tags: ["batocera", "gap"] },
  // ---- Agent rules ----
  { id: "FCT-AG-001", source_id: "SRC-MAME-001", category: "agent", subcategory: "method", fact_type: "rule", statement: "No fix without a fingerprint: OS+build, frontend+version, emulator+version, peripherals, last change, prior state. Ask max 3 missing items at once.", payload: { notes: "Core skill rule. The fingerprint script is read-only; it changes nothing." }, confidence: "high", tags: ["fingerprint", "method"] },
  { id: "FCT-AG-002", source_id: "SRC-MAME-001", category: "agent", subcategory: "method", fact_type: "rule", statement: "Change exactly ONE thing per fix attempt, with a backup first and a verification step after. Multi-change fixes are ladder failures.", payload: { notes: "Backup → single change → verify → document. No shortcuts." }, confidence: "high", tags: ["one-change", "backup", "ladder"] },
  { id: "FCT-AG-003", source_id: "SRC-SCR-001", category: "agent", subcategory: "evidence", fact_type: "rule", statement: "Label every claim: VERIFIED (tested), REPORTED (sourced), UNCONFIRMED (plausible). Never invent confidence percentages.", payload: { notes: "'Confidence 0.91' is cosplay. Three tiers, honest labels." }, confidence: "high", tags: ["evidence", "honesty"] },
  { id: "FCT-AG-004", source_id: "SRC-VP-002", category: "agent", subcategory: "dead-ends", fact_type: "rule", statement: "Every answer ships a DO-NOT-DO section: the known dead ends for that exact symptom. Undocumented dead ends are why threads run forever.", payload: { notes: "Most valuable section. Mine incident logs and playbook known_issues." }, confidence: "high", tags: ["do-not-do", "dead-ends"] },
  { id: "FCT-AG-005", source_id: "SRC-ROM-002", category: "agent", subcategory: "freshness", fact_type: "rule", statement: "Every recommendation carries a snapshot: date + versions. Advice without a version is advice with an unknown expiry date.", payload: { notes: "Re-check sources quarterly; track last_checked and source_last_updated." }, confidence: "high", tags: ["snapshot", "freshness"] },
  { id: "FCT-AG-006", source_id: "SRC-ROM-004", category: "agent", subcategory: "legal", fact_type: "rule", statement: "No ROM/BIOS download links, ever. Manage, audit, configure — yes. Provenance of your dumps is your business.", payload: { notes: "68/70 pack sources legal:ok, 2 review with documented restrictions." }, confidence: "high", tags: ["legal", "no-roms"] },
];

export const TEMPLATES: KBTemplate[] = [
  {
    id: "TPL-MAME-0001", title: "mame.ini — sane cabinet baseline", purpose: "Starting config for a Windows cabinet with fixed ROM set + CHDs",
    platform: "Windows / MAME 0.28x", confidence: "high",
    template: "rompath                   {{ROMPATH}}\nswpath                    {{ROMPATH}}\ncfg_directory             {{CFG_DIR}}\nartwork_crop              1\nvideo                     {{VIDEO_API}}\nnumscreens                1\nmultimouse                {{MULTIMOUSE}}\nlightgun                  1\n", placeholders: ["{{ROMPATH}}", "{{CFG_DIR}}", "{{VIDEO_API}}", "{{MULTIMOUSE}}"],
    validation_rules: ["rompath entries must exist before launch", "multimouse=1 only with 2+ gun devices", "regenerate via mame -createconfig after major upgrades"],
    source_ids: ["SRC-MAME-001"],
  },
  {
    id: "TPL-MAME-0002", title: "ROM folder layout — MAME split set", purpose: "Canonical folder structure for split/merged sets + CHDs + samples",
    platform: "any", confidence: "high",
    template: "mame/\n  roms/            # split set zips, e.g. pacman.zip\n  roms-chd/<game>/  # CHD per folder, e.g. killerinstinct/killerinst.chd\n  samples/         # analog audio samples\n  cfg/             # per-game input cfgs (BACKUP THIS)\n  nvram/  memcard/  hi/  # machine state — exclude from sync tools\n", placeholders: [],
    validation_rules: ["CHD filename must match driver expectation (check -listxml)", "never store downloads-in-progress inside roms/"],
    source_ids: ["SRC-MAME-001", "SRC-ROM-004"],
  },
  {
    id: "TPL-RA-0001", title: "retroarch.cfg — latency starter", purpose: "Low-latency baseline without breaking exotic cores",
    platform: "RetroArch 1.1x+", confidence: "medium",
    template: "video_driver = \"{{VIDEO_DRIVER}}\"\nvideo_vsync = \"true\"\nvideo_hard_sync = \"true\"\nrun_ahead_enabled = \"{{RUNAHEAD}}\"\nrun_ahead_frames = \"1\"\ninput_joypad_driver = \"{{JOYPAD_DRIVER}}\"\n", placeholders: ["{{VIDEO_DRIVER}}", "{{RUNAHEAD}}", "{{JOYPAD_DRIVER}}"],
    validation_rules: ["test runahead per-core; disable on desync-prone cores", "hard_sync only on GL/d3d11+ paths that support it"],
    source_ids: ["SRC-RA-001"],
  },
  {
    id: "TPL-GUN-0001", title: "DemulShooter per-game profile", purpose: "Per-ROM injection args + offset for one gun game",
    platform: "Windows / DemulShooter", confidence: "high",
    template: "; {{ROM}} on {{TARGET}}\ncmd = DemulShooter.exe -target={{TARGET}} -rom={{ROM}}\n; per-game calibration (NOT global):\naxis_x_offset = {{X_OFFSET}}\naxis_y_offset = {{Y_OFFSET}}\n; gun order: P1={{GUN1_ID}} P2={{GUN2_ID}}\n", placeholders: ["{{ROM}}", "{{TARGET}}", "{{X_OFFSET}}", "{{Y_OFFSET}}", "{{GUN1_ID}}", "{{GUN2_ID}}"],
    validation_rules: ["-target must match the emulator family exactly", "offsets are per-ROM; global recalibration is a dead end", "verify gun IDs after every USB replug"],
    source_ids: ["SRC-GUN-004"],
  },
  {
    id: "TPL-GUN-0002", title: "MAME ctrlr XML — AimTrak mapping", purpose: "Controller-file mapping for AimTrak guns in MAME",
    platform: "MAME / AimTrak", confidence: "low", needs_validation: true,
    template: "<!-- VERIFY-FIRST: structure per docs, values vs AimTrak PDF -->\n<mameconfig version=\"10\">\n  <system name=\"{{SYSTEM}}\">\n    <input>\n      <port type=\"P1_LIGHTGUN_X\">\n        <newseq type=\"standard\">GUNCODE_1_XAXIS</newseq>\n      </port>\n    </input>\n  </system>\n</mameconfig>\n", placeholders: ["{{SYSTEM}}"],
    validation_rules: ["cross-check port names against installed MAME -listxml", "do not ship to users without PDF verification"],
    source_ids: ["SRC-GUN-002", "SRC-MAME-001"],
  },
  {
    id: "TPL-VPIN-0001", title: "DmdDevice.ini — single-output routing", purpose: "Route DMD to exactly one target (virtual / Pin2DMD / ZeDMD)",
    platform: "Windows / dmd-extensions", confidence: "high",
    template: "[global]\n; enable ONE output:\n[virtualdmd]\nenabled = {{VIRTUAL_ENABLED}}\n[pin2dmd]\nenabled = {{PIN2_ENABLED}}\n[zedmd]\nenabled = {{ZE_ENABLED}}\nport = {{ZE_PORT}}\n", placeholders: ["{{VIRTUAL_ENABLED}}", "{{PIN2_ENABLED}}", "{{ZE_ENABLED}}", "{{ZE_PORT}}"],
    validation_rules: ["exactly one enabled=true", "ZeDMD port must match Device Manager COM port"],
    source_ids: ["SRC-VP-004"],
  },
  {
    id: "TPL-VPIN-0002", title: "ScreenRes.txt — 3-screen cabinet", purpose: "Playfield / backglass / DMD rectangles for B2S",
    platform: "Windows / B2S", confidence: "low", needs_validation: true,
    template: "# VERIFY-FIRST: confirm field order vs B2S wiki on your build\n{{PF_X}} {{PF_Y}} {{PF_W}} {{PF_H}}\n{{BG_X}} {{BG_Y}} {{BG_W}} {{BG_H}}\n{{DMD_X}} {{DMD_Y}} {{DMD_W}} {{DMD_H}}\n", placeholders: ["{{PF_X}}", "{{PF_Y}}", "{{PF_W}}", "{{PF_H}}", "{{BG_X}}", "{{BG_Y}}", "{{BG_W}}", "{{BG_H}}", "{{DMD_X}}", "{{DMD_Y}}", "{{DMD_W}}", "{{DMD_H}}"],
    validation_rules: ["rectangles must match Windows display topology exactly", "re-verify after any GPU driver update"],
    source_ids: ["SRC-VP-003"],
  },
  {
    id: "TPL-SCR-0001", title: "ScreenScraper v2 — quota-safe request", purpose: "Authenticated metadata request with quota awareness",
    platform: "any HTTP client", confidence: "high",
    template: "GET https://www.screenscraper.fr/api2/jeuInfos.php\n  ?devid={{DEVID}}&devpassword={{DEVPASS}}\n  &ssid={{SSID}}&sspassword={{SSPASS}}\n  &systemeid={{SYSTEM_ID}}&romnom={{ROM_BASENAME}}.zip\n# 1) call ssuserInfos.php FIRST, read quota\n# 2) cache response by (systemeid, rom sha1)\n# 3) back off on 429 / quota errors\n", placeholders: ["{{DEVID}}", "{{DEVPASS}}", "{{SSID}}", "{{SSPASS}}", "{{SYSTEM_ID}}", "{{ROM_BASENAME}}"],
    validation_rules: ["never scrape without reading quota first", "free-apps-only license", "resolve system IDs via systemesListe.php"],
    source_ids: ["SRC-SCR-001"],
  },
  {
    id: "TPL-SCR-0002", title: "TheGamesDB — search + platforms cache", purpose: "Game search with runtime-cached reference tables",
    platform: "any HTTP client", confidence: "high",
    template: "GET https://api.thegamesdb.net/v1/Games/ByGameName\n  ?apikey={{APIKEY}}&name={{GAME}}\n# reference (cache 7d):\nGET https://api.thegamesdb.net/v1/Platforms?apikey={{APIKEY}}\nGET https://api.thegamesdb.net/v1/Genres?apikey={{APIKEY}}\n# spec: https://api.thegamesdb.net/spec.yaml\n", placeholders: ["{{APIKEY}}", "{{GAME}}"],
    validation_rules: ["cache Platforms/Genres, don't refetch per game", "delta-sync, never full re-dump"],
    source_ids: ["SRC-SCR-002"],
  },
];

export const PLAYBOOKS: KBPlaybook[] = [
  {
    id: "PB-MAME-0001", title: "MAME major-version upgrade without tears", goal: "Move emulator + set from 0.2xx to 0.28x with a verified audit trail",
    confidence: "high", source_ids: ["SRC-MAME-001", "SRC-MAME-002", "SRC-ROM-004"],
    steps: [
      { action: "Backup: mame.ini, cfg/, nvram/, hi/ and the full roms/ listing (dir listing + -verifyroms log).", check: "Backup folder restorable on a second machine.", rollback: "Restore backup folder." },
      { action: "Install the new MAME build side-by-side (new folder, never overwrite).", check: "New mame.exe -version prints expected build." },
      { action: "Point the new build at a COPY of the set; run -verifyroms and save the log.", check: "Missing/renamed list captured, not eyeballed." },
      { action: "Rebuild the copy with RomVault + matching-version DAT until audit is clean.", check: "-verifyroms clean on the rebuilt copy." },
      { action: "Regenerate mame.ini via -createconfig, then re-apply your recorded diffs.", check: "Diff of old vs new ini reviewed line by line." },
      { action: "Smoke-test 5 known-good games incl. one CHD title and one gun title.", check: "All 5 boot to attract mode with sound + input." },
    ],
    safety_checks: ["Never upgrade in place on the only copy of a set.", "CHDs are version-tied — verify, don't assume."],
    error_signs: ["'missing ROM' floods on previously working games", "CHD 'required files missing'", "controls dead (cfg schema changed)"],
    known_issues: ["Forum advice from the old version no longer applies — check dates.", "Frontend core path may still point at the old exe."],
  },
  {
    id: "PB-GUN-0001", title: "Sinden twin-gun setup that survives reboots", goal: "Two stable Sinden guns with per-game profiles and no recalibration loop",
    confidence: "high", source_ids: ["SRC-GUN-001", "SRC-GUN-004"],
    steps: [
      { action: "Label USB ports physically; plug each gun into its pinned port via powered hub.", check: "Device Manager shows both cameras with stable instance paths." },
      { action: "Enable the Sinden border full-screen; disable HDR and windowed-mode cropping.", check: "Border visible edge-to-edge in the Sinden camera preview." },
      { action: "Assign P1/P2 in Sinden software, then verify in DemulShooter gun order.", check: "Trigger test: P1 moves P1 cursor only." },
      { action: "Create per-game DemulShooter profiles with offsets; leave global calibration alone.", check: "One known-good game on target before touching the next." },
    ],
    safety_checks: ["Backup Sinden profiles + DemulShooter configs before any update."],
    error_signs: ["Guns swapped after reboot", "drift only in one game", "tracking lost in bright scenes"],
    known_issues: ["Global recalibration after a USB swap corrupts working profiles.", "Windows Game Controllers order ≠ DemulShooter order."],
  },
  {
    id: "PB-VPIN-0001", title: "'Backglass stays black' triage", goal: "Isolate display-topology vs B2S-config vs standby-phantom faults",
    confidence: "high", source_ids: ["SRC-VP-001", "SRC-VP-003", "SRC-VP-004"],
    steps: [
      { action: "Read first: Windows display topology (which screen is which, scaling %, orientation).", check: "Screenshot of display settings saved." },
      { action: "Verify ScreenRes.txt rectangles against that topology (verify-first template).", check: "Rectangles match pixel-exact, no overlaps." },
      { action: "Launch one known-good table; check B2S log + DMD output routing (DmdDevice.ini single output).", check: "Exactly one DMD output enabled." },
      { action: "If TV wakes from standby black: force CEC/handshake re-sync on wake; test cold boot vs wake.", check: "Cold boot works AND wake works — both, not one." },
    ],
    safety_checks: ["Change one layer at a time (topology → B2S → DMD → power)."],
    error_signs: ["Backglass on wrong monitor", "DMD duplicated/mirrored", "works cold, fails on wake"],
    known_issues: ["Swapping HDMI cables rarely fixes topology faults.", "Standby TVs lie about being connected."],
  },
  {
    id: "PB-SCR-0001", title: "Quota-safe ScreenScraper run", goal: "Full-library scrape without bans, with resume capability",
    confidence: "high", source_ids: ["SRC-SCR-001"],
    steps: [
      { action: "Read ssuserInfos.php; record threads/quota before starting.", check: "Quota numbers logged with timestamp." },
      { action: "Resolve system IDs via systemesListe.php at runtime.", check: "No hardcoded system mapping in the job." },
      { action: "Scrape in small batches with cache-by-(system,sha1); pause on 429.", check: "Resume file written per batch." },
      { action: "Re-check quota mid-run; stop cleanly before exhaustion.", check: "Final quota logged; no error storms." },
    ],
    safety_checks: ["Free-apps-only license — verify your use qualifies.", "One job at a time per account."],
    error_signs: ["429 bursts", "wrong-system matches", "quota drained in minutes"],
    known_issues: ["A 29h scan over 100Mbit + quota throttle can be healthy — check throughput before panicking.", "Firmware '0 files' is a path/DAT issue, not a scraper issue."],
  },
  {
    id: "PB-CRT-0001", title: "CRT Emudriver first install (safe order)", goal: "15 kHz output without endangering the chassis or the weekend",
    confidence: "high", source_ids: ["SRC-CRT-001", "SRC-CRT-002"],
    steps: [
      { action: "Verify GPU against the Emudriver compatibility list (no RDNA/newer).", check: "Card model confirmed compatible in writing." },
      { action: "Plan the boot chain: how to keep 31kHz+ signals away from the 15kHz monitor during BIOS/boot.", check: "Boot display strategy documented (second LCD / delayed switch).", rollback: "Keep a known-good LCD attached until 15kHz is proven." },
      { action: "DDU-clean old drivers → install Emudriver → VMMaker modelines → test on safe display.", check: "15kHz modes listed; test pattern stable." },
      { action: "Enable GroovyMAME Switchres with the matching monitor preset; smoke-test 3 resolutions.", check: "No out-of-range events; geometry sane." },
    ],
    safety_checks: ["SAFETY: never hot-plug signal guesses into a 15kHz chassis.", "Super resolutions (2560) reduce modeline risk."],
    error_signs: ["rolling/folded image", "chassis clicking", "no sync on specific resolutions"],
    known_issues: ["Driver updates can silently drop custom modelines — re-verify after each update.", "Windows Update loves replacing Emudriver. Pin it."],
  },
  {
    id: "PB-ROM-0001", title: "RomM 'slow scan / 0 files' triage", goal: "Distinguish healthy-slow from broken before touching anything",
    confidence: "medium", source_ids: ["SRC-ROM-001", "SRC-SCR-001", "SRC-SCR-002"],
    steps: [
      { action: "Measure: scan throughput (files/min), network link speed, disk IO wait.", check: "Numbers captured: is it CPU, network, or quota bound?" },
      { action: "For '0 files' firmware: compare expected path vs actual path vs DAT profile name.", check: "All three agree (watch case sensitivity on shares)." },
      { action: "Check scraper quota + per-item latency separately from filesystem scan.", check: "Filesystem scan and metadata scrape measured independently." },
      { action: "Fix the bottleneck layer only (link speed / quota pacing / path mapping).", check: "One variable changed; re-measure before the next." },
    ],
    safety_checks: ["Read-only inspection first; no mass renames during triage."],
    error_signs: ["100Mbit link on gigabit hardware", "quota 429s mixed into scan logs", "case-mismatch paths on SMB/NFS"],
    known_issues: ["Deleting + rescanning to 'fix' slowness just restarts the 29 hours.", "Firmware '0 files' with populated folder = mapping issue, always."],
  },
];

export const GAPS: KBGaps[] = [
  { id: "QA-0011", severity: "warning", issue: "Batocera / Recalbox / Pegasus / Attract-Mode: index only, no verified artifacts", affected: "frontend/*", action: "Next wave: facts + folder-structure templates + setup playbooks per frontend." },
  { id: "QA-0012", severity: "warning", issue: "Device Knowledge Set missing: encoder/spinner/trackball VID/PID database", affected: "hardware/*", action: "Extra phase: VID/PID only from verified vendor/community sources." },
  { id: "QA-0007", severity: "warning", issue: "AimTrak ctrlr XML detail values unverified (TPL-GUN-0002)", affected: "TPL-GUN-0002", action: "Verify against AimTrak PDF, then lift needs_validation." },
  { id: "QA-0008", severity: "warning", issue: "B2S ScreenRes exact field order unverified (TPL-VPIN-0002)", affected: "TPL-VPIN-0002", action: "Verify against B2S wiki on a pinned build." },
  { id: "QA-0014", severity: "info", issue: "VPIN deep dive pending: PinballX-XML, Pinscape calibration, DOF toy events", affected: "vpin/*", action: "Extra phase after core VPIN set is battle-tested." },
  { id: "QA-0018", severity: "warning", issue: "Redump availability watch after June-2026 disruption", affected: "SRC-ROM-002", action: "Check status before each Redump-dependent recommendation." },
  { id: "QA-0020", severity: "info", issue: "Quarterly source re-check cycle", affected: "all sources", action: "Refresh last_checked / source_last_updated; flag drift." },
];

export const KB_META = {
  consolidated: "2026-08-06",
  full_records: 199,
  demo_sources: SOURCES.length,
  demo_facts: FACTS.length,
  demo_templates: TEMPLATES.length,
  demo_playbooks: PLAYBOOKS.length,
  demo_gaps: GAPS.length,
  legal_ok: "68/70 full-pack sources legal:ok, 2 review (documented)",
};
