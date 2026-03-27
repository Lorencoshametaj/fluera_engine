# 🔔 Native Notifications — Documentazione tecnica

Sistema di notifiche native **zero-dependency** per Android & iOS, implementato interamente dentro `fluera_engine`.

---

## Architettura

```
┌─────────────────────────────────────────────────────────────┐
│  Dart (native_notifications.dart)                           │
│  NativeNotifications.show / schedule / onNotificationTapped │
│                    │                        ▲               │
│           MethodChannel              EventChannel           │
│                    │                        │               │
├────────────────────┼────────────────────────┼───────────────┤
│  Android           ▼                        │               │
│  NotificationPlugin.kt ───► NotificationManagerCompat       │
│                    │                        │               │
│  FlueraNotificationReceiver.kt ─────────────┘               │
│   ├─ ACTION_NOTIFICATION_TAP    (body tap)                  │
│   ├─ ACTION_NOTIFICATION_ACTION (action button)             │
│   ├─ ACTION_DELIVER_SCHEDULED   (AlarmManager fire)         │
│   └─ BOOT_COMPLETED            (reschedule after reboot)   │
│                                                             │
│  Cold-start: SharedPreferences → flush on stream subscribe  │
├─────────────────────────────────────────────────────────────┤
│  iOS                                                        │
│  NotificationPlugin.swift                                   │
│   ├─ UNUserNotificationCenter (show/schedule/cancel)        │
│   ├─ UNUserNotificationCenterDelegate (tap routing)         │
│   └─ UNTextInputNotificationAction (inline reply)           │
│                                                             │
│  Cold-start: UserDefaults → flush on stream subscribe       │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Richiedere i permessi

```dart
final result = await NativeNotifications.requestPermission();
// result: granted | denied | alreadyGranted
```

### 2. Mostrare una notifica

```dart
await NativeNotifications.show(FNotification(
  id: 'welcome',
  title: 'Benvenuto su Fluera! 🎓',
  body: 'Inizia a studiare per raggiungere i tuoi obiettivi.',
  priority: FNotificationPriority.high,
  data: {'screen': 'home'},
));
```

### 3. Schedulare una notifica

```dart
await NativeNotifications.schedule(
  FNotification(id: 'review_123', title: 'Ripasso!', body: 'Hai materiale da ripassare.'),
  DateTime.now().add(Duration(hours: 24)),
);
```

### 4. Notifica ricorrente (es. studio giornaliero alle 18:00)

```dart
await NativeNotifications.scheduleRepeating(
  FNotification(
    id: 'daily_study',
    title: '📚 Tempo di studiare!',
    body: 'Il ripasso quotidiano ti aspetta.',
    groupKey: 'study_reminders',
  ),
  firstDeliveryAt: DateTime(2024, 1, 1, 18, 0),
  interval: FRepeatInterval.daily,
);
```

### 5. Ascoltare i tap

```dart
NativeNotifications.onNotificationTapped.listen((event) {
  print('Tap su: ${event.notificationId}');
  print('Action: ${event.actionId}');     // null = body tap
  print('Reply:  ${event.inputText}');    // testo inline reply
  print('Data:   ${event.data}');         // payload custom
  
  // Navigazione basata sul payload
  if (event.data?['screen'] == 'canvas') {
    navigateTo('/canvas/${event.data!['canvasId']}');
  }
});
```

### 6. Cold start (deep linking)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final initial = await NativeNotifications.getInitialNotification();
  if (initial != null) {
    // L'app è stata aperta da questa notifica
    initialRoute = '/canvas/${initial.data?['canvasId']}';
  }
  
  runApp(MyApp(initialRoute: initialRoute));
}
```

---

## API Completa

### Metodi

| Metodo | Descrizione |
|---|---|
| `requestPermission()` | Richiede i permessi (Android 13+ / iOS) |
| `show(notification)` | Mostra immediatamente |
| `schedule(notification, deliverAt)` | Schedula one-shot con data precisa |
| `scheduleRepeating(notification, firstDeliveryAt, interval)` | Schedula ricorrente (daily/weekly/hourly) |
| `cancel(id)` | Cancella una notifica specifica |
| `cancelAll()` | Cancella tutto |
| `cancelGroup(groupKey)` | Cancella tutte le notifiche di un gruppo |
| `setBadgeCount(count)` | Badge app icon (solo iOS) |
| `clearBadge()` | Azzera badge |
| `getDeliveredNotifications()` | Lista notifiche visibili nel Centro Notifiche |
| `getPendingNotifications()` | Lista notifiche schedulate non ancora consegnate |
| `getInitialNotification()` | Notifica che ha aperto l'app (cold start) |
| `createChannel(id, name, ...)` | Crea canale custom (solo Android) |

### Stream

| Stream | Tipo | Descrizione |
|---|---|---|
| `onNotificationTapped` | `Stream<FNotificationTapEvent>` | Tutti i tap: body, action, inline reply |

### Preset helpers

| Helper | Uso |
|---|---|
| `showStudyReminder(...)` | Promemoria di ripasso con azioni "Apri" / "Rimanda 1h" |
| `showExportDone(...)` | Conferma esportazione completata |
| `showProgress(...)` | Barra di progresso (determinata/indeterminata) |

---

## Modelli

### FNotification

```dart
FNotification(
  id: 'unique_id',              // Obbligatorio — usato per cancel/deduplica
  title: 'Titolo',              // Obbligatorio
  body: 'Corpo testo',          // Opzionale
  subtitle: 'Sottotitolo',      // Solo iOS
  style: FNotificationStyle.bigText,  // plain | bigText | bigPicture | inbox | progress
  priority: FNotificationPriority.high,
  category: FNotificationCategory.studySession,
  channelId: 'custom_channel',  // Default: fluera_default
  imageUrl: 'https://...',      // URL o asset per bigPicture / iOS attachment
  sound: 'study_bell',          // Nome file in raw/ (Android) o bundle (iOS)
  vibrate: true,
  data: {'canvasId': '42'},     // Payload custom → arriva nel tap event
  groupKey: 'study_reminders',  // Raggruppamento (Android group / iOS threadIdentifier)
  isGroupSummary: false,        // Android: notifica summary del gruppo
  actions: [                    // Max 3 Android, max 4 iOS
    FNotificationAction(id: 'open', label: 'Apri'),
    FNotificationAction(
      id: 'reply', label: 'Rispondi',
      requireInput: true, inputPlaceholder: 'Scrivi...',
      openApp: false,  // resta nella notification shade
    ),
  ],
  inboxLines: ['Linea 1', 'Linea 2'],  // Solo style: inbox
  progressMax: 100, progressCurrent: 75, // Solo style: progress
)
```

### FNotificationAction

| Proprietà | Tipo | Default | Descrizione |
|---|---|---|---|
| `id` | `String` | — | ID univoco, arriva in `FNotificationTapEvent.actionId` |
| `label` | `String` | — | Testo del bottone |
| `isDestructive` | `bool` | `false` | iOS: rosso |
| `isAuthRequired` | `bool` | `false` | iOS: richiede biometria |
| `openApp` | `bool` | `true` | Apre l'app al tap |
| `requireInput` | `bool` | `false` | Mostra campo testo inline |
| `inputPlaceholder` | `String?` | `null` | Placeholder del campo input |

### FNotificationTapEvent

| Proprietà | Tipo | Descrizione |
|---|---|---|
| `notificationId` | `String` | ID della notifica tappata |
| `actionId` | `String?` | ID dell'action (`null` = body tap) |
| `inputText` | `String?` | Testo digitato (inline reply) |
| `data` | `Map<String, String>?` | Payload custom |

---

## Canali Android

4 canali creati automaticamente + canali custom via `createChannel()`:

| ID | Nome | Importanza | Uso |
|---|---|---|---|
| `fluera_default` | Fluera | HIGH | Notifiche generali |
| `fluera_study` | Studio & Ripasso | HIGH | Promemoria studio |
| `fluera_export` | Esportazioni | DEFAULT | Export completato |
| `fluera_silent` | Silenziose | LOW | Aggiornamenti silenziosi |

### Icona personalizzata

L'icona di default è quella dell'app. Per personalizzarla, aggiungi nel `AndroidManifest.xml` dell'app host:

```xml
<meta-data
    android:name="com.flueraengine.notification_icon"
    android:resource="@drawable/ic_notification" />
```

---

## Cold Start & Buffering

Il problema: se l'app è killata e l'utente tappa una notifica, l'EventChannel non esiste ancora → l'evento si perde.

### Soluzione

```
Tap → Receiver/Delegate
  └─ EventSink disponibile? → invia subito
  └─ EventSink null? → salva su disco
      ├─ Android: SharedPreferences("fluera_notifications_queue")
      └─ iOS: UserDefaults("fluera_pending_tap_events")

App si avvia → EventChannel.onListen()
  └─ Legge da disco → invia tutti gli eventi → pulisce
```

**Zero eventi persi**, in qualsiasi stato dell'app (foreground, background, killed).

---

## Persistenza & Reboot

Le notifiche schedulate sopravvivono al riavvio del dispositivo:

- **Android**: `FlueraNotificationReceiver` ascolta `BOOT_COMPLETED`, legge gli allarmi da SharedPreferences e li ri-registra con AlarmManager. Le notifiche ricorrenti vengono rischedulate con `setRepeating` e il prossimo fire time viene calcolato automaticamente.

- **iOS**: `UNUserNotificationCenter` gestisce la persistenza internamente — le notifiche schedulate sopravvivono automaticamente al reboot.

---

## File del sistema

| File | Ruolo |
|---|---|
| `lib/src/platform/native_notifications.dart` | API Dart: modelli + NativeNotifications class |
| `android/.../NotificationPlugin.kt` | Plugin Android: canali, stili, scheduling, inline reply |
| `android/.../FlueraNotificationReceiver.kt` | Receiver Android: tap routing, delivery, boot recovery |
| `android/.../AndroidManifest.xml` | Permessi + receiver registration |
| `ios/Classes/NotificationPlugin.swift` | Plugin iOS: UserNotifications + delegate + TextInput |
| `android/.../FlueraEnginePlugin.kt` | Registra NotificationPlugin (Android) |
| `ios/Classes/FlueraEnginePlugin.swift` | Registra NotificationPlugin (iOS) |
| `lib/fluera_engine.dart` | Barrel export |
