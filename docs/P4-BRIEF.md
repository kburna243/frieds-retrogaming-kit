# P4 brief — documentation, i18n, credits, depersonalization

This file is the task description for phase P4. It replaces the private project plan for anyone working on
the documentation (it contains no personal data on purpose).

## Project in one paragraph

**Fried's Retrogaming Kit** (repo `kburna243/frieds-retrogaming-kit`, license MIT) is a set of guided Windows
installers built on a shared PowerShell 5.1 core (`core\`):

- **Pinball** (`pinball\`, `Start-Pinball.cmd`): sets up a *user-supplied* PinUP Popper build (Baller installer
  layout). Two modes: *move on this PC* and *rebuild on a fresh Windows*. Steps 1–9: detect build · choose target ·
  prerequisites (VC++/.NET/DirectX, installers only as verified copies) · copy (robocopy, resumable) · rewrite
  absolute paths (database, text files, registry, shortcuts — idempotent) · register COM components · Future
  Pinball/BAM first-time setup · screens (monitor roles, test windows, diff preview, "keep valid values" default,
  undo) · finish (backup, optional Popper autostart).
- **Lightgun / RetroBat** (`lightgun\`, `Start-Lightgun.cmd`): a "Wiimote-ready RetroBat": DolphinBar (mode 4),
  ViGEmBus, Gunmote (guided download from gunmotelabs), interference fixes (Steam, VMultiGuard), Gunmote layouts,
  RetroBat settings (`use_guns=0` per system etc.), profile automation (scheduled tasks + RetroBat hooks),
  measured verification (XInput test). Emulator setups (TeknoParrot, Demul + DemulShooter, Model 2/3, guided
  DuckStation/PCSX2, rumble) are being added in phase P3b in parallel.
- Every step is *Test → Invoke (dry-run capable) → Verify*; a step only turns green after Verify.
- The user brings everything copyright-relevant (ROMs, BIOS, purchased builds, PinUP Popper, tools without a
  redistribution license). The kit only downloads freely licensed tools from official sources and never re-hosts.
- Website: `site\` (Vite/React, hash routing, de/en, GitHub Pages ready, self-hosted fonts, no trackers).

## Constraints

- **Do not change PowerShell logic** in `core\`, `pinball\`, `lightgun\` or tests — they are tested on Windows
  (Pester 3.4) and cannot be tested in a Linux cloud environment. Text/documentation only.
- **Do not edit `i18n\*.psd1`** in this phase (phase P3b adds keys in parallel → merge conflicts). Report text
  problems you find there in the PR description instead.
- `lightgun\` is under active development (P3b); describe features only as far as the code on `main` shows them,
  mark emulator setups as "in progress".
- No personal data: no host names, IPs, local drive paths of a specific machine, e-mail addresses, real names
  except the brand "Fried's" and the author line in `LICENSE`.
- Every factual claim about a third-party tool (license, source URL, behavior) must be verified from the official
  source and linked; if unverifiable, say so.
- Keep German and English equivalent. German with correct umlauts (ä, ö, ü, ß).
- Work on branch `p4-docs`, open a pull request to `main`. Do not push to `main`, do not make the repo public.

## Deliverables

1. `README.md` (English) + `README.de.md` (German): what it is, who it is for, requirements, quick start for both
   installers, safety model (dry run default, confirmations, verified installers, backups, never deletes),
   what the user must bring, legal notice, links to guides, credits, license.
2. Guides in `docs\` (en + de each): `pinball-guide`, `lightgun-guide`, `troubleshooting`, `faq`. Derive steps from
   the code (`pinball\steps\*.ps1`, `lightgun\steps\*.ps1`, wizard pages) — no invented commands or versions.
3. `CREDITS.md`: complete in English and German (two sections or two files), every entry with verified official
   link and license where known: communities **Lightgun Lunatics** and **Pinball Lunatics**; **Lichtknarre**,
   **Touchmote**, **Gunmote (gunmotelabs)**, **DemulShooter (argonlefou)**, **RetroBat team**, **ViGEmBus (Nefarius)**,
   **TeknoParrot (Teknogods)**, MAMEHooker and its open successors, emulator authors/maintainers (MAME, Demul,
   Model 2 Emulator, Supermodel, DuckStation, PCSX2, RetroArch/libretro), **PinUP Popper/Player (nailbuster)**,
   Baller installer, Visual Pinball X, VPinMAME/PinMAME, B2S Backglass Server, DMD Extensions (freezy), FlexDMD,
   Future Pinball (BSP Software) + BAM (Ravarcade), DOFLinx, and the German community handbook
   "Projekt Virtual Pinball" by **Moster** (flippermarkt.de), published on vpinball.de, as inspiration.
   Missing someone is worse than a long list.
4. `LICENSE` (MIT, copyright holder "Friedrich Börner"), `SECURITY.md` (how to report issues; honest description of
   the security model incl. that the optional lightgun profile automation installs *highest-privilege scheduled
   tasks that any process of that user can start* — hardening is being finished before release; how to disable it),
   `CONTRIBUTING.md` (short).
5. `tools\Test-Depersonalized.ps1` (PowerShell 7 compatible, runs on Linux too) + allowlist file: scans the repo
   for host names, private/CGNAT IPs, drive-letter paths outside examples, e-mail addresses, typical secret
   patterns; exits non-zero on findings. Run it in CI: `.github\workflows\checks.yml` (depersonalization scan +
   site build `npm ci && npm run build` in `site\`). Optional second workflow `pages.yml` that deploys `site\dist`
   to GitHub Pages with `SITE_BASE=/frieds-retrogaming-kit/` — **disabled/manual trigger only** until release.
6. Website texts (`site\src\i18n\de.ts`, `en.ts`, guide pages): rename the product consistently to
   **"Fried's Retrogaming Kit"**, link the guides/README, keep the "work in progress" banner, do not add features.
7. PR description: summary, list of files, open questions, any text problems found in `i18n\*.psd1`.
