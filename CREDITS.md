# Credits / Danksagung

English first, deutsche Fassung weiter unten.

## English

Fried's Retrogaming Kit only glues together the work of many people. It never redistributes their software:
free tools are downloaded from their official sources, everything else you bring yourself. **Thank you!**

Links and licenses were checked against the official sources in September 2026. "Not stated" means the
official source names no license; the project's own terms apply. If something here is wrong or someone is
missing, please open an issue: credits are never left out on purpose.

### Communities

| Community | Why it is here | Official page |
|---|---|---|
| **Light Gun Lunatics** | Light gun community (games database, emulator guides, Discord); a lot of the lightgun know-how behind this kit comes from there | <https://lightgun.retrolunatics.com/> |
| **Pinball Lunatics** | Sister community for real and virtual pinball (guides, cabinet building) | <https://pinball.retrolunatics.com/> |

### Lightgun / RetroBat

| Project | Role in the kit | Official source | License |
|---|---|---|---|
| **Gunmote** (gunmotelabs) | Turns Wiimotes into light guns / virtual Xbox pads; the kit finds it, starts it and writes its layouts. You install it yourself. | <https://github.com/gunmotelabs/Gunmote> | GPL-3.0 |
| **Touchmote** (simphax and contributors) | Predecessor of Gunmote, named in Gunmote's README together with WiiTUIO | <https://github.com/simphax/Touchmote> | GPL-3.0 |
| **Lichtknarre** (Geekonarium) | Wiimote light gun tool; knowledge and inspiration for Wiimote light gun setups | <https://geekonarium.de/en/lichtknarre-lightgun/> | Free download (beta), terms on the author's site |
| **DemulShooter** (argonlefou) | Light gun input for Demul and other emulators; used by the emulator setups that are in progress | <https://github.com/argonlefou/DemulShooter> | Not stated |
| **RetroBat** (RetroBat Team) | The frontend the lightgun wizard configures. The kit does not install it. | <https://www.retrobat.org/> and <https://github.com/RetroBat-Official/retrobat> | RetroBat Team code LGPL-3.0, not for commercial use (see its license.txt) |
| **ViGEmBus** (Nefarius, Benjamin Höglinger-Stelzer) | Virtual Xbox 360 pads for Gunmote; the kit installs the official signed release after your confirmation. The project is retired and its repository archived (2023). | <https://github.com/nefarius/ViGEmBus> | BSD-3-Clause |
| **TeknoParrot** (Teknogods) | Modern arcade games; emulator setup in progress | <https://teknoparrot.com/> (UI source: <https://github.com/teknogods/TeknoParrotUI>) | Free download; the UI (TeknoParrotUI) is GPL-3.0, no license stated for the rest |
| **MAMEHooker** (Howard Casto) | The original output/force-feedback tool for MAME and light guns | <https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker> | "Open-source for personal use" (author's page) |
| **OutputHooker** (PolybiusExtreme) | Open successor of MAMEHooker for current Windows; rumble support is in progress, the choice of tool is still open | <https://github.com/PolybiusExtreme/OutputHooker> | GPL-3.0 |
| **QMamehook** (SeongGino) | Cross-platform, MAMEHooker-compatible output client | <https://github.com/SeongGino/QMamehook> | LGPL-2.1 |

### Emulators and their maintainers

| Emulator | Official source | License |
|---|---|---|
| **MAME** (MAMEdev team) | <https://www.mamedev.org/> | GPL-2.0 as a whole, most files BSD-3-Clause |
| **Demul** (Demul Team) | <http://demul.emulation64.com/> | Closed source, free |
| **Model 2 Emulator** (ElSemi) | No verified official download: the former Nebula site no longer serves the emulator | Closed source, free |
| **Supermodel** (Bart Trzynadlowski, Nik Henson and the Supermodel Team) | <https://github.com/trzy/Supermodel> (site: <https://www.supermodel3.com/>) | GPL-3.0 |
| **DuckStation** (Stenzek) | <https://github.com/stenzek/duckstation> | CC BY-NC-ND 4.0 |
| **PCSX2** (PCSX2 team) | <https://pcsx2.net/> | GPL-3.0 |
| **Flycast** (flyinghead) | <https://github.com/flyinghead/flycast> | GPL-2.0 |
| **RetroArch / libretro** (libretro team and all core authors) | <https://www.libretro.com/> and <https://github.com/libretro/RetroArch> | GPL-3.0 (RetroArch); cores have their own licenses |

### Virtual pinball

| Project | Role in the kit | Official source | License |
|---|---|---|---|
| **PinUP Popper / PinUP Player** (NailBuster Software) | Frontend and PuP packs of the build you bring. Never downloaded or redistributed by the kit. | <https://www.nailbuster.com/wikipinup/> | Free for non-commercial use |
| **Baller Installer** (PinUP / NailBuster) | The folder layout the pinball wizard expects | <https://www.nailbuster.com/wikipinup/doku.php?id=baller_installer> | Components keep their own licenses |
| **Visual Pinball X** (Visual Pinball team) | Pinball engine; the kit rewrites paths and screen values | <https://github.com/vpinball/vpinball> | Moving from the old MAME-like license to GPL-3.0-or-later (see its LICENSE) |
| **VPinMAME / PinMAME** (PinMAME team) | ROM emulation; the kit registers it | <https://github.com/vpinball/pinmame> | Moving from the old MAME license to BSD-3-Clause (see its LICENSE) |
| **B2S Backglass Server** (Herweh and the B2S team) | Backglass; the kit registers it | <https://github.com/vpinball/b2s-backglass> | Own MAME-derived license, no commercial use |
| **DMD Extensions** (freezy) | Virtual DMD; the kit sets its positions | <https://github.com/freezy/dmd-extensions> | GPL-2.0 |
| **FlexDMD** (vbousquet) | DMD renderer; the kit registers it | <https://github.com/vbousquet/flexdmd> | Apache-2.0 |
| **Future Pinball** (Christopher Leathley, BSP Software Design Solutions) | Second pinball engine; the kit sets its first-run options | <https://futurepinball.com/> | Freeware |
| **BAM - Better Arcade Mode** (Ravarcade) | Future Pinball mod; the kit runs the build's BAM cabinet batch file after your confirmation | <https://www.ravarcade.pl/> | Freeware |
| **DOFLinx** | Feedback and lighting for Pinball FX and Future Pinball; its folder is moved with the build | <https://doflinx.github.io/docs/> (releases: <https://github.com/DOFLinx/DOFLinx/releases>) | Not stated |
| **DirectOutput Framework** (mjrgh and contributors) | Cabinet feedback toys; its folder is moved with the build | <https://github.com/mjrgh/DirectOutput> | MIT |
| **Moster** (flippermarkt.de) | German community handbook "Projekt Virtual Pinball", published on vpinball.de with permission; inspiration for the checks in the pinball wizard | <https://www.vpinball.de/index.php/software/projekt-virtual-pinball/projekt-virtual-pinball> | Author's rights |

### Microsoft components

Visual C++ Redistributables, .NET Framework and the DirectX End-User Runtime are taken from your build or,
only if you allow it, downloaded from Microsoft addresses. Every file must carry a valid Microsoft signature.

---

## Deutsch

Fried's Retrogaming Kit verbindet nur die Arbeit vieler Menschen. Es verteilt deren Software nie weiter:
freie Werkzeuge werden von ihren offiziellen Quellen geladen, alles andere bringst du selbst mit. **Danke!**

Links und Lizenzen wurden im September 2026 an den offiziellen Quellen geprüft. „Nicht angegeben“ heißt: Die
offizielle Quelle nennt keine Lizenz, es gelten die Bedingungen des Projekts. Stimmt etwas nicht oder fehlt
jemand, bitte ein Issue aufmachen: Danksagungen werden nie absichtlich weggelassen.

### Communitys

| Community | Warum sie hier steht | Offizielle Seite |
|---|---|---|
| **Light Gun Lunatics** | Lightgun-Community (Spieledatenbank, Emulator-Anleitungen, Discord); viel Lightgun-Wissen hinter diesem Kit stammt von dort | <https://lightgun.retrolunatics.com/> |
| **Pinball Lunatics** | Schwester-Community für echte und virtuelle Flipper (Anleitungen, Cabinet-Bau) | <https://pinball.retrolunatics.com/> |

### Lightgun / RetroBat

| Projekt | Rolle im Kit | Offizielle Quelle | Lizenz |
|---|---|---|---|
| **Gunmote** (gunmotelabs) | Macht Wiimotes zu Lightguns bzw. virtuellen Xbox-Pads; das Kit findet es, startet es und schreibt seine Layouts. Installieren musst du es selbst. | <https://github.com/gunmotelabs/Gunmote> | GPL-3.0 |
| **Touchmote** (simphax und Mitwirkende) | Vorgänger von Gunmote, in Gunmotes README zusammen mit WiiTUIO genannt | <https://github.com/simphax/Touchmote> | GPL-3.0 |
| **Lichtknarre** (Geekonarium) | Wiimote-Lightgun-Werkzeug; Wissen und Anregung für Wiimote-Lightgun-Setups | <https://geekonarium.de/en/lichtknarre-lightgun/> | Kostenloser Download (Beta), Bedingungen auf der Seite des Autors |
| **DemulShooter** (argonlefou) | Lightgun-Eingaben für Demul und weitere Emulatoren; genutzt von den Emulator-Einrichtungen, die in Arbeit sind | <https://github.com/argonlefou/DemulShooter> | Nicht angegeben |
| **RetroBat** (RetroBat-Team) | Das Frontend, das der Lightgun-Assistent einrichtet. Das Kit installiert es nicht. | <https://www.retrobat.org/> und <https://github.com/RetroBat-Official/retrobat> | Code des RetroBat-Teams LGPL-3.0, nicht für kommerzielle Nutzung (siehe dessen license.txt) |
| **ViGEmBus** (Nefarius, Benjamin Höglinger-Stelzer) | Virtuelle Xbox-360-Pads für Gunmote; das Kit installiert nach deiner Bestätigung das offizielle signierte Release. Das Projekt ist eingestellt, sein Repository archiviert (2023). | <https://github.com/nefarius/ViGEmBus> | BSD-3-Clause |
| **TeknoParrot** (Teknogods) | Moderne Arcade-Spiele; Emulator-Einrichtung in Arbeit | <https://teknoparrot.com/> (Quellcode der Oberfläche: <https://github.com/teknogods/TeknoParrotUI>) | Kostenloser Download; die Oberfläche (TeknoParrotUI) ist GPL-3.0, für den Rest ist keine Lizenz angegeben |
| **MAMEHooker** (Howard Casto) | Das ursprüngliche Ausgabe-/Force-Feedback-Werkzeug für MAME und Lightguns | <https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker> | „Open-source for personal use“ (Seite des Autors) |
| **OutputHooker** (PolybiusExtreme) | Offener Nachfolger von MAMEHooker für aktuelles Windows; Rumble ist in Arbeit, die Werkzeugwahl ist noch offen | <https://github.com/PolybiusExtreme/OutputHooker> | GPL-3.0 |
| **QMamehook** (SeongGino) | Plattformübergreifender, MAMEHooker-kompatibler Ausgabe-Client | <https://github.com/SeongGino/QMamehook> | LGPL-2.1 |

### Emulatoren und ihre Maintainer

| Emulator | Offizielle Quelle | Lizenz |
|---|---|---|
| **MAME** (MAMEdev-Team) | <https://www.mamedev.org/> | Als Ganzes GPL-2.0, die meisten Dateien BSD-3-Clause |
| **Demul** (Demul Team) | <http://demul.emulation64.com/> | Nicht quelloffen, kostenlos |
| **Model 2 Emulator** (ElSemi) | Kein geprüfter offizieller Download: Die frühere Nebula-Seite bietet den Emulator nicht mehr an | Nicht quelloffen, kostenlos |
| **Supermodel** (Bart Trzynadlowski, Nik Henson und das Supermodel-Team) | <https://github.com/trzy/Supermodel> (Seite: <https://www.supermodel3.com/>) | GPL-3.0 |
| **DuckStation** (Stenzek) | <https://github.com/stenzek/duckstation> | CC BY-NC-ND 4.0 |
| **PCSX2** (PCSX2-Team) | <https://pcsx2.net/> | GPL-3.0 |
| **Flycast** (flyinghead) | <https://github.com/flyinghead/flycast> | GPL-2.0 |
| **RetroArch / libretro** (libretro-Team und alle Core-Autoren) | <https://www.libretro.com/> und <https://github.com/libretro/RetroArch> | GPL-3.0 (RetroArch); Cores haben eigene Lizenzen |

### Virtual Pinball

| Projekt | Rolle im Kit | Offizielle Quelle | Lizenz |
|---|---|---|---|
| **PinUP Popper / PinUP Player** (NailBuster Software) | Frontend und PuP-Packs des Builds, den du mitbringst. Das Kit lädt oder verteilt es nie. | <https://www.nailbuster.com/wikipinup/> | Kostenlos für nicht-kommerzielle Nutzung |
| **Baller-Installer** (PinUP / NailBuster) | Die Ordnerstruktur, die der Pinball-Assistent erwartet | <https://www.nailbuster.com/wikipinup/doku.php?id=baller_installer> | Komponenten behalten ihre eigenen Lizenzen |
| **Visual Pinball X** (Visual-Pinball-Team) | Flipper-Engine; das Kit schreibt Pfade und Bildschirmwerte um | <https://github.com/vpinball/vpinball> | Wechselt von der alten MAME-ähnlichen Lizenz zu GPL-3.0-or-later (siehe dessen LICENSE) |
| **VPinMAME / PinMAME** (PinMAME-Team) | ROM-Emulation; das Kit registriert es | <https://github.com/vpinball/pinmame> | Wechselt von der alten MAME-Lizenz zu BSD-3-Clause (siehe dessen LICENSE) |
| **B2S Backglass Server** (Herweh und das B2S-Team) | Backglass; das Kit registriert ihn | <https://github.com/vpinball/b2s-backglass> | Eigene, von MAME abgeleitete Lizenz, keine kommerzielle Nutzung |
| **DMD Extensions** (freezy) | Virtuelles DMD; das Kit setzt seine Positionen | <https://github.com/freezy/dmd-extensions> | GPL-2.0 |
| **FlexDMD** (vbousquet) | DMD-Renderer; das Kit registriert ihn | <https://github.com/vbousquet/flexdmd> | Apache-2.0 |
| **Future Pinball** (Christopher Leathley, BSP Software Design Solutions) | Zweite Flipper-Engine; das Kit setzt die Einstellungen für den ersten Start | <https://futurepinball.com/> | Freeware |
| **BAM – Better Arcade Mode** (Ravarcade) | Mod für Future Pinball; das Kit führt nach deiner Bestätigung die BAM-Cabinet-Batchdatei des Builds aus | <https://www.ravarcade.pl/> | Freeware |
| **DOFLinx** | Feedback und Beleuchtung für Pinball FX und Future Pinball; sein Ordner zieht mit dem Build um | <https://doflinx.github.io/docs/> (Releases: <https://github.com/DOFLinx/DOFLinx/releases>) | Nicht angegeben |
| **DirectOutput Framework** (mjrgh und Mitwirkende) | Feedback-Geräte im Cabinet; sein Ordner zieht mit dem Build um | <https://github.com/mjrgh/DirectOutput> | MIT |
| **Moster** (flippermarkt.de) | Deutsches Community-Handbuch „Projekt Virtual Pinball“, mit Erlaubnis auf vpinball.de veröffentlicht; Anregung für die Prüfungen im Pinball-Assistenten | <https://www.vpinball.de/index.php/software/projekt-virtual-pinball/projekt-virtual-pinball> | Rechte beim Autor |

### Microsoft-Komponenten

Visual C++ Redistributables, .NET Framework und die DirectX-Endbenutzer-Runtime kommen aus deinem Build oder,
nur wenn du es erlaubst, von Microsoft-Adressen. Jede Datei muss eine gültige Microsoft-Signatur tragen.
