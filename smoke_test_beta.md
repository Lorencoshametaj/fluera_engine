# 🧪 Smoke Test Pre-Beta — Fluera

Checklist manuale da eseguire su device reale (Android + iOS) prima del release beta.
`flutter analyze` è clean: questo documento cattura ciò che solo l'interazione umana può verificare.

**Target device:** 1× Android recente (pixel/samsung), 1× iOS (iPhone/iPad). Test `textScaleFactor = 1.0` e `2.0` su almeno un device.

---

## 🔑 Golden paths (bloccanti beta)

### 1. First-run flow
- [v] Splash compare ≤ 400ms, no glow/scale/pop animation
- [v] Consent screen GDPR: "Accetta tutto" e "Continua con queste scelte" leggibili e funzionanti
- [v] Gallery empty state invitante (non vuoto silenzioso)
- [v] Tap "Nuovo canvas" → canvas apre < 1s warm start
- [v] Primo tratto funziona (Android + iOS)
- [v] **Android: live stroke allineato** (regressione Y-offset risolta nel sprint)

### 2. Auth flow (login slice migrato completamente)
- [v] Email+password signup: 4 password check visibili (length, case, number, special)
- [v] Strength indicator: labels "Debole/Discreta/Buona/Forte" appaiono correttamente
- [v] Errori validator: "Email richiesta", "Formato email non valido", "Minimo 6 caratteri", "Le password non corrispondono"
- [v] Forgot password: "Reset Password" header, email sent "Controlla la tua inbox" con email placeholder
- [v] Verify email: header + messaggio + "Reinvia tra Xs" con countdown
- [v] "Ho già verificato — Accedi" button torna al login
- [v] Google sign-in: CTA "Continua con Google" + loading state
- [v] Apple sign-in (solo iOS): CTA "Continua con Apple"
- [v] Conflict dialog (anon → account esistente): labels canvas count + token AI usati, CTA "Accedi e scarta" / "Usa un'altra email"
- [v] Reauth modal (sessione scaduta): password field, CTA "Continua come ospite" / "Accedi"
- [v] Restore banner (24h window): "N canvas ospite in attesa", "Ripristina entro Xh", CTA Scarta/Ripristina
- [v] **EN locale**: switch device language to English, verify tutto si traduce (no fallback a IT)

### 3. Canvas core
- [ ] Scrittura con penna + dito: live stroke fluido
- [ ] Reduced motion OS abilitato → animazioni sparite/istantanee (splash, action flash)
- [ ] Undo/redo: toast bottom-center sobrio "Annullato"/"Ripristinato" (NO HUD glow centrale)
- [ ] Selezione lasso: niente connector JARVIS, niente UPPERCASE monospace labels
- [ ] Smart ink **NON** si apre tappando sullo stroke (opt-in disattivato di default)
- [ ] Shape recognition **NON** si attiva automaticamente (opt-in OFF)
- [ ] Bookmark: rename dialog "Rinomina bookmark" + delete conferma con label canvas

### 4. Exam/Study
- [ ] Apri exam overlay: header "Esame" (non "ATLAS EXAM"), no streak counter
- [ ] Topic selector: "Seleziona gli argomenti (max 10)"
- [ ] Risposta + confidence: slider 1-5 numerico (no emoji 😟😎)
- [ ] Post-esame: "Risultati" header, summary "Hai affrontato N sfide — M consolidate", calibration card
- [ ] Error replay button "🔄 Rafforza N concetti — ogni ripasso è crescita"
- [ ] Exit dialog "Uscire dall'esame?" con "Hai già risposto a N domande" + "Continua"/"Esci"

### 5. Collaboration (se V1FeatureGate.collaboration ON)
- [ ] P2P mode sheet: card "Richiamo a tempo" con icona timer teal (NON "Duello 7c" con controller rosso)

### 6. Paywall/quota
- [ ] Paywall feature comparison: tutte e 10 le righe label visibili (Canvas+penna, PDF import, etc.)
- [ ] Upgrade CTA "Fatto" post-acquisto
- [ ] Quota pill: normale (green/amber/red + icon auto_awesome)
- [ ] **Quota pill offline**: compare pill grigio con icona cloud_off + "—" e tooltip "Quota non disponibile"
- [ ] AI quota exceeded sheet: CTA "Chiudi" funziona

### 7. Empty/error states (nuovi fix)
- [ ] Chat history panel → disconnetti rete → tap history → appare "Impossibile caricare la cronologia" + bottone "Riprova"
- [ ] Storage usage screen con zero canvas → compare "I tuoi canvas appariranno qui dopo il primo tratto."
- [ ] PDF reader: apri PDF → text sheet → cerca parola inesistente → "Nessun risultato per \"xxx\"."

### 8. Logout
- [ ] Logout tooltip "Esci dall'account"
- [ ] Dialog "Vuoi uscire?" con body + CTA Annulla/Esci

---

## ♿ Accessibility (WCAG)

- [ ] TalkBack (Android) / VoiceOver (iOS) attivi: canvas carousel, minimap, color picker annunciano ruolo button + label
- [ ] Reduce Motion OS: animazioni rispettate (splash instant, action flash no fade, etc.)
- [ ] Dyslexia font toggle in settings: fontFamily cambia in tutta l'app
- [ ] High contrast toggle: effetto visibile
- [ ] `textScaleFactor = 2.0`: nessun overflow in dialog auth, exam, bookmark rename
- [ ] Touch target ≥ 40dp: tool chips, color swatches (bumped da 30→40 nello sprint)

---

## 🔍 Contrast (verifica visiva dopo Pass 4)

Queste alpha sono state alzate — verificare ancora leggibili su display reale:
- [ ] Chat overlay: empty state "Nessuna conversazione salvata" alpha 0.65
- [ ] Chat date subtitles alpha 0.6
- [ ] Atlas prompt overlay: hint "Chiedi qualcosa…" alpha 0.55
- [ ] Handwriting scratchpad placeholder "Scrivi qui la tua risposta a mano..." alpha 0.55
- [ ] Exam "Seleziona gli argomenti" label alpha 0.7

---

## 🚨 Known issues / Out-of-scope per beta

- ⏸️ F12 Toolbar contestuale (redesign L effort — post-beta)
- ⏸️ F13 Exam in focus mode (architettura — post-beta)
- ⏸️ B1 residui: ~50 stringhe settings panel + service error messages
- ⏸️ A5 fontSize migration → Theme.textTheme (design purity, non a11y-blocker)
- ⏸️ LaTeX editor (`V1FeatureGate.latexRecognition = false` — gated off)
- ⏸️ Excel tab (`V1FeatureGate.tabular = false` — gated off)
- ⏸️ Design tab (`V1FeatureGate.designTools = false` — gated off)

---

## 📋 Go/No-Go criteria

**GO se:**
- Tutti i bloccanti golden path (1-4) passano su almeno 1 Android + 1 iOS
- Contrast + textScaleFactor 2.0 senza overflow distruttivo
- Zero crash su auth flow completo (3 provider: email/google/apple)

**NO-GO se:**
- Live stroke regression Android torna
- EN locale rompe layout auth (troppe stringhe più lunghe = overflow)
- Paywall purchase flow silenzioso (no feedback user)
- Quota pill non reagisce a offline

---

**Ultimo aggiornamento:** 2026-04-21 (post Pass 5 B1 sweep + empty/error fixes)
