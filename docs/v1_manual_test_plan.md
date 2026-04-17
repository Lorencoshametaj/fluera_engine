# Fluera v1.0 — Test Plan Manuale Completo

> **Obiettivo:** Validare che l'esperienza utente v1 funzioni end-to-end su tutte le piattaforme target prima della beta chiusa.
>
> **Prerequisito:** `flutter test` → 5764/5764 pass, `flutter analyze` → 0 errors.
>
> **Notazione:** ⬜ = da fare, ✅ = pass, ❌ = fail (aprire issue), ⚠️ = pass con riserva

---

## Legenda Priorità

| Priorità | Significato | Blocca il lancio? |
|---|---|---|
| 🔴 P0 | Core flow — senza questo non si lancia | Sì |
| 🟡 P1 | Importante — degrada l'esperienza | Se ripetibile, sì |
| 🟢 P2 | Nice-to-have — cosmetico | No |

---

## A. Canvas e Scrittura (Passo 1)

### A1. Pen Tool — Scrittura Base

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| A1.1 | **Tratto base** | Scrivi una frase con Everyday Pen | Tratto fluido, senza scatti, ink-to-pixel ≤10ms | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.2 | **Pressure sensitivity** | Premi forte → premi leggero | Tratto si allarga/stringe | 🔴 | ⬜ | ⬜ | N/A | ⬜ |
| A1.3 | **Palm rejection** | Scrivi con mano appoggiata | Nessun segno dal palmo | 🔴 | ⬜ | ⬜ | N/A | ⬜ |
| A1.4 | **Fine Pen** | Seleziona Fine Pen, scrivi | Tratto più sottile, thinning visibile | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.5 | **Soft Pencil** | Seleziona Pencil, scrivi | Opacità variabile, texture matita | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.6 | **Calligraphy Nib** | Seleziona Calligraphy, scrivi curve | Angolo 45° visibile, variazione nib | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.7 | **Technical Pen** | Seleziona Technical, tira linee | Linee dritte con angle snap | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.8 | **Highlighter** | Seleziona Highlighter, evidenzia testo | Overlay semi-trasparente senza coprire | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.9 | **Solo 6 pennelli in strip** | Guarda la brush strip | Solo: Everyday Pen, Fine Pen, Thick Marker, Soft Pencil, Calligraphy, Technical, Highlighter. Niente watercolor/charcoal/etc. | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.10 | **Cambio colore** | Tap colore → scegli rosso → scrivi | Tratto in rosso | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| A1.11 | **Cambio spessore** | Slider spessore → max → scrivi | Tratto molto spesso | 🟢 | ⬜ | ⬜ | ⬜ | ⬜ |

### A2. Canvas Navigation

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| A2.1 | **Pan** | Due dita per spostare | Canvas si sposta senza scatti | 🔴 | ✅ | ✅ | ✅ | ✅ |
| A2.2 | **Pinch-to-zoom** | Pizzica per ingrandire/rimpicciolire | Zoom liscio, centro corretto | 🔴 | ✅ | ✅ | ✅ | ✅ |
| A2.3 | **Double-tap zoom** | Doppio tap | Zoom rapido a un livello predefinito | 🟡 | ✅ | ✅ | ✅ | ✅ |
| A2.4 | **Scroll mouse zoom (Web)** | Scroll wheel | Zoom in/out liscio | 🟡 | N/A | N/A | ⬜ | ⬜ |

### A3. Eraser

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| A3.1 | **Gomma stroke** | Scrivi → eraser → tocca il tratto | Tratto cancellato | 🔴 | ✅ | ✅ | ✅ | ✅ |
| A3.2 | **Gomma parziale** | Scrivi → eraser piccolo → cancella metà parola | Solo parte cancellata | 🟡 | ✅ | ✅ | ✅ | ✅ |

### A4. Undo/Redo

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| A4.1 | **Undo** | Scrivi 3 tratti → undo 3 volte | Tutti rimossi nell'ordine inverso | 🔴 | ✅ | ✅ | ✅ | ✅ |
| A4.2 | **Redo** | Undo → Redo | Tratto ripristinato | 🔴 | ✅ | ✅ | ✅ | ✅ |
| A4.3 | **Ctrl+Z / Ctrl+Y (desktop)** | Scorciatoie tastiera | Funzionano | 🟡 | N/A | N/A | ⬜ | ⬜ |

### A5. Layers

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| A5.1 | **Crea layer** | Apri layers → "Nuovo" | Layer aggiunto | 🟡 | ✅ | ✅ | ✅ | ✅ |
| A5.2 | **Nascondi layer** | Toggle visibilità layer | Contenuto sparisce/appare | 🟡 | ✅ | ✅ | ✅ | ✅ |
| A5.3 | **Rinomina layer** | Long press → rinomina | Nome aggiornato | 🟢 | ✅ | ✅ | ✅ | ✅ |

---

## B. PDF Import e Reference Mode

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| B1 | **Importa PDF** | Menu → Importa PDF → scegli file | PDF caricato, pagine visibili | 🔴 | ✅ | ✅ | ✅ | ✅ |
| B2 | **Opacità 85%** | Guarda il PDF importato | Leggermente trasparente (reference-only) | 🟡 | ✅ | ✅ | ✅ | ✅ |
| B3 | **Bordo blu 📎** | Guarda il bordo del PDF | Bordo blu visibile che indica "reference" | 🟡 | ✅ | ✅ | ✅ | ✅ |
| B4 | **Non annotabile** | Prova a scrivere sul PDF importato | Il tratto va SOPRA, non sul layer del PDF | 🟡 | ✅ | ✅ | ✅ | ✅ |
| B5 | **Navigate pagine** | Frecce avanti/indietro | Pagina cambia | 🔴 | ✅ | ✅ | ✅ | ✅ |
| B6 | **PDF Reader completo** | Apri PDF nel reader dedicato | Bookmarks, ricerca, text selection funzionano | 🟡 | ✅ | ✅ | ✅ | ✅ |
| B7 | **Night mode** | Toggle night mode nel reader | Inversione colori leggibile | 🟢 | ✅ | ✅ | ✅ | ✅ |

---

## C. Registrazione Audio (🎤 "Registra")

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| C1 | **Avvia registrazione** | Tap 🎤 → "Registra" | Indicatore rosso REC attivo | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| C2 | **Scrivi durante registrazione** | Registra + scrivi appunti | Ink anchored to audio timeline | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| C3 | **Stop registrazione** | Tap stop | Registrazione salvata | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| C4 | **Tap-to-seek** | Tap su un nodo scritto durante registrazione | Audio salta alla posizione temporale corretta (±2s) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| C5 | **Playback continuo** | Play dall'inizio | Audio riproduce continuamente | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| C6 | **Permesso microfono** | Prima registrazione assoluta | Dialog permesso OS appare, dopo "Consenti" funziona | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## D. Recall Mode (🧠 "Mettimi alla prova" — Passo 2)

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| D1 | **Attivazione** | Crea ≥5 nodi → Tap 🧠 | Entra in recall mode, canvas svuotato | 🔴 | ✅ | ✅ | ✅ | ✅ |
| D2 | **Label chip** | Guarda il bottone | Dice "Mettimi alla prova", NON "Recall" | 🔴 | ✅ | ✅ | ✅ | ✅ |
| D3 | **Tooltip** | Long press sul chip | Tooltip senza "Passo 2" o gergo tecnico | 🟡 | ✅ | ✅ | ✅ | ✅ |
| D4 | **Ricostruisci** | Scrivi quello che ricordi | Canvas si popola con nodi ricostruiti | 🔴 | ✅ | ✅ | ✅ | ✅ |
| D5 | **Auto-valutazione** | Finisci recall → self-eval popup | Slider/buttons per auto-valutazione 1-5 | 🔴 | ✅ | ✅ | ✅ | ✅ |
| D6 | **Fog of War update** | Dopo recall, nodi ricordati | Nodi ricordati diventano più chiari nel FoW | 🟡 | ✅ | ✅ | ✅ | ✅ |
| D7 | **Gate: illimitato per Free** | Fai 10+ recall consecutivi | Mai bloccato, MAI messaggio upsell | 🔴 | ✅ | ✅ | ✅ | ✅ |
| D8 | **Celebration** | Recall perfetto (8/8+) | "Solido." appare brevemente (≤2s) | 🟡 | ✅ | ✅ | ✅ | ✅ |

---

## E. Socratic AI (🔶 "Interrogami" — Passo 3)

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| E1 | **Attivazione** | Crea appunti → Tap "Interrogami" | IA pone una domanda pertinente al contenuto | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E2 | **Label chip** | Guarda il bottone | Dice "Interrogami", NON "Socratica" | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E3 | **Latenza** | Tempo da tap a prima risposta IA | < 3 secondi | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E4 | **Confidenza (5 dot)** | IA chiede confidenza | 5 dot (1-5) funzionano, haptic progressivo, colore cambia | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E5 | **Hypercorrection** | Rispondi sbagliato con confidenza alta (>80%) | Shock rosso, nodo pulsa, messaggio ipercorrezione | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E6 | **Risposta corretta** | Rispondi corretto | Feedback positivo verde | 🟡 | ✅ | ✅ | ✅ | ✅ |
| E7 | **Gate Free: 3/settimana** | Usa 3 sessioni socratiche | Dopo la 3ª, messaggio: "Hai usato le 3 sessioni..." | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E8 | **Upsell non-modale** | Quando gated dopo la 3ª | Banner dismissabile, NON modale bloccante | 🔴 | ✅ | ✅ | ✅ | ✅ |
| E9 | **Upsell pricing** | Leggi il messaggio | Contiene "€3.33/mese" e "Pro" | 🟡 | ✅ | ✅ | ✅ | ✅ |
| E10 | **Contesto corretto** | IA fa domande | Le domande riguardano gli appunti scritti, non topic random | 🔴 | ✅ | ✅ | ✅ | ✅ |

---

## F. Ghost Map (👻 "Cosa mi manca?" — Passo 4)

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| F1 | **Attivazione** | Crea ≥2 gruppi di appunti → Tap "Cosa mi manca?" | Ghost Map si genera, overlay visibile | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F2 | **Label chip** | Guarda il bottone | Dice "Cosa mi manca?", NON "Ghost Map" | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F3 | **Generazione** | Tempo da tap a overlay | < 5 secondi | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F4 | **Nodi mancanti** | Guarda l'overlay | Mostra concetti mancanti rispetto al topic | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F5 | **Tap per tentare** | Tap su nodo ghost | Popup per tentare la risposta (testo o mano) | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F6 | **Rivela risposta** | Tap "Rivela" dopo attempt | Mostra la risposta corretta dopo countdown | 🟡 | ✅ | ✅ | ✅ | ✅ |
| F7 | **Confronta** | After reveal | Confronto side-by-side (tentativo vs corretto) | 🟡 | ✅ | ✅ | ✅ | ✅ |
| F8 | **Progresso** | Esplora più nodi | Barra progresso "X/Y lacune esplorate" | 🟡 | ✅ | ✅ | ✅ | ✅ |
| F9 | **Chiudi Ghost Map** | Tap "Chiudi" | Overlay rimosso, canvas normale | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F10 | **Gate Free: 1/settimana** | Usa 1 Ghost Map → riprova | Dopo la 1ª, messaggio upsell | 🔴 | ✅ | ✅ | ✅ | ✅ |
| F11 | **Prerequisito minimo** | Prova con <2 gruppi nodi | Messaggio "Scrivi almeno 2 gruppi" | 🟡 | ✅ | ✅ | ✅ | ✅ |
| F12 | **Info screen** | Tap info/? | Schermata Material 3 con spiegazione pedagogica | 🟢 | ✅ | ✅ | ✅ | ✅ |

---

## G. Fog of War + FSRS (⚔️ "Sfida" — Passo 6/8)

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| G1 | **Attivazione FoW** | Nodi schedulati → Tap "Sfida" | Fog of War overlay: nodi sfocati | 🔴 | ✅ | ✅ | ✅ | ✅ |
| G2 | **Label chip** | Guarda il bottone | Dice "Sfida", NON "Fog of War" | 🔴 | ✅ | ✅ | ✅ | ✅ |
| G3 | **Densità nebbia 3 livelli** | Seleziona livello nel picker (Leggera/Media/Totale) | Leggera: trasparenza 30-50%, contenuto intravisto. Media: trasparenza 60-80%, contorni visibili. Totale: completamente coperto | 🔴 | ✅ | ✅ | ✅ | ✅ |
| G4 | **Tap per rivelare** | Tap su nodo sfocato | Nodo si desfoca con animazione | 🟡 | ✅ | ✅ | ✅ | ✅ |
| G5 | **Self-eval post-FoW** | Rivela tutti → finisci | Auto-valutazione come in Recall | 🟡 | ✅ | ✅ | ✅ | ✅ |
| G6 | **Gate: illimitato Free** | Fai 5+ sessioni FoW | Mai bloccato (strategia §3 lo dice) | 🔴 | ✅ | ✅ | ✅ | ✅ |
| G7 | **FSRS scheduling update** | Dopo eval → chiudi → riapri domani (o simula) | Nodi rischedulati con intervalli FSRS | 🟡 | ✅ | ✅ | ✅ | ✅ |

---

## H. SRS Notifications

### H-A. Permesso e prima schedulazione

| # | Test | Steps | Expected | Priorità | iPad | Android |
|---|---|---|---|---|---|---|
| H1 | **Permesso al momento giusto** | Fresh install → scrivi appunti → completa prima verify card (risposta valutata) | Dialog permesso notifiche OS appare DOPO il primo risultato SRS, non prima | 🔴 | ✅ | ✅ |
| H2 | **Permesso concesso** | Concedi il permesso nel dialog H1 | Nessun errore, scheduling procede silenziosamente (check debugPrint: "Scheduled N SR review notifications") | 🔴 | ✅ | ✅ |
| H3 | **Permesso negato** | Nega il permesso nel dialog H1 | Nessun crash, nessun dialog ripetuto, scheduling saltato silenziosamente | 🔴 | ✅ | ✅ |
| H4 | **Permesso gia' concesso** | Ripeti H1 dopo aver gia' concesso | Nessun dialog, scheduling procede | 🟡 | ✅ | ✅ |
| H5 | **Android < 13** | Device con Android 12 o inferiore | Nessun dialog (non richiesto), scheduling funziona | 🟡 | N/A | ✅ |

### H-B. Schedulazione e consegna

| # | Test | Steps | Expected | Priorità | iPad | Android |
|---|---|---|---|---|---|---|
| H6 | **Notifica schedulata** | Completa una verify card → aspetta che nextReview scada (o modifica orologio device +2h) | Notifica appare con titolo "📅 Review: {concetto}", body, e 2 action buttons ("Review now" + "In 1h") | 🔴 | ✅ | ✅ |
| H7 | **Puntualita'** | Schedule notifica con nextReview = ora + 2 min | Arriva entro ±30s dal tempo schedulato | 🟡 | ✅ | ✅ |
| H8 | **Raggruppamento** | Avere 3+ concetti due → aspetta che scadano | Le notifiche sono raggruppate sotto un'unica summary "N concepts to review" | 🟡 | ✅ | ✅ |
| H9 | **Cap notifiche** | Avere 50+ concetti schedulati | Max 40 notifiche schedu late (controlla con debugPrint "capped from"), nessun crash | 🟡 | ✅ | ✅ |
| H10 | **Badge iOS** | Concetti overdue presenti | App icon mostra badge numerico con conteggio overdue | 🟡 | ✅ | N/A |
| H11 | **Canale Android** | Notifica arriva su Android | Appare nel canale "Studio & Ripasso" (fluera_study) nelle impostazioni notifiche Android | 🟡 | N/A | ✅ |

### H-C. Interazioni con la notifica

| # | Test | Steps | Expected | Priorità | iPad | Android |
|---|---|---|---|---|---|---|
| H12 | **Tap body (app aperta)** | Notifica arriva con app in foreground → tap | Verify card appare nel canvas con il concetto corretto, haptic feedback | 🔴 | ✅ | ✅ |
| H13 | **Tap body (app background)** | Notifica arriva con app in background → tap | App torna in foreground + verify card appare | 🔴 | ✅ | ✅ |
| H14 | **Tap body (cold start)** | Forza chiusura app → tap notifica dalla lock screen | App si apre → verify card appare col concetto giusto (getInitialNotification) | 🔴 | ✅ | ✅ |
| H15 | **Action: Review now** | Tap bottone "Review now" nella notifica | Stesso comportamento di H12 — verify card appare | 🟡 | ✅ | ✅ |
| H16 | **Action: Snooze 1h** | Tap bottone "In 1h" nella notifica | Notifica sparisce, nuova notifica ri-schedulata a +1h (check debugPrint: "Snoozed X for 1h"), app NON si apre | 🔴 | ✅ | ✅ |
| H17 | **Snooze effettivo** | Dopo H16, aspetta 1h (o avanza orologio) | Nuova notifica arriva al tempo snoozato | 🟡 | ✅ | ✅ |
| H18 | **Data payload** | Tap qualsiasi notifica → controlla verify card | Il concetto nel card corrisponde al concetto della notifica (non null, non sbagliato) | 🔴 | ✅ | ✅ |

### H-D. Resilienza

| # | Test | Steps | Expected | Priorità | iPad | Android |
|---|---|---|---|---|---|---|
| H19 | **Reboot Android** | Schedula notifiche → riavvia device Android → aspetta orario | Notifiche arrivano comunque (reboot recovery via BOOT_COMPLETED) | 🔴 | N/A | ✅ |
| H20 | **Reboot: actions presenti** | Dopo H19, controlla la notifica ricevuta | Ha i 2 bottoni "Review now" e "In 1h" (non solo titolo/body) | 🔴 | N/A | ✅ |
| H21 | **Reboot: data presenti** | Dopo H19, tap sulla notifica | Verify card mostra il concetto corretto (non null) | 🔴 | N/A | ✅ |
| H22 | **cancelGroup** | Schedula notifiche → completa una nuova verify → salva SR | Vecchie notifiche cancellate, nuove rischedulate (check getPendingNotifications) | 🟡 | ✅ | ✅ |
| H23 | **Doze mode Android** | Device in idle per 30+ min → notifica scade | Notifica arriva (AlarmManager.setExactAndAllowWhileIdle bypassa Doze) | 🟡 | N/A | ✅ |
| H24 | **Exact alarm non concesso (Android 14+)** | Revoca "Alarms & reminders" in Settings → Apps → Fluera | Notifica arriva comunque (fallback a setAndAllowWhileIdle, ±10 min) | 🟡 | N/A | ✅ |

---

## I. Onboarding

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| I1 | **Primo avvio** | Installa fresh → apri | Seed node "Come funziona la memoria?" (IT) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| I2 | **Write prompt** | Guarda il prompt | Testo invitante tipo "Scrivi qui..." | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| I3 | **Prompt scompare** | Prima stroke | Il prompt "Scrivi qui" scompare | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| I4 | **Seed cancellabile** | Long press → elimina il seed node | Seed sparisce, isComplete = true | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| I5 | **Utente di ritorno** | Chiudi e riapri app | Niente seed, niente prompt | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| I6 | **Contenuto EN** | Locale inglese | "How does memory work?" | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| I7 | **Flusso 3 minuti** | Segui tutto il flusso dal seed alla prima recall | Viene guidato naturalmente entro 3 min | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## J. Tier Gating e Upsell

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| J1 | **Canvas Free illimitato** | Crea 50+ nodi | Mai bloccato | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J2 | **Recall Free illimitato** | Fai 10+ recall | Mai bloccato | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J3 | **FoW Free illimitato** | Fai 5+ sessioni FoW | Mai bloccato | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J4 | **Socratic: 3/week Free** | 4ª sessione socratica | Blocked + messaggio italiano con €3.33 | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J5 | **Ghost Map: 1/week Free** | 2ª Ghost Map | Blocked + messaggio | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J6 | **Banner non modale** | Quando gated | Banner in basso dismissabile, NON dialog | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J7 | **Upgrade to Pro** | Acquista Pro (sandbox) | Tutti i limiti rimossi | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| J8 | **Weekly reset** | Aspetta lunedì (o simula) → riprova | Counter azzerato, feature sbloccate | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| J9 | **Persistenza contatori** | Usa 2 Socratic → chiudi app → riapri | remainingThisWeek = 1 (non resetta) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## K. Deferred Features — Devono essere INVISIBILI

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| K1 | **Time Travel** | Cerca in tutta la UI | Nessun bottone, nessun menu, nessun accesso | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K2 | **Collaboration/P2P** | Cerca FAB collaboration, invite | Zero trace | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K3 | **Cross-Zone Bridges** | Cerca nel toolbar/menu | Nessun bottone bridges | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K4 | **Exam Session** | Cerca "Esame" | Nessun accesso | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K5 | **Marketplace** | Cerca "Marketplace" o "Template" | Nessun bottone raggiungibile | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K6 | **Passeggiata** | Cerca "Passeggiata" o walking mode | Non accessibile | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K7 | **LaTeX** | Apri radial menu, sezione Insert | Nessun LaTeX | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K8 | **Multiview** | Cerca split multi-canvas | Non accessibile | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K9 | **Tabular** | Cerca tabella/spreadsheet | Non accessibile | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| K10 | **Brush avanzati (radial)** | Apri radial menu → Brush ring | No watercolor, charcoal, oil, spray, neon, ink wash, airbrush | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## L. Degraded Mode (IA Offline)

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| L1 | **Socratic offline** | Disattiva rete → Tap "Interrogami" | Fallback silenzioso: genera domande locali generiche (no messaggio errore, lo studente continua senza accorgersi) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L2 | **Ghost Map offline** | Disattiva rete → "Cosa mi manca?" | 2 tentativi automatici (2s tra retry), poi error overlay con messaggio localizzato (`ghostMap_errorGeneric`). No crash | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L3 | **Recall offline** | Disattiva rete → "Mettimi alla prova" | FUNZIONA (non dipende da IA) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L4 | **FoW offline** | Disattiva rete → "Sfida" | FUNZIONA (non dipende da IA) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L5 | **Canvas offline** | Disattiva rete → scrivi liberamente | Canvas DEVE funzionare sempre | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L6 | **Riconnessione base** | Riattiva rete → ri-tap Socratic | IA risponde normalmente, indicatore connessione torna verde | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| L7 | **Indicatore connessione** | Disattiva rete → osserva toolbar | Pallino connessione passa da verde a grigio/rosso; riattiva rete → torna verde | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L8 | **Rete instabile** | Simula rete lenta/intermittente (throttle) | Badge offline visibile, Socratic degrada a domande locali, Ghost Map mostra retry hint | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| L9 | **Ghost Map interrotto** | Avvia Ghost Map → disattiva rete durante generazione | Timeout 15s, error overlay, canvas integro, nessuna corruzione | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| L10 | **Offline queue collab** | In sessione collaborativa: disattiva rete → scrivi 5 tratti → riattiva rete | Tratti sincronizzati automaticamente agli altri utenti (offline queue replay) | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## M. UI Labels e Vibe

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| M1 | **Chip Recall** | Guarda toolbar | "Mettimi alla prova" (IT) / "Test me" (EN) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| M2 | **Chip Socratic** | Guarda toolbar | "Interrogami" (IT) / "Quiz me" (EN) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| M3 | **Chip Ghost Map** | Guarda toolbar | "Cosa mi manca?" (IT) / "What am I missing?" (EN) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| M4 | **Chip FoW** | Guarda toolbar | "Sfida" (IT) / "Challenge" (EN) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| M5 | **Chip Recording** | Guarda toolbar | "Registra" (IT) / "Record" (EN) | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| M6 | **Nessun "Passo N"** | Controlla TUTTI i tooltip | Zero occorrenze di "Passo 2", "Passo 3", etc. | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| M7 | **Nessun gergo** | Controlla TUTTI i tooltip + label | Zero "Recall Mode", "Socratica", "Fog of War", "Ghost Map" visibili allo studente | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| M8 | **L10n switch** | Cambia lingua device IT↔EN | Tutte le label cambiano coerentemente | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## N. Persistence e Storage

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| N1 | **Salvataggio automatico** | Scrivi 10 nodi → chiudi app (force quit) → riapri | Canvas ripristinato con tutti i nodi | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| N2 | **Multiple canvas** | Crea 3 canvas diversi | Tutti elencati, nessuna perdita dati | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| N3 | **Rename nota** | Rinomina un canvas | Nome aggiornato ovunque | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| N4 | **Tier gate persistence** | Verifica Free tier → Usa 2 Socratic → force quit → riapri | Counter a 2, remaining = 1 (limite 3/settimana) | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| N5 | **Delta save (layer invariati)** | Crea 5 layer con contenuto → modifica solo layer 3 → force quit → riapri | Tutti e 5 i layer intatti, solo layer 3 con la modifica | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| N6 | **Save durante stroke attivo** | Inizia uno stroke lungo e lento → attendi >2s senza rilasciare → rilascia | Nessun crash, save avviene dopo il completamento dello stroke | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| N7 | **Tier gate reset giornaliero** | Usa 1 Deep Review (limite 1/giorno) → cambia data di sistema al giorno dopo → riapri app | Counter Deep Review azzerato, feature disponibile | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| N8 | **Folder organizzazione canvas** | Crea cartella → sposta 2 canvas dentro → naviga nella cartella | Canvas visibili nella cartella, non più nella root | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| N9 | **Anteprima canvas al riavvio** | Disegna contenuto riconoscibile → chiudi app → riapri gallery | Thumbnail/anteprima del canvas visibile e corretta | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## O. Export

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| O1 | **Export PNG (Free)** | Menu → Export → PNG | File PNG salvato, qualità buona | 🔴 | ⬜ | ⬜ | ⬜ | ⬜ |
| O2 | **Export PDF (Pro only)** | In Free: prova export PDF | Messaggio "Solo con Pro" | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## P. Sound Design Pedagogico

| # | Test | Steps | Expected | Priorità | iPad | Android | Web | Win |
|---|---|---|---|---|---|---|---|---|
| P1 | **Suono attivazione recall** | Entra in recall mode | Suono discreto (se implementato) | 🟢 | ⬜ | ⬜ | ⬜ | ⬜ |
| P2 | **Silenzio durante scrittura** | Scrivi mentre suono è attivo | Suono si interrompe, no distrazione | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |
| P3 | **Toggle audio** | Settings → mute suoni | Tutti i suoni silenziati | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ |

---

## Q. Stress Test

| # | Test | Come eseguire | Criterio Pass | Priorità |
|---|---|---|---|---|
| Q1 | **200+ nodi** | Crea 200 nodi manualmente, pan e zoom | ≥50 FPS, no jank | 🔴 |
| Q2 | **30 min sessione continua** | Scrivi per 30 minuti senza fermarti | Nessun crash, RAM < 500MB | 🔴 |
| Q3 | **Cold start** | Kill app → riaprila | Canvas pronto < 3 secondi | 🟡 |
| Q4 | **FSRS 30 giorni** | Script che simula scheduling | Intervalli corretti, no crash | 🟡 |
| Q5 | **PDF pesante** | Importa PDF da 50+ pagine | Carica senza crash | 🟡 |
| Q6 | **Rapida successione** | Apri/chiudi Socratic, Ghost, Recall velocemente | Nessun crash o stato inconsistente | 🔴 |

---

## R. Edge Cases

| # | Test | Steps | Expected | Priorità |
|---|---|---|---|---|
| R1 | **Canvas vuoto + Recall** | Tap "Mettimi alla prova" con 0 nodi | Messaggio "Scrivi qualcosa prima" o chip disabilitato | 🔴 |
| R2 | **Canvas vuoto + Ghost** | Tap "Cosa mi manca?" con 0 nodi | Messaggio prerequisito | 🔴 |
| R3 | **Canvas 1 nodo + Ghost** | Solo 1 gruppo di nodi | Messaggio "Scrivi almeno 2 gruppi" | 🟡 |
| R4 | **Interruzione rete mid-Socratic** | Rete si stacca durante dialogo Socratico | Fallback: messaggio errore, no crash, no stato corrotto | 🔴 |
| R5 | **Rotazione device** | Ruota iPad da portrait a landscape | Canvas si adatta, no perdita dati | 🟡 |
| R6 | **Multitasking iPad** | Slide Over / Split View | App non crasha, canvas visibile | 🟡 |
| R7 | **Background + foreground** | Metti app in background 5min → torna | Canvas intatto, timer SRS corretto | 🔴 |
| R8 | **Low battery** | Batteria < 10% | App non si comporta diversamente, no crash | 🟢 |
| R9 | **Doppio tap rapido su chip** | Tap rapidissimo su "Interrogami" | Una sola sessione aperta, no race condition | 🟡 |
| R10 | **Kill durante Ghost Map** | Force kill durante generazione Ghost | Al riavvio, canvas integro, nessuna corruzione | 🔴 |

---

## Riepilogo Conteggi

| Sezione | Test totali |
|---|---|
| A. Canvas e Scrittura | 18 |
| B. PDF Import | 7 |
| C. Audio | 6 |
| D. Recall Mode | 8 |
| E. Socratic AI | 10 |
| F. Ghost Map | 12 |
| G. Fog of War + FSRS | 7 |
| H. SRS Notifications | 24 |
| I. Onboarding | 7 |
| J. Tier Gating | 9 |
| K. Deferred Features | 10 |
| L. Degraded Mode | 10 |
| M. UI Labels | 8 |
| N. Persistence | 9 |
| O. Export | 2 |
| P. Sound Design | 3 |
| Q. Stress Test | 6 |
| R. Edge Cases | 10 |
| **TOTALE** | **157** |

---

## Procedura

1. **Build release** per ogni piattaforma target
2. **Esegui in ordine:** P0 prima, poi P1, poi P2
3. **Registra ogni fallimento** con:
   - Screenshot/video
   - Device + OS version
   - Steps to reproduce
   - Gravità (Blocker / Major / Minor)
4. **Greenlight rule:** 0 Blocker + 0 Major su piattaforme 🔴 → pronto per la beta
