#!/usr/bin/env python3
"""Fast batch translation - uses simple str.replace on comment lines only."""
import os, re

BASE = os.path.dirname(os.path.abspath(__file__))

# Italian -> English translations (only for content inside comments)
T = {
    # ─── synchronized_recording.dart ───
    "Quando l'utente ha iniziato a disegnare questo tratto": "When the user started drawing this stroke",
    "Quando l'utente ha completato questo tratto": "When the user completed this stroke",
    "Indice della pagina PDF su cui was disegnato il tratto": "Index of the PDF page on which the stroke was drawn",
    "Returns: number of punti da mostrare (0 if the tratto is not ancora iniziato)": "Returns: number of points to show (0 if the stroke has not started yet)",
    "If il playback non ha ancora raggiunto l'inizio of the stroke": "If playback has not yet reached the start of the stroke",
    "Numero totale di tratti nella registrazione": "Total number of strokes in the recording",
    "[strokeStartTime] - timestamp di inizio of the stroke (DateTime.now() quando l'utente ha iniziato)": "[strokeStartTime] - start timestamp of the stroke (DateTime.now() when the user started)",
    "[strokeEndTime] - timestamp di fine of the stroke (DateTime.now() quando l'utente ha finito)": "[strokeEndTime] - end timestamp of the stroke (DateTime.now() when the user finished)",
    "If il playback ha superato la fine of the stroke, mostra tutto": "If playback has passed the end of the stroke, show everything",
    # ─── time_travel_compressor.dart ───
    "Le tre tecniche sono **composte in pipeline**: prima si quantizza,": "The three techniques are **composed in a pipeline**: first we quantize,",
    "Only gli stroke beneficiano delle ottimizzazioni avanzate.": "Only strokes benefit from advanced optimizations.",
    "For altri tipi (shape, text, image), i dati are already compatti.": "For other types (shape, text, image), the data is already compact.",
    "Only gli stroke hanno points[] che beneficiano della compressione": "Only strokes have points[] that benefit from compression",
    "because pressione e tilt sono sempre": "because pressure and tilt are always",
    # ─── time_travel_recorder.dart ───
    "gli eventi** — li accumula per tutta la durata della sessione e li": "events** — it accumulates them for the entire session duration and",
    "Numero totale di eventi registrati nella sessione": "Total number of events recorded in the session",
    "Avvia la registrazione (chiamato dopo check Pro subscription)": "Start recording (called after Pro subscription check)",
    "Registra un evento — chiamato dal LayerController dopo ogni modifica": "Record an event — called by LayerController after each modification",
    "Log ogni 100 eventi per debug (non ad ogni evento)": "Log every 100 events for debug (not every event)",
    "Scrive gli eventi della sessione to disk in formato JSONL compresso": "Writes session events to disk in compressed JSONL format",
    "Manager disco (null if not ancora attivato)": "Disk manager (null if not yet activated)",
    # ─── synchronized_playback_overlay.dart ───
    "mentre l'audio is being played. I tratti si \"disegnano\" progressivamente": "while the audio is being played. The strokes \"draw\" progressively",
    "Calculate if the punto di disegno corrente is visible nella viewport": "Calculate if the current drawing point is visible in the viewport",
    "Margine per considerare \"visibile\" (un po' dentro lo schermo)": "Margin to consider \"visible\" (slightly inside the screen)",
    "Calculate l'angolo della an arrow verso il punto di disegno": "Calculate the angle of an arrow towards the drawing point",
    "Calculate la distanza dal centro della viewport al disegno": "Calculate the distance from the center of the viewport to the drawing",
    "Use IgnorePointer per permettere tocchi al canvas sotto": "Use IgnorePointer to allow touches on the canvas below",
    "Calculate position della an arrow sul bordo dello schermo": "Calculate position of an arrow on the screen edge",
    "Position della an arrow": "Position of an arrow",
    "GLOW: disegna prima un contorno luminoso": "GLOW: draw a luminous outline first",
    "Draw il tratto vero sopra il glow": "Draw the actual stroke above the glow",
    "Pulsante chiudi (sempre disponibile)": "Close button (always available)",
    # ─── time_travel_timeline_widget.dart ───
    "Time labels sotto la barra": "Time labels below the bar",
    "DATE/TIME LABELS (sotto la barra scrubber)": "DATE/TIME LABELS (below the scrubber bar)",
    # ─── time_travel_lasso_overlay.dart ───
    "Test strokes: centro del bounds dentro il lasso": "Test strokes: center of bounds inside the lasso",
    # ─── canvas_adapter.dart ───
    "Checks if a position canvas is dentro i bounds": "Checks if a canvas position is within bounds",
    "For canvas infinito, ritorna sempre true.": "For infinite canvas, always returns true.",
    "For PDF, verifica che sia dentro la pagina.": "For PDF, verifies that it is within the page.",
    # ─── layer_panel.dart ───
    "Si apre/chiude dal bordo sinistro o destro dello schermo": "Opens/closes from the left or right edge of the screen",
    "Pannello layer (visibile sia quando open che minimized per l'animazione)": "Layer panel (visible both when open and minimized for animation)",
    # ─── image_element.dart ───
    "Strokes e shapes disegnati sopra l'immagine (in editing mode)": "Strokes and shapes drawn on top of the image (in editing mode)",
    # ─── timelapse_export_config.dart ───
    "solo ogni N-esimo frame per mantenere tempi ragionevoli.": "only every Nth frame to maintain reasonable times.",
    "Stima della durata del video in secondi": "Estimated video duration in seconds",
    "Stima della size file in MB": "Estimated file size in MB",
    "Calculate frameSkip to remain sotto maxDuration": "Calculate frameSkip to remain under maxDuration",
    # ─── export_preset.dart ───
    "Get la size in punti (72 DPI) per questo formato": "Get the size in points (72 DPI) for this format",
    "Get l'etichetta leggibile per questo formato": "Get the readable label for this format",
    # ─── saved_export_area.dart ───
    "Supporta anche configurazioni multi-pagina.": "Also supports multi-page configurations.",
    # ─── adaptive_debouncer_service.dart ───
    "Obiettivo: zero lag during drawing, salvataggio veloce dopo": "Goal: zero lag during drawing, fast save afterwards",
    "Debounce base durante disegno attivo (aumentato da 3s a 5s)": "Base debounce during active drawing (increased from 3s to 5s)",
    "Debounce minimo durante disegno intenso (molti strokes/sec)": "Minimum debounce during intense drawing (many strokes/sec)",
    "Debounce massimo durante disegno lento (pochi strokes/sec)": "Maximum debounce during slow drawing (few strokes/sec)",
    "Debounce dopo inactivity (corto per salvare velocemente)": "Debounce after inactivity (short to save quickly)",
    "per rilevare automaticamente quando l'utente sta disegnando.": "to automatically detect when the user is drawing.",
    # ─── _lifecycle ───
    "Flush critico: la sessione corrente is ancora in memoria nel recorder.": "Critical flush: the current session is still in memory in the recorder.",
    "Sincronizza Firebase in background dopo caricamento locale": "Synchronize Firebase in background after local loading",
    "Guarded: NON espande durante caricamento iniziale.": "Guarded: does NOT expand during initial loading.",
    # ─── _image_features.dart ───
    "Verify if a punto is dentro i confini of the image": "Verify if a point is within the image boundaries",
    "Check if the punto is dentro l'immagine": "Check if the point is inside the image",
    "Check if the punto is dentro i bounds locali CENTRATI": "Check if the point is inside the CENTERED local bounds",
    "Check if it is dentro i confini of the image": "Check if it is within the image boundaries",
    "Start disegno sopra l'immagine": "Start drawing on top of the image",
    "Continua disegno sopra l'immagine only if stiamo disegnando": "Continue drawing on top of the image only if we are drawing",
    "Tocco fuori dall'immagine -> esci da mode editing": "Touch outside the image -> exit editing mode",
    "Auto-save dopo modifica immagine": "Auto-save after image modification",
    "Auto-save dopo eliminazione immagine": "Auto-save after image deletion",
    "Auto-save dopo aggiunta immagine": "Auto-save after adding image",
    "Esci da editing mode dopo aver salvato gli strokes": "Exit editing mode after saving strokes",
    "Clear stato": "Clear state",
    "Reset stato": "Reset state",
    # ─── _ui_canvas_layer.dart ───
    "Synchronized Playback Overlay (Recorded — dentro il canvas Stack)": "Synchronized Playback Overlay (Recorded — inside the canvas Stack)",
    # ─── professional_canvas_toolbar.dart ───
    "Quick actions sempre accessibili": "Quick actions always accessible",
    # ─── selection_transform_overlay.dart ───
    "I callbacks vengono chiamati durante il drag per aggiornare": "The callbacks are called during drag to update",
    # ─── nebula_canvas_screen.dart ───
    "Forza repaint dopo mutazione in-place della lista.": "Force repaint after in-place mutation of the list.",
    "Nome/Titolo della nota (caricato o ricevuto)": "Note name/title (loaded or received)",
    "Raw input processor per 120Hz mode (quando applicabile)": "Raw input processor for 120Hz mode (when applicable)",
    "Flag per disabilitare auto-save durante caricamento": "Flag to disable auto-save during loading",
    "FIX ZOOM LAG: Cache delle liste shapes": "FIX ZOOM LAG: Cache of shape lists",
    "Notifier per indicare quando l'utente sta disegnando": "Notifier to indicate when the user is drawing",
    "Auto-scroll durante il drag": "Auto-scroll during drag",
    "L'origine (0,0) of the canvas mappa al centro dello schermo": "The origin (0,0) of the canvas maps to the center of the screen",
    "Save stato canvas": "Save canvas state",
    "AUTO-SAVE dopo redo": "AUTO-SAVE after redo",
    "AUTO-SAVE dopo clear": "AUTO-SAVE after clear",
    "If c'è una selezione, verifica if the tap is dentro la selezione": "If there is a selection, check if the tap is inside the selection",
    "Start drag della selezione": "Start selection drag",
    "If lo stroke is empty, resetta tutto": "If the stroke is empty, reset everything",
    "Save stato for ado": "Save state for undo",
    # ─── pro models ───
    "durante il rendering e la persistenza Firebase.": "during rendering and Firebase persistence.",
    "Engine version che ha prodotto questo stroke.": "Engine version that produced this stroke.",
    "FIX: 2 decimali causavano curve grezze dopo load because": "FIX: 2 decimals caused rough curves after load because",
    # ─── brush_test ───
    "REALISM: Simula pressione realistica per dito dalla velocità": "REALISM: Simulates realistic finger pressure from velocity",
    "Finger: simula pressione dalla velocità": "Finger: simulates pressure from velocity",
    "Previene repaint inutili quando altri widget cambiano": "Prevents unnecessary repaints when other widgets change",
    "Forza repaint quando cambia": "Force repaint when it changes",
    # ─── integration_examples.dart ───
    "ESEMPIO 1: Pulsante nella Home": "EXAMPLE 1: Button in the Home",
    # ─── exports ───
    "Esporta tutti i componenti necessari per usare la schermata di test pennelli": "Exports all components needed to use the brush test screen",
    "Esporta tutti i tool unificati per uso nelle views.": "Exports all unified tools for use in views.",
    # ─── stroke processing ───
    "Rifinisce il tratto dopo che was completato:": "Refines the stroke after it was completed:",
    "Simula pressione variabile anche without stylus:": "Simulates variable pressure even without stylus:",
    "Smoothing ottimizzato delle larghezze": "Optimized width smoothing",
    "Smoothing opacity (stessa logica delle larghezze)": "Opacity smoothing (same logic as widths)",
    # ─── tile_cache / rendering ───
    "Invalidate tutti i tile che contengono un certo stroke": "Invalidate all tiles that contain a certain stroke",
    "Invalidate tutti i tile che intersecano un bounds": "Invalidate all tiles that intersect a bounds",
    "Invalidate tutti i tile (ricostruzione completa)": "Invalidate all tiles (complete reconstruction)",
    "Invalidate tile coinvolti da uno stroke (chiamare dopo add/remove)": "Invalidate tiles involved by a stroke (call after add/remove)",
    "Invalidate tutti i tile (chiamare dopo undo completo o clear)": "Invalidate all tiles (call after complete undo or clear)",
    "Invalidate tutta la tile cache": "Invalidate the entire tile cache",
    "I tile cached sono bitmap GPU-scaled.": "Cached tiles are GPU-scaled bitmaps.",
    "Gets gli strokes NON ancora rasterizzati in un tile": "Gets strokes NOT yet rasterized in a tile",
    "Invece di ri-rasterizzare tutti gli strokes, ritorna solo quelli nuovi.": "Instead of re-rasterizing all strokes, returns only the new ones.",
    "quando deve rasterizzare un tile.": "when it needs to rasterize a tile.",
    # ─── canvas parts ───
    "Painter per disegnare i pattern della carta on the canvas": "Painter to draw paper patterns on the canvas",
    "FRAME BUDGET MANAGER - Mantiene 60 FPS anche con 500k strokes": "FRAME BUDGET MANAGER - Maintains 60 FPS even with 500k strokes",
    "NO repaint: durante pan/zoom — aggiornato solo su widget rebuild": "NO repaint: during pan/zoom — updated only on widget rebuild",
    "Le sessioni sono serializzate in un file indice leggero (`index.json`);": "Sessions are serialized in a lightweight index file (`index.json`);",
    "per tutte le piattaforme e i dispositivi supportati.": "for all supported platforms and devices.",
    "Rappresenta un'immagine posizionata on the canvas con tutte le modifiche": "Represents an image positioned on the canvas with all modifications",
    "Stile della griglia": "Grid style",
    "for performance ottimale (zero widget rebuild durante disegno)": "for optimal performance (zero widget rebuild during drawing)",
    "Positioned at viewport level (fuori da Transform)": "Positioned at viewport level (outside Transform)",
    # ─── gesture / input ───
    "Processa pointer move event (durante stroke)": "Process pointer move event (during stroke)",
    "Punto finale corrente (durante disegno)": "Current end point (during drawing)",
    "anche quando sono registrati come PointerDeviceKind.touch": "even when registered as PointerDeviceKind.touch",
    "Ometti tilt/orientation se sono 0 (default) per risparmiare spazio": "Omit tilt/orientation if they are 0 (default) to save space",
    "If non ci sono coalesced, is una lista con solo 'event'": "If there are no coalesced, it's a list with only 'event'",
    "Ma attenzione: su Android, getCoalescedEvents() restituisce tutti i punti dal frame precedente.": "But beware: on Android, getCoalescedEvents() returns all points from the previous frame.",
    "Invece di convertire ogni punto interpolato con screenToCanvas(),": "Instead of converting each interpolated point with screenToCanvas(),",
    "ma for precision massima iteriamo su tutti i raw points.": "but for maximum precision we iterate over all raw points.",
    "Reset flag multi-touch quando tutti i diti sono sollevati": "Reset multi-touch flag when all fingers are lifted",
    "_currentStrokeStartTime viene resettato dopo": "_currentStrokeStartTime is reset after",
    "to remain visivamente nella stessa position sullo schermo": "to remain visually in the same position on screen",
    # ─── misc ───
    "Timer per pre-caching durante idle": "Timer for pre-caching during idle",
    "Calculates i bounds degli selected elements": "Calculates the bounds of selected elements",
    "Calculates pressione media e speed for a sotto-segmento di punti.": "Calculates average pressure and speed for a sub-segment of points.",
    "Elimina tutti i dati (disco + RAM)": "Delete all data (disk + RAM)",
    "Gets i bounds della selezione corrente": "Gets the bounds of the current selection",
    "Ultimo offset to calculate delta durante drag": "Last offset to calculate delta during drag",
    "Pre-carica tutte le texture (da chiamare all'avvio of the canvas)": "Pre-load all textures (call at canvas startup)",
    "Saves uno stroke (RAM sempre, Disk se attivo)": "Saves a stroke (RAM always, Disk if active)",
    "Connette un ValueNotifier esterno per monitorare lo stato disegno": "Connects an external ValueNotifier to monitor drawing state",
    "Getters per stato corrente": "Getters for current state",
    "Notifier esterno per stato disegno (opzionale, per binding)": "External notifier for drawing state (optional, for binding)",
    "Path dell'asset per ogni type of texture": "Asset path for each texture type",
    "Size di default delle immagini (to calculate bounds)": "Default image size (to calculate bounds)",
    "Cache singleton delle texture caricate": "Singleton cache of loaded textures",
    "[enableDeltaTracking]: Se false, tutti i punti avranno lo stesso timestamp": "[enableDeltaTracking]: If false, all points will have the same timestamp",
    "Sort per priority (alta prima)": "Sort by priority (highest first)",
    "Calculate bounds delle shapes selezionate": "Calculate bounds of selected shapes",
    "L'immagine viene disegnata con:": "The image is drawn with:",
    "Draw la texture su tutta l'area visibile": "Draw the texture over the entire visible area",
    "All i punti sono vicini alla linea, tieni solo start e end": "All points are close to the line, keep only start and end",
    "qui si instrada verso il renderer della versione corretta.": "here it routes to the renderer of the correct version.",
    "Skip warm-up period (frame iniziali sono more lenti)": "Skip warm-up period (initial frames are slower)",
    "3. Add routing in block `engineVersion` sotto": "3. Add routing in block `engineVersion` below",
    "The rect originale is centrato su zero, quindi topLeft = (-width/2, -height/2)": "The original rect is centered on zero, so topLeft = (-width/2, -height/2)",
    "Quindi dobbiamo calcolare il rect finale dopo tutte le trasformazioni": "So we must calculate the final rect after all transformations",
    "Draw tutte the geometric shapes completate (SOLO visibili)": "Draw all completed geometric shapes (ONLY visible ones)",
    "Draw la current shape in preview (sempre visibile if present)": "Draw the current shape in preview (always visible if present)",
    "SizedBox deve coprire il contenuto in tutte le direzioni": "SizedBox must cover the content in all directions",
    "permetti di cambiare idea (utile se viene inizializzato come 'pdf' ma poi si disegna su 'note')": "allow changing one's mind (useful if initialized as 'pdf' but then drawing on 'note')",
    "Cue column (colonna sinistra per parole chiave)": "Cue column (left column for keywords)",
    "Righe sottili nella zona principale (note-taking area)": "Thin lines in the main area (note-taking area)",
    "Righe nella zona summary": "Lines in the summary area",
    "Linea per action/description sotto il frame": "Line for action/description below the frame",
    "Overlay scuro fuori dal crop": "Dark overlay outside the crop",
    "Mantieni dentro i bordi": "Keep within the borders",
    "Puntini ogni 1cm": "Dots every 1cm",
    "Puntini densi ogni 5mm": "Dense dots every 5mm",
    "Nota: usiamo stopwatch interno, questo stream is not affidabile": "Note: we use internal stopwatch, this stream is not reliable",
    "Giorni della settimana": "Days of the week",
    "Log progresso ogni 1000 strokes": "Log progress every 1000 strokes",
    "FIX: WAL sempre non compresso": "FIX: WAL always uncompressed",
    "Barline sinistra (inizio)": "Left barline (start)",
    "gap max dentro un blocco": "max gap within a block",
    "Save in RAM (sempre)": "Save in RAM (always)",
    # ─── Pass 2: remaining phrases ───
    "Save l'immagine nella directory dell'app": "Save the image in the app directory",
    "If sotto limite e sotto max count, non serve eviction": "If under limit and under max count, no eviction needed",
    "Remove fino a essere sotto il 70% del limite": "Remove until under 70% of the limit",
    "Flush sessione corrente to disk (gli eventi sono ancora in-memory)": "Flush current session to disk (events are still in-memory)",
    "Pause playback durante l'export": "Pause playback during export",
    "Auto-save dopo aggiunta testo digitale": "Auto-save after adding digital text",
    "Auto-save dopo modifica testo digitale": "Auto-save after modifying digital text",
    "AUTO-SAVE dopo undo": "AUTO-SAVE after undo",
    "Determina direzione dello scroll": "Determine scroll direction",
    "Auto-save dopo resize testo digitale": "Auto-save after resizing digital text",
    "Auto-save dopo drag testo digitale": "Auto-save after dragging digital text",
    "Ferma l'auto-scroll quando termina il drag": "Stop auto-scroll when drag ends",
    "AUTO-SAVE dopo aggiunta shape": "AUTO-SAVE after adding shape",
    "Seleziona l'immagine ma NON iniziare il drag ancora": "Select the image but do NOT start dragging yet",
    "If c'è una selezione e il punto is dentro la selezione, inizia drag": "If there is a selection and the point is inside the selection, start drag",
    "_imageEditingStrokes contiene SOLO i nuovi strokes durante questa sessione": "_imageEditingStrokes contains ONLY the new strokes during this session",
    "Auto-save dopo editing immagine": "Auto-save after image editing",
    "Handle rotazione (sopra il box)": "Handle rotation (above the box)",
    "Risolve il problema della perdita dei primi punti durante la scrittura": "Solves the problem of losing the first points during writing",
    "Ridotto da 200ms per minimizzare input persi dopo zoom": "Reduced from 200ms to minimize lost input after zoom",
    "Drawing solo con 1 dito (quando pan mode is not attivo E stylus mode permette)": "Drawing only with 1 finger (when pan mode is not active AND stylus mode allows)",
    "Evita ricalcolo O(n) ad every frame durante viewport culling": "Avoids O(n) recalculation at every frame during viewport culling",
    "Performance: da O(n) every frame a O(1) dopo primo calcolo": "Performance: from O(n) every frame to O(1) after first calculation",
    "StrokeDataManager (RAM cache, sempre attivo)": "StrokeDataManager (RAM cache, always active)",
    "Pressione dello stylus (0.0-1.0), default 1.0 per touch": "Stylus pressure (0.0-1.0), default 1.0 for touch",
    "Orientamento dello stylus (radianti)": "Stylus orientation (radians)",
    "If delta tracking is disabled, usa sempre baseTimestamp": "If delta tracking is disabled, always use baseTimestamp",
    "Stiffness della \"molla\" (more alto = more rigido)": "Stiffness of the \"spring\" (higher = more rigid)",
    "Massa virtuale della punta (more alto = more inerzia)": "Virtual tip mass (higher = more inertia)",
    "Position precedente durante resize (per calcolo delta incrementale)": "Previous position during resize (for incremental delta calculation)",
    "indice della guida usata come asse": "index of the guide used as axis",
    "Start il drag degli selected elements": "Start dragging the selected elements",
    "Sposta anche i bounds della selezione (more efficiente che ricalcolare)": "Also move the selection bounds (more efficient than recalculating)",
    "Sposta direttamente gli elementi del delta dello scroll": "Move elements directly by the scroll delta",
    "Seleziona elementi dentro il lasso": "Select elements inside the lasso",
    "Seleziona elementi che si trovano dentro il percorso lasso": "Select elements that are inside the lasso path",
    "Calculates bounds degli selected elements": "Calculates bounds of selected elements",
    "Preview in real-time durante disegno": "Real-time preview during drawing",
    "Painter per preview shape durante disegno": "Painter for shape preview during drawing",
    "il riferimento corretto quando l'utente continua a muovere il dito": "the correct reference when the user continues to move the finger",
    "Position precedente durante resize": "Previous position during resize",
    "Draw shapes (sempre rendering diretto - tipicamente poche)": "Draw shapes (always direct rendering - typically few)",
    "Corpo della an arrow": "Body of an arrow",
    "Size della punta": "Size of the tip",
    "Uso: aggiungere come CustomPaint layer sotto il DrawingPainter.": "Usage: add as CustomPaint layer below DrawingPainter.",
    "Opacity della grana (0.0 = invisibile, 1.0 = piena)": "Grain opacity (0.0 = invisible, 1.0 = full)",
    "Dividiamo per scale so appare sempre della stessa size": "We divide by scale so it always appears the same size",
    "Gli strokes are in coordinate relative all'immagine, quindi beneficiano delle trasformazioni": "Strokes are in coordinates relative to the image, so they benefit from transformations",
    "Se questa immagine is in editing mode, disegna strokes temporanei": "If this image is in editing mode, draw temporary strokes",
    # ─── Pass 3: final phrases ───
    "Ferma l'auto-scroll quando termina il drag": "Stop auto-scroll when drag ends",
    "indice della guida usata come asse": "index of the guide used as axis",
    "Draw gli strokes temporanei (durante l'editing corrente)": "Draw temporary strokes (during current editing)",
    "Se questa immagine is in editing mode, disegna overlay (in coordinate assolute)": "If this image is in editing mode, draw overlay (in absolute coordinates)",
    "In mode image edit da infinite canvas, il canvas is already delle dimensioni of the image": "In image edit mode from infinite canvas, the canvas is already the image size",
    "Cache statica dello sfondo to avoid ridisegno continuo": "Static background cache to avoid continuous redrawing",
    "Avvia pre-caching di tile adiacenti durante idle": "Start pre-caching adjacent tiles during idle",
    "If ci sono ancora task, schedula next frame": "If there are still tasks, schedule next frame",
    "MEMORY PRESSURE HANDLER - Gestisce memoria sotto pressione": "MEMORY PRESSURE HANDLER - Manages memory under pressure",
    "Margine examong thentorno al viewport to avoid pop-in durante pan": "Margin around the viewport to avoid pop-in during pan",
    "QUADTREE: usa QuadTree quando ci sono molti strokes (> threshold)": "QUADTREE: uses QuadTree when there are many strokes (> threshold)",
    "Tempo di vita of points in cache dopo ultimo accesso (ms)": "Lifetime of points in cache after last access (ms)",
    "Invalidate cache for ao stroke (chiamare dopo modifica)": "Invalidate cache for a stroke (call after modification)",
    "If la distanza massima is maggiore della tolleranza, ricorsivamente semplifica": "If the maximum distance is greater than the tolerance, recursively simplify",
    "Draw strokes sopra l'immagine": "Draw strokes on top of the image",
    "The canvas is already centrato, quindi possiamo disegnarli direttamente": "The canvas is already centered, so we can draw them directly",
}

# Sort by length desc for longest-match-first
SORTED_ITEMS = sorted(T.items(), key=lambda x: -len(x[0]))

def is_comment_line(line):
    """Check if a line is a comment line (// or ///)."""
    stripped = line.lstrip()
    return stripped.startswith('//')

def process_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except (UnicodeDecodeError, FileNotFoundError):
        return False
    
    original = content
    lines = content.split('\n')
    new_lines = []
    
    for line in lines:
        if is_comment_line(line):
            for it, en in SORTED_ITEMS:
                if it in line:
                    line = line.replace(it, en)
                    break
        new_lines.append(line)
    
    new_content = '\n'.join(new_lines)
    if new_content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        return True
    return False

def main():
    dirs = [os.path.join(BASE, 'lib'), os.path.join(BASE, 'test')]
    dart_files = []
    for d in dirs:
        for root, _, files in os.walk(d):
            for f in files:
                if f.endswith('.dart'):
                    dart_files.append(os.path.join(root, f))
    dart_files.sort()
    
    print(f"Found {len(dart_files)} Dart files")
    modified = 0
    for fp in dart_files:
        if process_file(fp):
            print(f"  ✓ {os.path.relpath(fp, BASE)}")
            modified += 1
    print(f"\nDone! Modified {modified} files.")

if __name__ == '__main__':
    main()
