# **Wissensbasis zur Implementierung von Emulations-Enhancements: Technische Architektur, Optimierungspfade und Fehlervermeidung von MAME bis Nintendo Switch**

Die zeitgemäße Emulation historischer und moderner Videospielplattformen beschränkt sich in anspruchsvollen Arcade- und Cabinet-Setups nicht mehr auf die bloße Replikation nativer Hardwaregrenzen. Das übergeordnete Ziel moderner Backend-Architekturen liegt in der kontrollierten Bildsynthese, visuellen Rekonstruktion und drastischen Latenzminimierung auf moderner Display- und Rechenhardware. Im Kontext des Projekts *Fried's Retrogaming Kit* und dessen Enhancement-Spezifikation (v.07 innerhalb des Konzepts 0.5) bedarf die automatisierte Verwaltung dieser Erweiterungen einer formalisierten, fehlertoleranten Systematik1. Modifikationen an Render-Pipelines, Shader-Kompilierungsschleifen und Eingabetreibern greifen tief in das Betriebssystem und die Ausführungslogik der Emulatoren ein1. Ein inkonsistenter Konfigurationszustand führt unweigerlich zu Bildfehlern, Speicherzugriffsverletzungen oder Eingabeabbrüchen3. Die folgende Abhandlung liefert eine tiefgehende Wissensbasis über die technischen Mechanismen, systemspezifischen Fehlerquellen und deterministischen Implementierungsmuster quer über alle Konsolengenerationen hinweg.

## **Systemarchitektur und Konfigurations-Governance im Frontend-/Backend-Ökosystem**

### **Richtlinienbasierte Konfigurationskontrolle und transaktionale Sicherheit**

In komplexen Cabinet-Installationen, die Frontends wie PinUP Popper, RetroBat oder LaunchBox mit heterogenen Emulatoren verknüpfen, stellt die unkoordinierte Modifikation von Konfigurationsdateien die primäre Ursache für Systemausfälle dar1. Werden interne Auflösungsmultiplikatoren, Widescreen-Patches oder Treiber-Hooks simultan oder mit fehlerhafter Syntax injiziert, resultiert dies häufig in stillen Fehlern oder Programmabstürzen. Das Architekturmodell von Fried's Retrogaming Kit adressiert diese Problematik durch eine strikt entkoppelte Richtlinienarchitektur1:  
Alle modifizierenden Operationen unterliegen einer *Gated Execution Policy*, bei der jede geplante Modifikation zunächst in einem Trockenlauf analysiert und validiert wird, bevor ein zustandsverändernder Aufruf mittels expliziter Genehmigungsparameter autorisiert wird1. Flankiert wird dieses Modell von atomaren Schnappschüssen, die vor jedem Schreibzugriff auf Konfigurationen oder Registrierungsschlüssel angelegt und über kryptografische Prüfsummen abgesichert werden1. Über eine hostlose JSON-RPC-Schnittstelle über Standard-Ein-/Ausgabe interagiert das System deterministisch mit externen Prozessüberwachern, wodurch Datei-Locks und Race-Conditions zwischen Backend-Skripten und nativen Emulator-Instanzen ausgeschlossen werden1.

### **Abstraktionsebenen: Libretro-Ökosystem versus Standalone-Architektur**

Die technische Umsetzung von Enhancements spaltet sich grundlegend zwischen dem einheitlichen Libretro-Framework (RetroArch) und spezialisierten Standalone-Emulatoren auf. Während Libretro eine harmonisierte Treiberschicht für Video, Audio und Eingabe über virtuelle Kerne bereitstellt, operieren Standalone-Emulatoren autark mit direktem Hardwarezugriff7. Die Wahl der Zielplattform bestimmt maßgeblich, welche Enhancement-Pipelines realisierbar sind.

| Systemkriterium | Libretro / RetroArch Cores | Standalone-Emulatoren (PCSX2, Dolphin, DuckStation, Ryujinx) |
| :---- | :---- | :---- |
| **Konfigurationshierarchie** | Zentralisiert via retroarch.cfg, Core-Overrides und Game-Remaps8. | Dezentralisiert; proprietaere INI-, XML- oder JSON-Formate je Emulator10. |
| **Shader-Pipeline** | Vereinheitlichtes Slang/GLSL-Multipass-Framework (z. B. HSM Mega Bezel)5. | Individuelle Post-Processing-Engines; erfordert für komplexe Effekte externe ReShade-Hooks2. |
| **Latenzkompensation** | Nativer Support für speicherbasierte Run-Ahead- und Preemptive-Frame-Zyklen8. | Stark fragmentiert; meist auf V-Sync-Deaktivierung und variable Bildwiederholraten (VRR) beschränkt. |
| **Geometrie- und Grafik-Hacks** | Oft veraltet oder unvollständig portiert (z. B. instabiler PCSX2-Core). | Hochgradig optimierte, hardwarespezifische Render-Hacks und modernste Kompatibilitätspatches3. |
| **Fenster- und Gerätekontrolle** | Gekapselt; Fensterskalierung und Border-Overlays global standardisiert5. | Direkte Kontrolle über OS-Fenster-Handles, RawInput-Devices und prozessnahe Injektionen13. |

Die architektonische Konsequenz für die Backend-Steuerung besteht darin, dass frühe Konsolen- und Arcade-Systeme bis einschließlich der vierten Generation (16-Bit) optimal im homogenen Libretro-Framework skalieren15. Ab der fünften Konsolengeneration (PlayStation, Nintendo 64\) und insbesondere ab 128-Bit-Architekturen verlagert sich die Implementierung zwingend auf Standalone-Binaries, da nur dort die notwendigen Render-Target-Korrekturen und Hardware-Register exakt abgefangen werden können3.

## **Visuelle Bildsynthese und Rendering-Pipelines**

### **Shader-Pipelines und physikalische CRT-Rekonstruktion**

Die visuelle Ästhetik klassischer Raster- und Vektorgrafiken bis zur Jahrtausendwende war untrennbar mit den physikalischen Eigenschaften von Kathodenstrahlröhren (CRT) verbunden. Grafiker nutzten die feinen Unschärfen des Elektronenstrahls, Phosphormasken und Zeilenzwischenräume gezielt als primitives Antialiasing und zur optischen Farbmischung durch Dithering2. Auf hochauflösenden Flachbildschirmen mit quadratischen Pixeln wirken native Rohsignale steril, pixelig und fehlerhaft.  
Moderne Rekonstruktionspipelines nutzen Slang-Multipass-Shader unter Vulkan oder Direct3D 12\. Komplexe Shader wie *CRT-Royale* berechnen den physikalischen Strahlverlauf, Konvergenzfehler an den Röhrenrändern sowie die Lichtstreuung der Loch- oder Schlitzmaske auf Subpixelebene. Eine Weiterentwicklung stellt das *HSM Mega Bezel Reflection Framework* dar, welches nicht nur das Bild aufbereitet, sondern in Echtzeit Gehäusereflexionen auf simulierten virtuellen Acrylrahmen und Schrankblenden projiziert5. Da diese Berechnungen extrem bandbreitenintensiv sind, steigen die Hardwareanforderungen bei 4K-Ausgabe exponentiell an; Low-End-Grafikchips geraten hierbei schnell in thermische Drosselung oder Bildratenverluste.  
In Standalone-Umgebungen, die keine native Slang-Infrastruktur aufweisen, muss die Shader-Injektion über Hilfswerkzeuge wie ReShade realisiert werden. Hierbei wird der Treiberaufruf über modifizierte Laufzeitbibliotheken abgefangen. Im Rahmen von Cabinet-Setups führt dies zu schwerwiegenden Interaktionsproblemen, wenn externe Overlays (wie Lightgun-Kalibrierungsränder) versehentlich durch Post-Processing-Effekte wie Bloom oder Verzerrungen verfälscht werden, wodurch optische Sensoren die Displaygrenzen verlieren2.

### **Geometrie- und Texturskalierung**

Das Erhöhen des internen Render-Multiplikators (Internal Resolution Scale) von nativer Bildauflösung (beispielsweise 240p bei der PlayStation oder 480i bei der PlayStation 2\) auf moderne 1440p- oder 4K-Targets berechnet Polygone mit mathematischer Präzision neu11. Ergänzt wird dieses Verfahren durch anisotrope Filterung (AF), welche Texturen, die in flachen Winkeln in den virtuellen Raum fluchten, schärft, ohne spürbare GPU-Zyklen auf moderner Hardware zu beanspruchen.  
Antialiasing-Verfahren müssen jedoch differenziert bewertet werden. Klassisches Multisample-Antialiasing (MSAA) skaliert in emulierten Umgebungen schlecht, da viele Retro-Konsolen Bild- und Beleuchtungseffekte in eigenen Render-Passes über Framebuffer-Texturen berechneten. Post-Processing-Filter wie FXAA verwischen stattdessen zweidimensionale Menüelemente und Schriften. Bei nativer 4K-Renderung ist geometrisches Aliasing ohnehin minimiert, weshalb der Fokus primär auf der korrekten Behandlung von Temporal-Antialiasing (TAA) oder Subpixel-Filtern liegen muss.

### **Geometrie- und Rasterungsartefakte bei PS2-Architekturen**

Wird die interne Auflösung von Konsolen der sechsten Generation skaliert, brechen fundamentale Programmierannahmen klassischer Render-Engines zusammen. Entwickler der PlayStation 2 nutzten den internen Grafikprozessor (Graphics Synthesizer) für unkonventionelle Rendering-Tricks, die fest auf ganzzahlige Pixelgrenzen ausgelegt waren3.  
Ein weit verbreitetes Fehlerbild ist das sogenannte Ghosting oder Bloom-Misalignment, welches auftritt, wenn Vollbild-Unschärfe- oder Beleuchtungsfilter über die 3D-Geometrie gelegt werden17. Auf Originalhardware verschoben Entwickler Koordinaten oft um einen halben Pixel, um bilineare Glättungseffekte zu erzwingen. Bei einer Vervielfachung der Zielauflösung auf 4K führt diese Verschiebung dazu, dass der Blend-Effekt deutlich versetzt neben dem 3D-Modell gezeichnet wird3. Innerhalb von PCSX2 muss dieses Phänomen über manuelle Hardware-Hacks kompensiert werden:  
Die Option *Half-Pixel Offset* justiert die Berechnungsmatrix gezielt nach3. Während der Modus *Align to Native* universelle Geometriekanten glättet, erfordern Titel wie *Bully*, *Armored Core 3* oder Spiele der *Grand Theft Auto*\-Reihe zwingend die Einstellung *Special (Texture)*, um Tiefenschärfefehler und Halo-Artefakte vollständig zu tilgen3. Ein alternativer Modus namens *Normal (Vertex)* verschiebt stattdessen Vertex-Positionen, provoziert jedoch bei inkompatiblen Titeln horizontale Bildfehler und Abrisse an den Panelrändern3.  
Zusätzlich entstehen bei skalierten 2D-Elementen, wie Minimaps und Menüschriften, unschöne vertikale oder horizontale Haarlinien (Black Grid Lines)3. Ursache hierfür ist das unsaubere Mapping von Texturatlas-Koordinaten auf aufskalierte Polygone. Die Aktivierung von *Round Sprite* (auf Stufe *Half*) oder *Align Sprite* rundet die Textur-Koordinaten auf saubere Grenzwerte ab und verhindert Darstellungsfehler in Font-Engines3. Weiterhin tritt bei unzureichender Z-Puffer-Präzision Z-Fighting auf, bei dem nah beieinanderliegende Polygone flackern; dies wird backendseitig durch die Forcierung von 32-Bit-Floating-Point-Tiefenpuffern unter modernen Schnittstellen wie Vulkan behoben.

### **Widescreen-Modifikationen und Frustum-Anpassung**

Die bloße Änderung des Bildseitenverhältnisses von historischem 4:3 auf zeitgemäßes 16:9 oder 21:9 führt im Frontend zu gestreckten und unproportionalen Bildinhalten. Authentische Widescreen-Verbesserungen modifizieren daher die Projektionsmatrix direkt im Speicher der emulierten Maschine.  
Hierbei wird primär das Horizontal-Plus-Verfahren (Hor+) angewendet, welches den horizontalen Öffnungswinkel der Kamera (Field of View) erweitert, während die vertikale Bildachse unverändert bleibt. Dieser Eingriff kollidiert jedoch mit integrierten Performance-Optimierungen klassischer Spiele: Engines nutzten aggressives Frustum-Culling, bei dem alle Objekte, die außerhalb des ursprünglichen 4:3-Blickfeldes lagen, nicht zur Render-Pipeline geschickt wurden. Fehlt ein entsprechender Culling-Patch, führt dies zu drastischem Geometrie-Popping, bei dem Häuser, Bäume und Spielfiguren erst mitten im sichtbaren Randbereich des Breitbildschirms aufpoppen.  
Gleichzeitig verzerren zweidimensionale Benutzeroberflächen. Da HUD-Elemente als separate Overlays gerendert werden, werden Fadenkreuze, Lebensbalken und Rundinstrumente bei globaler Bildstreckung oval verzerrt. Professionelle Widescreen-Patches müssen folglich die 3D-Kameramatrix modifizieren, während das 2D-Interface zentriert auf eine ungestreckte 4:3-Ebene verankert oder durch neu skalierte Widescreen-Grafiken ersetzt wird.

### **HD-Textur-Injektion und AI-Upscaling**

Das dynamische Ersetzen nativer Texturen zur Laufzeit durch hochauflösende, KI-generierte Assets (mittels neuronaler Architekturen wie ESRGAN oder RealSR) stellt ein mächtiges grafisches Enhancement dar11. DuckStation und PCSX2 nutzen hierfür Hash-basierte Abgleichsysteme im Videospeicher11.  
DuckStation erfordert eine strikte Katalogisierung basierend auf der Seriennummer des Mediums im Format textures/\[SERIAL\]/replacements/ (beispielsweise SLUS-01042 für *Parasite Eve 2*)11. Die Dateien folgen einer kryptischen Nomenklatur, welche VRAM-Hash, Farbpaletten-Hash und Sub-Rechteck-Positionen abbildet, wie etwa texupload-P4-\[HASH1\]-\[HASH2\]-64x256-0-192-64x64-P0-1411.  
Wird ein Texturpaket unbedacht injiziert, erzeugt das asynchrone Nachladen großer Bilddateien von der Festplatte massive Mikroruckler während des Spielens. Das Konfigurations-Backend muss daher zwingend die VRAM-Cache-Option *Preload Texture Replacements* setzen, damit alle Texturen vor Spielbeginn in den Grafikspeicher transferiert werden20. Zudem müssen die Texturen mit Alphakanal-Filtern aufbereitet sein; unvollständige Transparenzmasken führen sonst zu sichtbaren Saumkanten (Alpha Bleeding) um Sprites und Laubelemente11.

## **Latenzminimierung und Framerate-Architektur**

### **Run-Ahead und Preemptive Frames im Libretro-Framework**

Traditionelle Emulation akkumuliert Verzögerungen: Polling-Latenzen der Betriebssystem-Treiber, Berechnungsverzögerungen des emulierten Framebuffers und Pufferungen des Desktop-Compositors summieren sich rasch auf 3 bis 6 Frames Eingabeverzögerung. Das Libretro-Ökosystem implementiert mathematische Zustandsberechnungen, um diese Latenz unter das Niveau der Originalhardware zu senken8.  
Die Methode *Run-Ahead* (run\_ahead\_enabled \= "true") zwingt den Emulator, bei jedem Frame die Spiel- und Renderlogik deterministisch um eine definierte Anzahl von Zyklen (run\_ahead\_frames) in die Zukunft zu berechnen, das Bild vorzeitig an den Bildschirm auszugeben und den Zustand anschließend via internem Schnappschuss (Save-State) blitzschnell zurückzusetzen8. Da diese Methode extreme CPU-Ressourcen bindet und bei asynchronen Soundtreibern zu Knacksern neigt, stabilisiert die Option *Secondary Instance* (run\_ahead\_secondary\_instance \= "true") den Ablauf, indem eine primäre Instanz die Sound- und Basislogik hält, während eine geklonte Instanz die spekulative Zukunft berechnet8.  
Die modernere Alternative stellen *Preemptive Frames* (preemptive\_frames\_enable \= "true") dar12. Hierbei läuft die Emulation regulär ohne dauerhafte Mehrfachberechnung. Erst wenn das Backend einen neuen Eingabe-Impuls registriert, springt der Emulator sofort um die konfigurierten Frames in die Vergangenheit, speist den neuen Tastendruck ein, berechnet die Zwischenschritte in Mikrosekunden neu und gibt den finalen Frame aus. Dies spart massive Prozessorlast und vermeidet Audioaussetzer12.

| Leistungsmerkmal | Standard Run-Ahead | Preemptive Frames |
| :---- | :---- | :---- |
| **Rechenaufwand (CPU)** | Permanent extrem hoch; skaliert linear mit der Frameanzahl15. | Situativ; Lastspitzen treten ausschließlich bei Input-Änderungen auf. |
| **Audio-Stabilität** | Anfällig für Pufferabrisse; erfordert Secondary Instance8. | Nativ hoch; Soundberechnung wird im regulären Zyklus weitergeführt. |
| **Speicheranforderung** | Hoch durch kontinuierliches Klonen ganzer RAM-Zustände8. | Moderat; nutzt einen schlanken Ringpuffer vergangener Zustände. |
| **Einsatzprofil** | Ältere 8-Bit- und 16-Bit-Systeme mit simpler Architektur (z. B. NES, SNES). | Bis zu 32-Bit-Plattformen und frühe 3D-Konsolen (GBA, PS1) stabil einsetzbar. |

Für Plattformen jenseits der 32-Bit-Ära (PlayStation 2, GameCube, Dreamcast) sind diese Verfahren technisch nicht anwendbar, da die schiere Größe der Speicherabbilder und asynchrone Multi-Threading-Prozesse einen deterministischen Frame-Rollback innerhalb des 16-Millisekunden-Fensters unmöglich machen.

### **Framerate-Unlocks und Timestep-Entkopplung**

Während 2D-Titel unverrückbar an 50 Hz (PAL) oder 60 Hz (NTSC) gekoppelt sind, erlauben moderne Emulatoren für PlayStation 3 (RPCS3) und Nintendo Switch (Ryujinx) das Freischalten der Framerate auf 60, 120 oder unbegrenzte Bilder pro Sekunde4.  
Die zentrale Fehlerquelle liegt in der Kopplung der Spielphysik an die Render-Frequenz (Fixed Timestep)25. Ist eine Spiellogik darauf programmiert, dass jeder Frame exakt 1/30 Sekunde entspricht, führt ein Forcieren von 60 FPS zu einer Verdopplung der gesamten Spielgeschwindigkeit (Fast-Forward-Effekt), wodurch Zeitlimits ablaufen und Physik-Engines kollabieren25.  
Bei modernen Switch-Emulatoren wie Ryujinx erfordert die FPS-Erweiterung daher ein präzises Patching-System, welches in zwei getrennten Dateipfaden operiert4:  
*ExeFS-Patches* liegen als Binär-Diffs (patch.ips) oder strukturierte Instruktions-Skripte (.pchtxt) im Verzeichnis Ryujinx/mods/contents/\[TitleID\]/\[ModName\]/exefs/10. Sie überschreiben assemblierte Maschinenbefehle im Hauptspeicher der emulierten Anwendung, modifizieren VSync-Aufrufe und entkoppeln die interne Zeittaktung der Engine24.  
*RomFS-Patches* hingegen werden im parallelen Verzeichnis .../romfs/ abgelegt und ersetzen Spieldaten wie INI-Dateien von Middleware-Engines (z. B. Unreal Engine oder Havok)4. Ein statischer 60-FPS-Patch führt jedoch dazu, dass das Spiel bei Leistungseinbrüchen unter 60 Bilder pro Sekunde in extreme Zeitlupe verfällt25. Für ein stabiles Erlebnis müssen Konfigurations-Backends daher zwingend dynamische FPS-Mods (wie Chuck's Dynamic FPS) hinterlegen, welche die Zeitschritte (Delta Time) in Echtzeit an die tatsächlich erreichte Render-Leistung anpassen4.

### **Shader-Kompilierung und Bildausgabe-Synchronisation**

Ein massives Ärgernis bei modernen Grafik-APIs (Vulkan, DirectX 12\) sind Shader-Kompilierungs-Ruckler (Stutter). Wenn ein Spiel einen visuellen Effekt erstmals aufruft, muss der Treiber den Zwischencode (SPIR-V) in systemspezifischen GPU-Maschinencode übersetzen, was Render-Pausen von bis zu 500 Millisekunden provoziert.  
Moderne Backend-Setups begegnen diesem Phänomen durch standardisierte Aktivierung von *Graphics Pipeline Libraries* (Vulkan GPL). Diese Treiberfunktion erlaubt es Emulatoren, Shader-Pipelines asynchron im Hintergrund zu kompilieren, ohne die Rendering-Schleife zu blockieren. Im GameCube- und Wii-Emulator Dolphin wird alternativ das *UberShader*\-Verfahren genutzt, welches einen monolithischen Universal-Shader auf der GPU ausführt, der die gesamte Hardware-Grafikpipeline nachbildet und Shader-Ruckler vollständig eliminiert, wenngleich dies signifikante GPU-Rohleistung voraussetzt.  
Für eine ruckelfreie Bildausgabe muss die Bildwiederholrate mittels variabler Synchronisation (G-Sync oder FreeSync) an das Panel übergeben werden. Hierfür muss das Frontend den Emulator im rahmenlosen Fenstermodus (Borderless Windowed) unter Nutzung des modernen Desktop-Duplication- oder Flip-Modells starten, um den Latenzaufschlag des klassischen V-Sync-Dreifachpuffers zu umgehen.

## **Konsolengenerations-Spezifika und Fehlerquellen-Matrix**

Die architektonische Vielfalt historischer Plattformen verlangt maßgeschneiderte Konfigurationspfade. Die nachfolgende Übersicht stellt die systemspezifischen Besonderheiten, typischen visuellen Fehlerbilder und empfohlenen Gegenmaßnahmen für Entwickler dar.

| Systemklasse | Primäre Emulatoren | Empfohlene Enhancements | Typische Artefakte / Fallstricke | Technische Gegenmaßnahme |
| :---- | :---- | :---- | :---- | :---- |
| **Klassische Arcade (2D)** | MAME, FBNeo7 | CRT-Shader (Royale/Lottes), Integer Scaling, Preemptive Frames12 | Bildunschärfe bei krummen Skalierungsfaktoren; VSync-Input-Lag. | Integer Scaling erzwingen (integer\_scale \= "true"); Audioschnittstelle auf WASAPI/ASIO mit Puffer ≤ 32 ms15. |
| **5\. Generation (PS1, N64)** | DuckStation, Ares, Simple647 | PGXP (Präzisionsgeometrie), 4K Internal Res, Widescreen, Textur-Packs11 | Stark wackelnde Polygone (Fixed-Point-Mangel); Texturverkrümmung bei PGXP11. | PGXP Vertex Cache & Perspective Correction aktivieren; MDEC-Routine-Hacks für FMV-Stabilität20. |
| **6\. Generation (PS2, GC, DC)** | PCSX2, Dolphin, Flycast7 | 3×–6× Native Res, 16× Anisotrope Filterung, Widescreen, HD-Texturen11 | Ghosting, vertikale Streifen in Schriften, fehlerhaftes Frustum-Culling3. | PCSX2: Half-Pixel Offset (Special Texture), Round Sprite aktivieren3; Dolphin: Backend Vulkan mit UberShaders. |
| **7\. Generation (PS3, Wii)** | RPCS3, Dolphin7 | 4K Skalierung, 60/120 FPS VBlank-Unlock, Asynchrones Texture Streaming7 | Physik-Desynchronisation, Loop-Crashes bei unpassenden Frameraten, Shader-Stutter. | RPCS3: VBlank Frequency gezielt patchen (z. B. 120 Hz für 60 FPS Target); Write Color Buffers forcieren. |
| **Moderne Ära (Switch)** | Ryujinx (und Derivate)4 | ExeFS/RomFS 60-FPS-Patches, Resolution Scale 2×, Dynamic Resolution Disabler4 | Zeitlupeneffekt bei Framedrops; instabile Speicherverwaltung bei VRAM-Überlauf25. | Dynamische FPS-Mods (Chuck's Mod) mit ExeFS-Patches kombinieren; Vulkan Host Memory Management aktivieren4. |

Auf Plattformebene müssen Backend-Pipelines diese Parameter dynamisch per Spiel-Identifikator (Game ID/CRC) und nicht global verwalten11. Ein global forzierter Half-Pixel-Offset-Hack in PCSX2 bereinigt beispielsweise Titel wie *Bully*, führt jedoch in Spielen, die keine Texturverschiebungen nutzen, zu fehlerhaften Kanten und Geometrieverschiebungen3.

## **Spezialarchitektur für Lightgun-Ökosysteme**

Lightgun-Titel repräsentieren den komplexesten Bereich in modernen Multi-Plattform-Cabinets1. Da moderne LCD-, OLED- und Projektionsdisplays physikalisch bedingt keine Elektronenstrahl-Zeilenabtastung wie historische Bildröhren aufweisen, müssen Zielkoordinaten über externe optische und sensorische Tracking-Verfahren interpoliert werden2.

### **Hardware-Tracking-Paradigmen**

Die gegenwärtige Hardware-Landschaft stützt sich auf grundverschiedene Messprinzipien mit spezifischen Vor- und Nachteilen für Cabinet-Konstrukteure2:  
Die *Sinden Lightgun* integriert eine optische Hochgeschwindigkeitskamera in der Waffenmündung2. Das System basiert zwingend auf der Darstellung eines kontrastreichen, ununterbrochenen Rahmens (Border) an den Rändern des Displays2. Die bordeigene Firmware errechnet anhand der geometrischen Verzerrung dieses Rechtecks im Sichtfeld der Kamera die exakte Zielposition2. Dieses Prinzip funktioniert auf beliebigen Anzeigetechnologien (einschließlich OLED und Projektoren), reagiert jedoch empfindlich auf Spiegelungen und verlangt einen Mindestabstand von 1,5 bis 2,5 Metern zum Monitor2.  
Das *Gun4IR*\-System nutzt stattdessen eine aktive Infrarot-Triangulation2. Vier präzise positionierte IR-LED-Punkte an den Ecken des Bildschirmrahmens werden von einer IR-Kamera in der Pistole erfasst2. Ein integrierter Mikrocontroller kalkuliert die Position mit extrem geringer Latenz von typischerweise 3 bis 5 Millisekunden2. Das Tracking arbeitet pixelgenau und unbeeindruckt von wechselnden Lichtverhältnissen im Raum, bedingt jedoch feste Montageleisten am Gehäuse2.  
Günstigere Alternativen wie *Wiimote mit DolphinBar* nutzen eine simple Zweipunkt-IR-Leiste1. Durch das Fehlen zweier weiterer Referenzpunkte neigt dieses System bei Verkippen der Waffe zu Roll-Verzerrungen und Drift28. Ältere Systeme wie *Aimtrak* operieren über relative Mausbewegungen mit interner Glättung, erfordern jedoch häufige Neukalibrierungen, sobald der Spieler seine Position vor dem Automaten verändert1.

### **Border- und Aspect-Ratio-Management für kamerabasierte Systeme**

Für kamerabasierte Systeme wie die Sinden Lightgun ist das unterbrechungsfreie Rendern des Rahmens überlebenswichtig2. Wird ein 4:3-Arcade-Titel unkorrigiert auf einem 16:9-Widescreen-Monitor dargestellt, gerät die optische Geometrieberechnung aus dem Takt.  
Konfigurations-Skripte müssen den Tracking-Rahmen deterministisch bereitstellen7. Im Libretro-Umfeld geschieht dies über dedizierte Slang-Border-Shader oder pixelgenaue PNG-Overlays5. In Standalone-Umgebungen muss entweder das Frontend (z. B. RetroBat) das Artwork-Bezel inklusive des weißen Randes um das zentrierte Spielfenster zeichnen oder ReShade muss einen entsprechenden Border-Shader injizieren5. Kritisch sind hierbei Rundungsfehler: Besitzt der weiße Rahmen Nachkommastellen in den Pixelkoordinaten, entstehen Kantenbrüche, die zum Abreißen des Zielsignals führen; Rahmenbreiten müssen zwingend als ganzzahlige Integer-Werte definiert werden7.

### **DemulShooter-Architektur und Multi-Gun-Isolation**

Unter Windows existiert auf Treiberebene die gravierende Hürde, dass das Betriebssystem standardmäßig alle angeschlossenen USB-Mäuse zu einem einzigen Cursor aggregiert. Wenn zwei Spieler gleichzeitig mit Lightguns zielen, überschreiben sich die Mauskoordinaten gegenseitig, was Mehrspieler-Arcade-Partien unmöglich macht. Das Hilfsprogramm *DemulShooter* löst dieses Problem durch systemnahes Memory-Hooking und die direkte Nutzung der RawInput-Schnittstelle13.  
DemulShooter fängt die absoluten Positionsdaten der einzelnen Hardware-IDs isoliert über Windows RawInput ab, bevor der Zielprozess sie verarbeiten kann13. Anschließend injiziert das Tool die berechneten Achsenkoordinaten und Schussflags direkt in den reservierten Arbeitsspeicher des Emulators oder Arcade-Dump-Prozesses13.  
Die Einbindung in Frontend-Startskripte erfolgt über strikte Befehlszeilenparameter6:

DemulShooter.exe \-target=\[target\] \-rom=\[rom\] \[Optionen\]

Für Sega Model 2 Arcade-Spiele lautet der Aufruf beispielsweise DemulShooter.exe \-target=model2 \-rom=hotd6. Moderne Arcade-Titel unter TeknoParrot nutzen spezifische Targets wie DemulShooter.exe \-target=ringwide \-rom=sdr \-parrotloader32. Ergänzende Flags wie \-nocrosshair unterdrücken emulatorinterne Fadenkreuze, während \-widescreen die Speicherinjektion an modifizierte Breitbild-Framegrößen anpasst14.  
Bei der Automatisierung müssen Frontend-Entwickler darauf achten, dass DemulShooter nicht blockierend gestartet wird (unter Windows mittels des start "" ... Befehls), da das Skript sonst auf die Beendigung von DemulShooter wartet und der eigentliche Emulator niemals lädt29. DemulShooter nistet sich im Infobereich der Taskleiste ein, signalisiert ein erfolgreiches Speicher-Hooking durch ein grünes Fadenkreuz-Icon und beendet sich automatisch, sobald der Hauptprozess schließt14.

### **Haptisches Feedback: DirectOutput Framework (DOF) und MameHooker**

Ein authentisches Arcade-Erlebnis verlangt physisches Feedback. Echte Arcade-Pistolen nutzen massive Magnetspulen (Solenoids) für harten mechanischen Rückstoß sowie Mündungsfeuer-LEDs2.  
In klassischen Arcade-Setups liest das Programm *MameHooker* Statusmeldungen aus, die von Emulatoren über native Ausgabe-Schnittstellen bereitgestellt werden (beispielsweise MAME mit dem Startparameter \-output windows)35. Registriert das Spiel einen Schuss oder ein Nachlade-Ereignis, sendet es strukturierte Signale wie P1\_Gun\_Recoil \= 1 an MameHooker, welches Steuerbefehle an Relaisplatinen, Pac-Drive oder FTDI-Controller absetzt1.  
Im Ökosystem von Fried's Retrogaming Kit wird diese Funktionalität mit dem DirectOutput Framework (DOF) verknüpft1. Ursprünglich für virtuelle Flipper zur Ansteuerung von Schützen, Getriebemotoren und Adressierbaren LED-Streifen entwickelt, fungiert DOF in Multi-Purpose-Arcade-Cabinets als zentrale Abstraktionsschicht1. Über Interop-Bridges leiten Frontends die Schuss- und Schadens-Events aus MameHooker und DemulShooter direkt an DOF weiter, wodurch Lichtbalken und Schütze präzise im Takt der emulierten Waffen auslösen1.

### **Systemspezifische Lightgun-Besonderheiten**

*MAME:* In der Konfigurationsdatei mame.ini müssen die Parameter lightgun 1, multimouse 1 und lightgun\_device rawinput gesetzt sein. Da Windows die RawInput-Maus-Indizes bei jedem Neustart oder Umstecken von USB-Ports neu vergibt, droht eine Vertauschung von Spieler 1 und Spieler 2\. Dies wird im Kit-Backend verhindert, indem feste Controller-Mapping-Dateien (ctrlr) generiert werden, die Eingabegeräte strikt anhand ihrer Hardware-Vendor- und Product-ID (VID/PID) ansteuern.  
*Sega Model 2 & Model 3 (Supermodel):* Model 2 erfordert im Emulator-Menü zwingend die Einstellung XInput=1 und UseRawInput=0, wenn DemulShooter genutzt wird, da die Eingaben direkt in den Speicher geschrieben werden30. Entscheidend ist, dass bei jedem Spiel nach der Ersteinrichtung einmalig das interne Service-Testmenü des Arcade-Boards aufgerufen werden muss, um die Minimal- und Maximalwerte der analogen Achsen für beide Spieler im NVRAM abzuspeichern28.  
*PlayStation 1 (DuckStation) & PlayStation 2 (PCSX2):* DuckStation bietet exzellente native Emulation der Namco GunCon über Mauseingaben7. PCSX2 hingegen emuliert GunCon 2 über dessen USB-Subsystem37. Im modernen Qt-Frontend müssen für den 2-Spieler-Betrieb separate RawInput-Mäuse konfiguriert werden; die Verwendung des globalen Mausmodus führt dazu, dass beide Spieler denselben GunCon-Zeiger steuern37.  
*Nintendo Wii (Dolphin):* Dolphin erlaubt zwei Betriebsmodi: Den nativen Bluetooth-Passthrough für originale Wiimotes an einer DolphinBar oder die Emulation des optischen Zeigers über absolute PC-Mauskoordinaten moderner Lightguns1. Bei emulierten Profilen muss die interne Zeigertotzone auf null gesetzt und der vertikale/horizontale Streckungsbereich exakt kalibriert werden, um Koordinatenverzerrungen am Monitorrand zu vermeiden.

## **Umfassende Fehlerursachen- und Troubleshooting-Matrix**

Die nachfolgende Tabelle aggregiert die kritischsten Fehlerbilder, die bei der Aktivierung visueller, latenzbezogener und peripherer Enhancements auftreten, und definiert die deterministischen Lösungswege für automatisierte Reparaturroutinen1.

| Fehlerbild | Primäre Ursache | Diagnose- und Verifizierungspfad | Deterministische Behebung |
| :---- | :---- | :---- | :---- |
| **Schwarzer Bildschirm oder Deadlock bei Spielstart mit DemulShooter** | UAC-Rechtekonflikt oder blockierendes Startskript im Frontend30. | Prüfung, ob DemulShooter mit Administratorrechten läuft, während der Emulator eingeschränkte Rechte besitzt30. | Prozessebene vereinheitlichen; Startaufruf via Windows start "" asynchron ausführen6. |
| **Doppel-Eingaben / Cursor-Springen bei Gamepads und Guns** | Konflikt zwischen physischem DirectInput-Gerät und virtuellem Wrapper (z. B. vJoy/ViGEmBus)1. | Parallele Eingabesignale in der Systemsteuerung (joy.cpl) beobachten. | HidHide-Treiberrichtlinie aktivieren, um physische Schnittstellen vor dem Emulator zu verbergen1. |
| **Spiellogik läuft in doppelter Geschwindigkeit (Fast-Forward)** | Feste Kopplung der Physikschleife an die Bildrate bei 60-FPS-Unlocks25. | Framezähler gegen interne Spieluhr (Timer läuft zu schnell) prüfen. | ExeFS-Patch gegen dynamischen Delta-Time-Patch tauschen oder Framelimiter reaktivieren4. |
| **Zittern (Jitter) und Zielfehler bei Lightgun-Fadenkreuzen** | Infrarotinterferenz durch Sonnenlicht oder Bildreflektionen am Monitor2. | Tracking-Vorschau im Konfigurationsfenster der Waffe auf Bildrauschen prüfen30. | Glättungsfilter im Treiber anheben (Smooth Mode); Raumlicht abdunkeln; Rahmenkontrast erhöhen2. |
| **Knacken im Audiostream und Stottern bei aktiviertem Run-Ahead** | CPU-Kernüberlastung durch mehrfache State-Rollbacks innerhalb eines Frame-Intervalls15. | Auslastung des primären Ausführungsthreads in Windows-Leistungsüberwachung prüfen15. | Run-Ahead auf 1 Frame begrenzen; auf Preemptive Frames wechseln oder Secondary Instance aktivieren8. |
| **Geometrielücken und plötzliches Aufpoppen bei Widescreen** | Das interne Frustum-Culling der Original-Engine maskiert periphere Objekte. | Kameraschwenk durchführen: Objekte erscheinen abrupt am linken/rechten Monitorrand. | Spezifischen ASM-/Hex-Patch zur Deaktivierung des Frustum-Cullings in den Emulator laden. |
| **HD-Textur-Paket wird ignoriert (DuckStation/PCSX2)** | Diskrepanz zwischen Regions-Seriennummer (Game Serial) und Ordnername oder fehlerhafte Hashes11. | Emulations-Logfile auf Textur-Ladefehler und Dateipfade analysieren11. | Verzeichnis exakt anpassen (z. B. SLUS-XXXXX); Option Preload Texture Replacements aktivieren11. |

## **Synthese und Handlungsempfehlungen für die Backend-Entwicklung**

Die erfolgreiche Realisierung des Enhancement-Bereichs in Fried's Retrogaming Kit (Concept 0.5, v.07) erfordert ein Umdenken weg von globalen Schaltern hin zu granularen, zustandsgeprüften Regelsätzen1. Jedes Enhancement stellt einen Eingriff in die Ausführungssemantik dar und muss als potenzieller Fehlerherd isoliert werden.  
Für die praktische Umsetzung im Rahmen der Kit-Architektur ergeben sich drei verbindliche Entwicklungsrichtlinien:  
Erstens muss das transaktionale Sicherungssystem konsequent vor jeder Modifikation greifen1. Bevor Skripte Render-Auflösungen, Widescreen-Patches oder Shader in Dateien wie retroarch.cfg, PCSX2.ini oder DuckStation-Konfigurationen schreiben, muss über die API ein verifizierter Snapshot angelegt werden1. Schlägt ein Emulatorstart fehl oder meldet der Grafiktreiber Instabilitäten, muss das Backend fähig sein, die Konfiguration im Rahmen der Gated Execution Policy unmittelbar auf den letzten bekannten stabilen Zustand zurückzurollen1.  
Zweitens dürfen Rendering-Hacks – insbesondere Half-Pixel Offset, Round Sprite und Textur-Injektionen – niemals global für ganze Konsolengenerationen aktiviert werden3. Das Backend muss spielebezogene Profile verwalten, die anhand von Prüfsummen oder Seriennummern exakt jene Korrekturwerte anwenden, die für den jeweiligen Titel validiert wurden11. Ein universeller Fix beseitigt ein Problem in einem Titel, erzeugt jedoch in zehn anderen unvorhergesehene Bildfehler3.  
Drittens erfordert das Lightgun-Segment eine deterministische Prozess- und Peripherie-Orchestrierung: Startskripte müssen DemulShooter zwingend asynchron vor dem Zielprozess initiieren, Berechtigungsebenen synchronisieren und sicherstellen, dass RawInput-Mäuse über statische Hardware-IDs (VID/PID) anstelle dynamischer OS-Indizes zugewiesen werden6. Werden kamerabasierte Systeme wie Sinden betrieben, muss das Konfigurationsmodul mathematisch sicherstellen, dass Bezels und Border-Shader unter strikter Beibehaltung ganzzahliger Pixelgrenzen ohne Skalierungsverzerrung auf dem Display gerendert werden2. Wird diese Systematik konsequent durchgesetzt, transformiert das Kit heterogene Emulationslandschaften in ein stabiles, fehlerresistentes Gesamtsystem mit maximaler audiovisueller Wiedergabetreue1.

#### **Referenzen**

> 1. \[FREE TOOL\] Fried's Retrogaming Kit (v0.1) — Lossless Baller, [https://www.vpforums.org/index.php?showtopic=58353](https://www.vpforums.org/index.php?showtopic=58353)  
> 2. PC Gun Controller Guide: How to Choose the Right One, [https://electronics.alibaba.com/buyingguides/pc-gun-controller-guide-how-to-choose-in-2025](https://electronics.alibaba.com/buyingguides/pc-gun-controller-guide-how-to-choose-in-2025)  
> 3. \[GS-FIX\]: Upscaling Corrections Dump \#1 · Issue \#6217 \- GitHub, [https://github.com/PCSX2/pcsx2/issues/6217](https://github.com/PCSX2/pcsx2/issues/6217)  
> 4. Shin Megami Tensei V: Vengeance. romfs 60FPS \+ 1080p Mod, [https://gbatemp.net/threads/shin-megami-tensei-v-vengeance-romfs-60fps-1080p-mod.657105/page-2](https://gbatemp.net/threads/shin-megami-tensei-v-vengeance-romfs-60fps-1080p-mod.657105/page-2)  
> 5. Changelog \- Emulation station powered for Windows \- Retrobat, [https://www.retrobat.org/en/changelog/](https://www.retrobat.org/en/changelog/)  
> 6. tkssitch's Content \- Page 2 \- LaunchBox Community Forums, [https://forums.launchbox-app.com/profile/152280-tkssitch/content/page/2/?type=forums\_topic\_post](https://forums.launchbox-app.com/profile/152280-tkssitch/content/page/2/?type=forums_topic_post)  
> 7. \[RETROBAT\] EmulationStation pour windows \- Page 2 \- Général, [https://www.logic-sunrise.com/forums/topic/88853-retrobat-emulationstation-pour-windows/page-2](https://www.logic-sunrise.com/forums/topic/88853-retrobat-emulationstation-pour-windows/page-2)  
> 8. r/RetroArch on Reddit: CPU Run-ahead feature (1.7.2), what is it, [https://www.reddit.com/r/RetroArch/comments/8kx0tq/cpu\_runahead\_feature\_172\_what\_is\_it\_called\_in\_the/](https://www.reddit.com/r/RetroArch/comments/8kx0tq/cpu_runahead_feature_172_what_is_it_called_in_the/)  
> 9. Handheld Border Shaders \- Shaders \- Libretro Forums, [https://forums.libretro.com/t/handheld-border-shaders/2551?page=9](https://forums.libretro.com/t/handheld-border-shaders/2551?page=9)  
> 10. FAQ and Troubleshooting \- ryujinx-mirror/Ryujinx, [https://git.nadeko.net/Ryujinx\_Mirror/Ryujinx/wiki/FAQ-and-Troubleshooting](https://git.nadeko.net/Ryujinx_Mirror/Ryujinx/wiki/FAQ-and-Troubleshooting)  
> 11. Texture Replacement · stenzek/duckstation Wiki \- GitHub, [https://github.com/stenzek/duckstation/wiki/Texture-Replacement](https://github.com/stenzek/duckstation/wiki/Texture-Replacement)  
> 12. libretroConfig.py \- GitHub, [https://github.com/batocera-linux/batocera.linux/blob/master/package/batocera/core/batocera-configgen/configgen/configgen/generators/libretro/libretroConfig.py](https://github.com/batocera-linux/batocera.linux/blob/master/package/batocera/core/batocera-configgen/configgen/configgen/generators/libretro/libretroConfig.py)  
> 13. DemulShooter (Dual light gun on DEMUL, Model2, Dolphin, Silent, [http://forum.arcadecontrols.com/index.php?topic=149714.2800](http://forum.arcadecontrols.com/index.php?topic=149714.2800)  
> 14. Usage \- argonlefou/DemulShooter GitHub Wiki, [https://github-wiki-see.page/m/argonlefou/DemulShooter/wiki/Usage](https://github-wiki-see.page/m/argonlefou/DemulShooter/wiki/Usage)  
> 15. Rpi3b+ unplayable on 4k TCL \- RetroPie Forum, [https://retropie.org.uk/forum/topic/26622/rpi3b-unplayable-on-4k-tcl](https://retropie.org.uk/forum/topic/26622/rpi3b-unplayable-on-4k-tcl)  
> 16. Issue with Half Pixel Offset \#2775 \- Yakuza 1 \- GitHub, [https://github.com/PCSX2/pcsx2/issues/2775](https://github.com/PCSX2/pcsx2/issues/2775)  
> 17. Reducing Blurry Visuals on Bully : r/PCSX2 \- Reddit, [https://www.reddit.com/r/PCSX2/comments/1jsv783/reducing\_blurry\_visuals\_on\_bully/](https://www.reddit.com/r/PCSX2/comments/1jsv783/reducing_blurry_visuals_on_bully/)  
> 18. PCSX2 First Time Setup and Configuration \- GitHub, [https://github.com/PCSX2/pcsx2/blob/master/pcsx2/Docs/Configuration\_Guide/Configuration\_Guide.md](https://github.com/PCSX2/pcsx2/blob/master/pcsx2/Docs/Configuration_Guide/Configuration_Guide.md)  
> 19. raising graphics quality causes lights/shadows to shift to the side in, [https://www.reddit.com/r/PCSX2/comments/1fqhikd/raising\_graphics\_quality\_causes\_lightsshadows\_to/](https://www.reddit.com/r/PCSX2/comments/1fqhikd/raising_graphics_quality_causes_lightsshadows_to/)  
> 20. r/duckstation on Reddit: If anyone is tryng to use custom textures on, [https://www.reddit.com/r/duckstation/comments/1d962gg/if\_anyone\_is\_tryng\_to\_use\_custom\_textures\_on/](https://www.reddit.com/r/duckstation/comments/1d962gg/if_anyone_is_tryng_to_use_custom_textures_on/)  
> 21. PS1/Duckstation texture packs are now a thing, Vagrant Story, [https://gbatemp.net/threads/ps1-duckstation-texture-packs-are-now-a-thing-vagrant-story.662541/](https://gbatemp.net/threads/ps1-duckstation-texture-packs-are-now-a-thing-vagrant-story.662541/)  
> 22. Duckstation texture replacement is awesome : r/WipeOut \- Reddit, [https://www.reddit.com/r/WipeOut/comments/1rtke8i/duckstation\_texture\_replacement\_is\_awesome/](https://www.reddit.com/r/WipeOut/comments/1rtke8i/duckstation_texture_replacement_is_awesome/)  
> 23. Configuration manettes Logitech Precision \- RetroBat, [https://retrobat.forumgaming.fr/t3518-configuration-manettes-logitech-precision](https://retrobat.forumgaming.fr/t3518-configuration-manettes-logitech-precision)  
> 24. Ryujinx Mods Guide: How to Add and Manage Mods, [https://ryujinx.io/mods/](https://ryujinx.io/mods/)  
> 25. Pokemon Legends Z-A 60 FPS Patch on real Switch Hardware, [https://gbatemp.net/threads/pokemon-legends-z-a-60-fps-patch-on-real-switch-hardware.676159/page-2](https://gbatemp.net/threads/pokemon-legends-z-a-60-fps-patch-on-real-switch-hardware.676159/page-2)  
> 26. How to install Luigis Mansion 3 60 fps mode? : r/Ryujinx \- Reddit, [https://www.reddit.com/r/Ryujinx/comments/zcban8/how\_to\_install\_luigis\_mansion\_3\_60\_fps\_mode/](https://www.reddit.com/r/Ryujinx/comments/zcban8/how_to_install_luigis_mansion_3_60_fps_mode/)  
> 27. Visuals Fixed 1.1.2 Mod for The Legend of Zelda \- GameBanana, [https://gamebanana.com/mods/448096](https://gamebanana.com/mods/448096)  
> 28. DemulShooter (Dual light gun on DEMUL, Model2, Dolphin, Silent, [https://forum.arcadecontrols.com/index.php?topic=149714.3480](https://forum.arcadecontrols.com/index.php?topic=149714.3480)  
> 29. \[SOLVED\] \- Alien Extermination bat file help \- RocketLauncher Forums, [https://www.rlauncher.com/forum/index.php?threads/alien-extermination-bat-file-help.6596/](https://www.rlauncher.com/forum/index.php?threads/alien-extermination-bat-file-help.6596/)  
> 30. DemulShooter (Dual light gun on DEMUL, Model2, Dolphin, Silent, [https://forum.arcadecontrols.com/index.php?topic=149714.3440](https://forum.arcadecontrols.com/index.php?topic=149714.3440)  
> 31. GitHub \- mchenier/arcade\_controllers\_configuration, [https://github.com/mchenier/arcade\_controllers\_configuration](https://github.com/mchenier/arcade_controllers_configuration)  
> 32. DemulShooter (Dual light gun on DEMUL, Model2, Dolphin, Silent, [https://forum.arcadecontrols.com/index.php?topic=149714.920](https://forum.arcadecontrols.com/index.php?topic=149714.920)  
> 33. Namco ES4 \- argonlefou/DemulShooter GitHub Wiki, [https://github-wiki-see.page/m/argonlefou/DemulShooter/wiki/Namco-ES4](https://github-wiki-see.page/m/argonlefou/DemulShooter/wiki/Namco-ES4)  
> 34. Demulshooter krieg ich nicht zum Laufen : r/lightgunshooters \- Reddit, [https://www.reddit.com/r/lightgunshooters/comments/1rzz2wh/cant\_get\_demulshooter\_to\_work/?tl=de](https://www.reddit.com/r/lightgunshooters/comments/1rzz2wh/cant_get_demulshooter_to_work/?tl=de)  
> 35. Mame Outputs and Arduino \- Arcade Controls Forum, [http://forum.arcadecontrols.com/index.php?topic=159700.0](http://forum.arcadecontrols.com/index.php?topic=159700.0)  
> 36. Help with solenoid choice for recoil \- Arcade Controls Forum, [http://forum.arcadecontrols.com/index.php?topic=163300.0](http://forum.arcadecontrols.com/index.php?topic=163300.0)  
> 37. \[BUG\]: USB \- GunCon 2's calibration shots not always work as, [https://github.com/PCSX2/pcsx2/issues/7618](https://github.com/PCSX2/pcsx2/issues/7618)  
> 38. Dolphin, scaled, no demulshooter, dual GUN4IR \- Facebook, [https://www.facebook.com/groups/903631730390946/posts/1580958915991554/](https://www.facebook.com/groups/903631730390946/posts/1580958915991554/)

Die optische Realitätsnähe in virtuellen Flippersystemen steht und fällt mit der physikalisch korrekten Interaktion von Lichtquellen, Oberflächenmaterialien und optischen Linsenverzerrungen. Während traditionelle Emulatoren ein fixes Videosignal rendern, simulieren **Visual Pinball X (VPX)** und **Future Pinball (unter BAM – Better Arcade Mode)** dynamische Echtzeit-3D-Szenen auf einer schräggestellten Spielfläche (Playfield).

Im Rahmen des Konzepts von *Fried's Retrogaming Kit* und dessen Pinball-Suite-Management müssen diese Parameter deterministisch verwaltet werden, um das typische Ausbrennen von Lampen, unrealistische Kugelreflexionen oder Performance-Einbrüche bei 4K-Auflösung auszuschließen.

## **Visual Pinball X (VPX 10.7 / 10.8): PBR- und Beleuchtungsarchitektur**

VPX hat sich mit den Versionen 10.7 und 10.8 von einer einfachen Shader-Engine zu einem modernen Physically Based Rendering (PBR) Framework weiterentwickelt. Um eine fotorealistische Tiefe zu erreichen, müssen vier Kernbereiche aufeinander abgestimmt werden:

### **1\. PBR-Materialeigenschaften und Playfield-Clearcoat**

Ein realistisches Spielfeld besteht optisch aus bedrucktem Holz, das mit einer hochglänzenden Klarlackschicht (Automotive Clearcoat oder Diamond Plate) versiegelt ist:

* **Roughness (Rauheit):** Der Wert für das Playfield-Material sollte zwischen 0.015 und 0.035 liegen. Ein Wert von 0 wirkt künstlich wie ein Spiegel; ein Wert über 0.06 lässt das Spielfeld matt und stumpf wirken.  
*   
* **Glossiness / Specular Level:** Zwischen 0.85 und 0.95. Bestimmt die Härte der Glanzlichter, die von den GI-Lampen (General Illumination) auf die Spielfläche geworfen werden.  
*   
* **Clearcoat Layer & Clearcoat Roughness:** In VPX 10.8 separat steuerbar. Der Klarlack reflektiert die Umgebung scharf, während die darunterliegende Holz-/Druckschicht eine leicht diffuse Streuung aufweist.  
*   
* **Ball-Reflexion auf dem Playfield:** In den Table-Optionen sollte *Playfield Reflections* aktiviert und auf dynamische Reflexionen begrenzt sein. Wichtig: Die Reflektionsstärke (Ball Reflection Strength) sollte auf 0.35 bis 0.55 gedrosselt werden, da die Stahlkugel im echten Flipper nur bei extrem sauber poliertem Lack wie ein Spiegelbild sichtbar ist.  
* 

### **2\. Kugel-Optik (Ball Rendering & Environment Mapping)**

Die Kugel ist der visuelle Fokuspunkt des Spielers:

* **Ball Material:** Hohe Metallizität (Metalness \= 1.0), minimale Rauheit (Roughness \= 0.01 bis 0.02).  
*   
* **Environment Map (HDRI):** Eine Standard-Graustufen-Reflexion lässt die Kugel plastisch tot wirken. Für maximalen Fotorealismus muss eine hochauflösende Cabinet- oder Raum-Environment-Map geladen werden, die den virtuellen Kastenrahmen, das Backglass und Deckenlichter eines realen Raumes widerspiegelt.  
*   
* **Dynamic Ball Shadows:** In den VPX-Videoeinstellungen zwingend auf *Ambient \+ Dynamic Shadows* setzen. Dies erzeugt sowohl den weichen Umgebungsschatten (Ambient Occlusion direkt unter der Kugel) als auch harte Schlagschatten, wenn die Kugel an aktiven Flashers oder Bumpern vorbeiläuft.  
* 

### **3\. Color Management, HDR und Tone Mapping**

Historische Tische leiden oft unter dem Problem, dass blinkende Lampen das Spielfeld in reines Weiß überstrahlen (Clipping):

* **Tone Mapper:** In VPX 10.8 stehen verschiedene Algorithmen zur Auswahl.  
* 

  * *Reinhard:* Verhindert Clipping, führt jedoch bei hohen Helligkeiten zu entsättigten, grau wirkenden Spitzenlichtern.  
  *   
  * *Filmic:* Erzeugt hohen Kontrast, neigt aber zum Zudrücken dunkler Schattendetails.  
  *   
  * *AgX / ACES (Empfehlung):* State-of-the-Art im modernen Rendering. Verarbeitet extreme Helligkeitsstufen fotometrisch korrekt, sodass intensive Flasher ihre Farbsättigung beibehalten, anstatt in weißes Rauschen überzugehen.  
  *   
* **LUT (Look-Up Table):** Einbindung einer tischspezifischen oder dezenten Global-LUT (.png). Tisch-LUTs modulieren die Farbtemperatur: Für Tische der 70er/80er-Jahre wird ein wärmerer Kelvin-Wert (Simulation von Glühfadenlampen mit leichtem Gelb-/Orangestich) gewählt, für moderne Stern-Spike-Tische eine kühle, kontrastreiche LED-Graduierung.  
*   
* **Bloom & Streulicht:** *Bloom Strength* auf maximal 0.08 bis 0.15 reduzieren. Ein zu hoher Bloom-Filter erzeugt einen diffusen Schleier auf der Spielfeldscheibe und zerstört die Tiefenschärfe.  
* 

### **4\. Ambient Occlusion und Geometrietiefe**

* **Screen Space Ambient Occlusion (SSAO):** Aktivierung unter den Video-Optionen. SSAO berechnet die Abschattung in Ritzen, unter Plastics, Flipperfingern und um Posts herum.  
*   
* **Scale FX / Anti-Aliasing:** Verwendung von MSAA (mindestens 4×) in Kombination mit FXAA oder SMAA, um das Flimmern dünner Drahtrampen (Wireforms) bei Kopfbewegungen zu eliminieren.  
* 

## **Future Pinball \+ BAM (Better Arcade Mode): Dynamische Next-Gen-Pipeline**

Natives Future Pinball verwendet veraltete Direct3D 9-Routinen mit vorab eingezeichneter (prebaked) Beleuchtung in den Texturen. Moderne Tische (insbesondere Veröffentlichungen von TerryRed mit PinEvent und FizX) setzen zwingend auf die BAM-Erweiterung von Ravarcade, welche die Beleuchtungs-Engine vollständig ersetzt.

### **1\. BAM Per-Pixel Dynamic Lighting vs. Pre-Baked Art**

* Moderne Tische entfernen vorgerenderte Schatten und Lichtflecken vollständig aus den 2D-Texturen des Spielfelds und der Plastics.  
*   
* Die Ausleuchtung erfolgt in Echtzeit auf Pixelebene über dynamische Punktlichtquellen, die der Bewegung von Kugel und Schaltern folgen.  
* 

### **2\. Shadowmaps und BAM Ray Cast Ball Shadows**

* **BAM Shadowmaps:** Werden den primären GI-Glühbirnen und Flashers zugewiesen. Dadurch werfen Rampen, Posts und Aufbauten korrekte 3D-Schatten auf die Spielfläche.  
*   
* **Ray Cast Ball Shadows:** Die Kugel berechnet in Echtzeit physikalisch akkurate Strahlen- und Halbschatten in Abhängigkeit von den aktiven Lichtquellen.  
* 

  * *Hardware-Bedingung:* Diese Funktion ist extrem GPU-intensiv. Der FPLoader und die FuturePinball.exe müssen zwingend mit dem 4-GB-Patch versehen sein, um Out-of-Memory-Abstürze bei komplexen Tischen zu verhindern.  
  * 

### **3\. Normal Maps und Relief-Mapping (Bump Mapping)**

* Klassische flache Texturen auf Zielen (Drop Targets), Bumper-Kappen und den transparenten Plastik-Inserts (Jewel Inserts) wirken im 3D-Raum steril.  
*   
* Durch das Hinzufügen von Normal-/Bump-Maps bricht sich das Licht an den Kanten von Inserts und Plastikabdeckungen mit echter optischer Tiefe, wodurch die Riffelung physischer Flipper-Kunststoffe exakt nachempfunden wird.  
* 

### **4\. BAM Post-Processing und Licht-Menü**

BAM stellt ein In-Game-Menü bereit (aufrufbar über die Taste \~ bzw. Ö oder F12, je nach Tastaturlayout):

* **Lighting Settings:**  
* 

  * *Ambient Light:* Sollte auf einen niedrigen Wert (typisch 10% bis 25%) gesetzt werden, um die Atmosphäre einer abgedunkelten Spielhalle zu simulieren. Zu viel Umgebungslicht lässt Farben ausgewaschen wirken.  
  *   
  * *Diffusion Light:* Kontrolliert die Reichweite und Weichheit des Lichts auf den umgebenden Objekten.  
  *   
* **Post-Processing (Color Correction / Tone Mapping):**  
* 

  * Feine Justierung von Gamma, Kontrast und Sättigung.  
  *   
  * Deaktivierung von FP-eigenem Antialiasing zugunsten von modernen Filtern wie NFAA oder FXAA innerhalb des BAM-Post-Processings, um Treppeneffekte an schrägen Kanten ohne Unschärfe zu beseitigen.  
  * 

## **Konfigurations- und Referenztabelle für maximale optische Immersion**

| Einstellungsbereich | Visual Pinball X (VPX 10.8) | Future Pinball (BAM Engine) |
| :---- | :---- | :---- |
| **Primärer Tone Mapper** | AgX oder ACES (verhindert Ausbrennen von Flashers)  | BAM Internal Post-Processing (Tonemapping aktiv)  |
| **Color Grading / LUT** | Tischnative .png\-LUTs oder dezente Warm-Arcade-LUT | BAM Color Correction (RGB-Gains & Gamma-Kompensation) |
| **Kugelschatten** | Dynamic \+ Ambient Shadows aktiviert | BAM Ray Cast Ball Shadows aktiviert  |
| **Geometrie-Schatten** | Screen Space Ambient Occlusion (SSAO) auf Stufe *High* | BAM Shadowmaps für GI & Flashers aktiviert  |
| **Playfield Roughness** | 0.020 – 0.035 (hoher Glanz mit minimaler Dispersion) | Geregelt über Shader-Parameter und Textur-Specular-Map |
| **Reflektionsstärke** | 0.40 – 0.55 (Kugel spiegelt sich dezent, nicht als Vollbild) | BAM Mirror / Reflection Plane (ausbalanciert via Table Script)  |
| **Anti-Aliasing** | 4× Quality MSAA \+ SMAA/FXAA post-pass | NFAA Post-Processing Filter via BAM  |
| **Umgebungshelligkeit** | Day/Night-Slider im Table Editor auf 15–30 (Nacht-Modus) | Ambient Light im BAM-Menü/Script auf 15%–25%  \[cite: 4\]  |

## **Fallstricke, Fehlerquellen und Performance-Fallen**

1. **Script-Overrides im BAM-System:**  
2. 

   * *Problem:* Manuelle Anpassungen im BAM-In-Game-Menü (Licht, Post-Processing) werden nach dem Neustart des Tisches verworfen.  
   *   
   * *Ursache:* Viele moderne Releases (wie *Sonic Pinball Mania*) erzwingen ihre Lichtparameter fest im Tabellenskript unter TABLE OPTIONS. Jede manuelle Änderung im GUI wird bei der Initialisierung überschrieben.  
   *   
   * *Lösung:* Konfigurationswerte müssen direkt im VP- bzw. FP-Skriptcode editiert werden.  
   *   
3. **Z-Fighting bei transparenten Rampen und Spielfeldscheiben:**  
4. 

   * *Problem:* Flackernde Geometrieartefakte an Rampenkanten oder Übergängen zu Metallleitblechen.  
   *   
   * *Ursache:* Ungenügende Tiefenpuffer-Präzision (Z-Buffer) oder falsch gewählte Schnittflächenabstände (Near Plane). Liegt die Kameraebene zu nah am Objekt, kollidieren benachbarte Polygone.  
   *   
   * *Lösung:* In den Grafikeinstellungen 32-Bit-Depth-Buffer forcieren und den Kamera-Mindestabstand (Near-Clip-Plane) nicht unterhalb von 5 bis 10 cm ansetzen.  
   *   
5. **Mikroruckler und Input-Lag durch Post-Processing-Last:**  
6. 

   * *Problem:* Obwohl die Grafikkarte hohe Frameraten liefert, reagieren die Flipperfinger zäh (Lag) oder die Kugel stottert periodisch.  
   *   
   * *Ursache:* Die Kombination aus 4K-Auflösung, SSAO, Ray Cast Shadows und unbegrenzter Bildwiederholrate erzeugt Frame-Pacing-Inkonsistenzen.  
   *   
   * *Lösung:* V-Sync in VPX auf 1 (Frame Sync 1:1 an die Monitor-Frequenz, z. B. 120 Hz oder 144 Hz) setzen. In Future Pinball SSAO in den BAM-Plugins deaktivieren, da dies extreme Renderzeiten auf der GPU beansprucht.  
   *   
7. **Überstrahlte, weiße Lichtflecken (Specular Blowout):**  
8. 

   * *Problem:* Insert-Lampen oder Flash-Sequenzen verwandeln die Spielfeldgrafik in weiße Flecken ohne Zeichnung.  
   *   
   * *Ursache:* Verwendung von linearem Tone-Mapping in Kombination mit hoher Emission Scale der Licht-Objekte.  
   *   
   * *Lösung:* Wechsel auf den *AgX*\-Tone-Mapper in VPX 10.8. Die Eigenschaft Falloff Power der Lichter im Tisch-Editor auf einen quadratischen Exponenten (2.0) justieren, um den physikalischen Lichtabfall im Raum exakt abzubilden.  
   * 

## **Einbindung in Fried's Retrogaming Kit**

Um diese visuellen Profile im Ökosystem von *Fried's Retrogaming Kit* konsistent bereitzustellen, müssen die Einstellungen auf Betriebssystem- und Dateiebene modularisiert werden:

* **VPX Registry Injection:** Die globalen Video-, Tone-Mapping- und Antialiasing-Parameter von VPX liegen im Windows-Registrierungspfad HKEY\_CURRENT\_USER\\Software\\Visual Pinball\\VP10\\Player. Vor dem Ändern von Auflösungs- oder Shader-Flags muss das Kit über die *Gated Execution Policy* einen atomaren Registry-Schnappschuss erstellen (New-KitBackup), um korrupte Grafikeinstellungen verlustfrei rückgängig machen zu können.  
*   
* **BAM Presets:** Die Profildateien von BAM (BAM\\Settings\\\*.cfg bzw. XML-Templates) müssen vom Kit überwacht werden. Beim automatisierten Retargeting zwischen verschiedenen Cabinet-Monitoren (Playfield-Drehung, Multi-Display-Offset) dürfen die tischspezifischen Beleuchtungssektionen nicht durch generische Standardprofile überschrieben werden.

