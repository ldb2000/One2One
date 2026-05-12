# Calendar & Teams integration — Design spec

**Date**: 2026-05-12
**Branch**: `feat/calendar-teams-integration`
**Author**: laurent.deberti
**Status**: Approved (design phase), awaiting implementation plan.

## 1. Goals & non-goals

### Goals
- Capture meeting **start/end times** from imported calendar events (currently lost).
- **Outlook-style agenda inspector** (right panel) on Dashboard / MeetingsList showing events for the selected day.
- **Per-event quick actions**: join Teams call, import as Meeting, navigate to existing Meeting if already imported.
- **Auto-suggest MeetingKind**: `.manager` / `.oneToOne` / `.project` based on attendees + title fuzzy match against `Project.name`.
- **System notifications** (`UNUserNotificationCenter`) at meeting start, T-5 min before end, and at end.
- **Menu bar item** (NSStatusItem) inspired by [MeetingBar](https://github.com/leits/MeetingBar): show next meeting, click → list with quick-join.
- **Dashboard time stats** computed from calendar duration instead of recording duration.

### Non-goals (v1)
- MS Graph integration (no OAuth, no transcripts, no chat). Teams = parse join URL from EventKit only (decision **T-A**).
- LLM-based project matching (deterministic fuzzy match only; LLM is a future hook).
- Floating always-on-top windows for popups (decision **N-A**: system notifications only).
- Auto-start recording from notification (decision **R-A**: tap → open Meeting, user clicks Record manually).
- Snooze action on end-warning notification.
- Dock-less menubar-only mode (mentioned, deferred to v2).
- Conflict resolution UI for overlapping events.

## 2. Decisions log

| Ref | Decision | Value |
|-----|----------|-------|
| T-A | Teams scope | URL extraction only, no MS Graph |
| Q2  | Project matching | Title fuzzy match for `.project`; attendee email for `.oneToOne` / `.manager` |
| N-A | Popups | UNUserNotificationCenter only |
| R-A | Recording trigger | Manual; notif tap opens Meeting, no auto-record |
| D-D | Agenda placement | Trailing inspector panel (`.inspector` modifier) |
| S-A | Time stats | Calendar duration replaces recording duration (recording = fallback) |
| §7  | Menu bar | NSStatusItem with next-meeting display + dropdown agenda |

## 3. Architecture

```
EventKit ──► CalendarAgendaService ──► AgendaInspectorPanel
                    │                  │
                    │                  └─► MenuBarController (NSStatusItem)
                    │
                    ├─► MeetingNotificationService (3 notifs / Meeting)
                    │
                    └─► (user tap event)
                            └─► ProjectMatchService ─► CalendarMeetingImportService.importEvent
                                                          ─► Meeting (scheduledStart/End, teamsJoinURL, calendarEventID, kind)
```

### New / modified files

```
Services/
  CalendarMeetingImportService.swift   [extend: dates + Teams URL + importEvent()]
  CalendarAgendaService.swift          [NEW]
  MeetingNotificationService.swift     [NEW]
  TeamsLauncher.swift                  [NEW]
  ProjectMatchService.swift            [NEW]

Views/
  AgendaInspectorPanel.swift           [NEW]
  WeekStripView.swift                  [NEW — reusable horizontal day strip]
  MeetingsListView.swift               [extend: stats from effectiveDuration]
  CalendarEventImportSheet.swift       [extend: show match suggestion + confidence]
  SettingsView.swift                   [extend: menubar + notif toggles]

App/
  AppDelegate.swift                    [NEW or extend — own MenuBarController]
  OneToOneApp.swift                    [adopt NSApplicationDelegateAdaptor]

Controllers/
  MenuBarController.swift              [NEW — NSStatusItem]

Models/
  Meeting (in OtherModels.swift)       [add: scheduledStart, scheduledEnd, teamsJoinURL, calendarEventID]
  MeetingModels.swift                  [add: Meeting.effectiveDuration extension]
  AppSettings.swift                    [add menubar/notif settings]
  SchemaVersions.swift                 [bump version, lightweight migration]
```

## 4. Data model changes

### `Meeting` — new optional fields

```swift
var scheduledStart: Date?     // EKEvent.startDate
var scheduledEnd: Date?       // EKEvent.endDate
var teamsJoinURL: String?     // extracted from event.url / notes / location
var calendarEventID: String?  // EKEvent.calendarItemIdentifier — dedupe key
```

All optional → existing meetings stay valid; lightweight SwiftData migration (no custom mapping).

### `Meeting.effectiveDuration`

```swift
extension Meeting {
    var effectiveDuration: TimeInterval {
        if let s = scheduledStart, let e = scheduledEnd, e > s {
            return e.timeIntervalSince(s)
        }
        return recordingDuration  // fallback for ad-hoc meetings
    }
}
```

### Dedupe at import

Before creating a Meeting from an event:
```swift
let predicate = #Predicate<Meeting> { $0.calendarEventID == eventId }
if let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
    return existing  // navigate to existing instead of creating
}
```

## 5. Calendar import extensions

### `CalendarMeetingEvent` — extended

Add: `let teamsJoinURL: String?`

### Teams URL extraction (priority order)

1. `event.url` — accept if scheme `msteams` or host contains `teams.microsoft.com` / `teams.live.com`.
2. Regex over `event.notes`: `https://teams\.microsoft\.com/l/meetup-join/[^\s>"']+` (also `teams.live.com`).
3. Regex over `event.location` (rare fallback).

Return first non-nil match.

### `importEvent(_:) -> Meeting`

New method on `CalendarMeetingImportService`:
1. Dedupe via `calendarEventID`.
2. Create `Meeting`:
   - `title = event.title`
   - `date = event.startDate`
   - `scheduledStart = event.startDate`
   - `scheduledEnd = event.endDate`
   - `teamsJoinURL = extractedURL`
   - `calendarEventID = event.id`
3. Resolve participants (existing attendee → Collaborator dedup by email).
4. Call `ProjectMatchService.suggestKind(...)` → set `kind`, link `Project` or `Collaborator` if matched.
5. Schedule notifications via `MeetingNotificationService.schedule(for: meeting)`.

## 6. AgendaInspectorPanel

### Placement
- Use `.inspector { AgendaInspectorPanel() }` on Dashboard / MeetingsListView (macOS 14+).
- Toggle button in toolbar; persisted in `AppSettings.agendaInspectorOpenByDefault`.
- Width: ~320pt default, user-resizable.

### Layout

```
┌─────────────────────────────────────┐
│  5    6    7    8    9   10   11    │  ← WeekStripView (horizontal day strip)
│  M  [TUE]  W    T    F    S    S    │
├─────────────────────────────────────┤
│  Tuesday · 12 mai '26          6 >  │  ← day header + event count
├─────────────────────────────────────┤
│ 09:00 ─ 10:00                       │
│ [Téléphonie iPMI] Cadrage           │
│ 👥 4   📞 Teams                      │
│ ─────────────────────────────────── │
│ 10:00 ─ 11:30                       │
│ Entretien Sylvain Estellé           │
│ 👥 2   ⚠ no Teams link              │
│ ...                                 │
└─────────────────────────────────────┘
```

### WeekStripView

- Reusable SwiftUI component, `@Binding var selectedDate: Date`.
- Shows 7 days. Each cell: day number + first letter of weekday (locale-aware).
- Selected day: filled pill (accent color).
- Today (when not selected): subtle accent tint.
- Swipe left/right or `<` `>` buttons → shift week by ±7 days.
- Tap day header (Tuesday · 12 mai '26) → expand mini month calendar for distant date jumps.

### Event row interactions

Tap event row → context sheet/menu:
- **Rejoindre Teams** (enabled iff `teamsJoinURL != nil`)
- **Importer comme Meeting** (creates Meeting via `importEvent`)
- **Ouvrir Meeting** (visible iff Meeting with matching `calendarEventID` exists)

Visual states:
- Cancelled: strikethrough, gray.
- Declined: red border tint.
- Tentative: hatched.
- Accepted: normal/green accent.
- In progress (`now` between start/end): bold + colored bar.

### Data source

`CalendarAgendaService.eventsForDay(date)` calls existing `fetchEvents(start:end:)` with day bounds. Filter `!event.isAllDay`.

Refresh triggers:
- `selectedDate` change.
- `scenePhase` → `.active`.
- Timer 60s while panel visible.
- `EKEventStoreChanged` notification.

## 7. MenuBar (MeetingBar-inspired)

### Component

`MenuBarController: NSObject` owned by AppDelegate (`NSApplicationDelegateAdaptor`).

### Status item display

Configurable via settings:
- `[icon] Téléphonie iPMI · 09:00` — next meeting title + start time.
- `[icon] Dans 12 min : Sylvain Estellé` — countdown when <30 min.
- `[icon] En cours : Diapason (47m)` — when between start/end.
- `[icon]` only — when idle / setting disabled.

Refresh: 30s timer + `EKEventStoreChanged` + `scenePhase`.

### Dropdown menu

```
Aujourd'hui · mar 12 mai
─────────────────────────────
● 09:00  [Téléphonie iPMI] Cadrage
         ↳ Rejoindre Teams
         ↳ Ouvrir dans OneToOne
● 10:00  Sylvain Estellé
         ↳ (pas de lien Teams)
         ↳ Ouvrir dans OneToOne
○ 11:00  diapason (annulé)
...
─────────────────────────────
Demain · mer 13 mai          ▸   (submenu)
─────────────────────────────
Ouvrir OneToOne
Préférences…
Quitter
```

Status dots: `●` accepted (green) · `○` cancelled/declined (gray) · `◐` tentative (yellow). Bold rows for events starting within 15 min. `▶ EN COURS` prefix for active.

### Actions

- **Rejoindre Teams** → `TeamsLauncher.open(meeting.teamsJoinURL)` directly (no app activation needed).
- **Ouvrir dans OneToOne** → `NSApp.activate(ignoringOtherApps: true)` + navigate to Meeting (create via `importEvent` if not yet imported).
- Click status item title (when in "Dans X min" mode) → shortcut: join Teams if URL available.

### Architecture note

`CalendarAgendaService` is the single source of truth (ObservableObject singleton). Both `AgendaInspectorPanel` and `MenuBarController` observe it. No duplicated fetching.

## 8. Notifications (UNUserNotificationCenter)

### Setup

`MeetingNotificationService.requestAuthorization()` — alert + sound, called on first import or app launch.

### Three notifications per imported Meeting

Stable IDs based on `meeting.persistentModelID.storeIdentifier` + suffix:

| ID suffix      | Fire at              | Title                    | Body                                | Action               |
|----------------|----------------------|--------------------------|-------------------------------------|----------------------|
| `.start`       | `scheduledStart`     | Réunion: {title}         | Démarre maintenant                  | Ouvrir (default)     |
| `.endWarning`  | `scheduledEnd - 5m`  | Fin dans 5 min           | {title} se termine à {HH:mm}        | (info only)          |
| `.end`         | `scheduledEnd`       | Réunion terminée         | {title}                             | Ouvrir               |

### Categories

```swift
UNNotificationCategory(identifier: "MEETING_START",
    actions: [UNNotificationAction(identifier: "OPEN_MEETING", title: "Ouvrir", options: [.foreground])],
    intentIdentifiers: [])
// similarly MEETING_END
```

### Delegate

`UNUserNotificationCenterDelegate`:
- `userNotificationCenter(_:didReceive:withCompletionHandler:)` reads `userInfo["meetingID"]`, routes app to `MeetingView(meeting)`.
- Default tap = same as `OPEN_MEETING` action.

### Lifecycle

- On import → schedule all 3.
- On Meeting deletion → cancel by IDs.
- On schedule change (resync from calendar) → re-schedule.
- On app launch → `syncPending()` iterates Meetings with `scheduledStart > now` and re-posts notifications (resilience against reboot).
- On corresponding EKEvent deleted from calendar (detected on next `fetchEvents`) → cancel notifications for that Meeting.

## 9. Teams launcher

```swift
enum TeamsLauncher {
    static func open(_ urlString: String) {
        guard let parsed = URL(string: urlString) else { return }
        let target = toMSTeamsScheme(parsed) ?? parsed
        NSWorkspace.shared.open(target)
    }

    private static func toMSTeamsScheme(_ url: URL) -> URL? {
        if url.scheme == "msteams" { return url }
        guard let host = url.host?.lowercased(),
              host == "teams.microsoft.com" || host == "teams.live.com",
              url.path.contains("/l/meetup-join/") else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "msteams"
        return comps?.url
    }
}
```

Native fallback: if Teams desktop not installed, macOS routes `msteams://` to default browser → Teams web client.

## 10. ProjectMatchService

```swift
enum ProjectMatchService {
    static func suggestKind(for event: CalendarMeetingEvent,
                             context: ModelContext,
                             settings: AppSettings) -> MatchSuggestion
}

struct MatchSuggestion {
    let kind: MeetingKind
    let project: Project?
    let collaborator: Collaborator?
    let confidence: Double  // 0..1
    var autoApply: Bool { confidence >= 0.9 }
}
```

### Pipeline (short-circuit at first strong match)

1. **Manager**: attendee email matches `settings.managerEmail` (or secondary) → `.manager`, confidence 1.0.
2. **One-to-One**: exactly 2 attendees after filtering self (`settings.userEmail`):
   - Match the other email → existing `Collaborator` → `.oneToOne`, confidence 1.0.
   - No match → `.oneToOne`, confidence 0.6 (sheet offers to create Collaborator).
3. **Project**: fuzzy match `event.title` vs each `Project.name`:
   - `normalize(s) = s.lowercased().folding(.diacriticInsensitive).removingPunctuation.tokens`
   - `score = max(tokenOverlapRatio(a, b), jaroWinkler(joined(a), joined(b)))`
   - Best score ≥ 0.7 → `.project`, confidence = score.
4. **Fallback**: `.global`, confidence 0.3.

### Auto-apply

- `autoApply == true` (≥ 0.9): import creates Meeting immediately with `kind` + link.
- Else: `CalendarEventImportSheet` opens showing "Suggestion: Projet X (87%)" with override picker.

## 11. Stats temps (S-A)

Replace `recordingDuration` with `effectiveDuration` everywhere Meeting duration is displayed/aggregated:

Call sites to patch (to enumerate in implementation plan):
- `MeetingsListView` — per-row duration + aggregated stats.
- `ManagerTrackingView` — if it displays time stats.
- Dashboard widgets (if present).
- `ExportService` — exports.

Dashboard aggregate: "Temps en réunions cette semaine = X h Y m" = sum of `effectiveDuration` over Meetings whose `date` is in current week. No "agenda vs recording" breakdown (S-A explicit).

## 12. Settings (AppSettings)

New keys (with defaults):

```swift
var userEmail: String?                       // for "me" filtering in attendees
var menubarEnabled: Bool = true
var menubarShowNextTitle: Bool = true
var menubarMaxTitleChars: Int = 25
var agendaInspectorOpenByDefault: Bool = false
var notifMeetingStart: Bool = true
var notifMeetingEndWarning: Bool = true
var notifMeetingEnd: Bool = true
var autoImportThreshold: Double = 0.9
```

Surface in `SettingsView` under a new "Calendrier & menubar" section.

## 13. Permissions

- `NSCalendarsFullAccessUsageDescription` — verify Info.plist wording covers new use (likely already set for existing import).
- Notifications — runtime via `UNUserNotificationCenter.requestAuthorization` (no Info.plist key on macOS).
- Login launch (future) — `SMAppService.mainApp` (out of scope v1; mentioned).

## 14. Edge cases

**Handled v1**:
- All-day events excluded from inspector + menubar (`!event.isAllDay`).
- Event without Teams URL → "Rejoindre Teams" disabled (no error).
- Event modified in calendar after import → "Resync depuis calendrier" button in MeetingView updates `scheduledStart/End/title` after user confirmation.
- Calendar permission denied → empty state in inspector with "Autoriser" button → opens System Settings.
- Notification permission denied → settings shows status + link to System Settings.

**Out of scope v1** (documented for future):
- Recurrence: each EKEvent occurrence treated independently (EventKit expands automatically — acceptable for v1).
- Multi-account Google/Outlook: works transparently if accounts configured in macOS Calendar.app.
- Overlapping events: stacked vertically in inspector, no visual resolution.
- Snooze action on end-warning notif.
- Dock-less menubar-only activation policy toggle.

## 15. Testing strategy

### Unit (XCTest)
- `ProjectMatchService`: corpus of titles/projects, verify kind + confidence + auto-link.
- Fuzzy normalize + Jaro-Winkler: golden cases (`[Téléphonie iPMI] Cadrage` vs `Téléphonie IPMI`).
- Teams URL extraction: fixtures (msteams scheme, https teams.microsoft.com, in notes, in url, absent).
- `Meeting.effectiveDuration`: scheduled present / absent / inverted.

### Integration (in-memory `ModelContext`)
- Import event → Meeting with `scheduledStart/End/teamsJoinURL/calendarEventID` populated.
- Re-import same event → dedup via `calendarEventID`, no duplicate.
- `.oneToOne` match → Collaborator linked.
- `.project` match ≥ 0.9 → Project linked automatically.

### Manual
- AgendaInspectorPanel: WeekStripView nav, date selection, event rendering for each status.
- MenuBarController: status item rendering, dropdown actions, "Rejoindre Teams" without activating app.
- Notifications: schedule + delivery + tap → opens correct Meeting.
- Permission flows: cal denied, notif denied.
- Resync from calendar after event edit.

### Not tested
- `TeamsLauncher.open` (NSWorkspace side effect).
- `MenuBarController` UI rendering (NSStatusItem visuals).

## 16. Branch & integration

- Branch: `feat/calendar-teams-integration` off `master`.
- Single feature branch, sub-commits per service/view.
- Migration commit isolated (`feat(schema): scheduledStart/End + teamsJoinURL + calendarEventID`).
- No PR yet — local feature dev.

## 17. Out-of-scope future work

- MS Graph (T-B): transcripts ingestion, post summary to Teams chat, real attendance.
- Floating always-on-top popup window (N-B/N-C).
- Auto-start recording on notif tap (R-B/R-C).
- LLM-based project matching when fuzzy threshold misses.
- Multi-calendar account management UI (Google/Outlook direct OAuth).
- Snooze action.
- Dock-less menubar-only mode toggle.
- Login-launch via `SMAppService.mainApp`.
