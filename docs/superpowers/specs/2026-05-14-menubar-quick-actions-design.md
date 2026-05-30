# Menubar Quick Actions — Design spec

**Date**: 2026-05-14
**Branch**: TBD (probable: `feat/menubar-quick-actions`)
**Author**: laurent.deberti
**Status**: Approved (design phase), awaiting implementation plan.

## 1. Goals

Enrich the existing `MenuBarController` so the menubar becomes a true productivity hub: start meetings, capture actions/notes, jump to urgent items, search the database — all without ever bringing the main window forward.

## 2. Final menu layout

```
─── HEADER ───
Aujourd'hui · mer 14 mai

─── QUICK ACTIONS ───
+ Nouvelle réunion                          (Q1)
+ Démarrer 1:1                            ▸ (Q2 — submenu pinned + favourites)
+ 1:1 Manager                               (Q3)
+ Nouvelle action                           (Q4 — popover)
+ Note rapide                               (Q5 — popover)

─── AUJOURD'HUI (X restantes) ───            (A1 + A2 count)
● 10:00  [Téléphonie iPMI]                ▸
● 14:00  Echange LDB x TAC                ▸
○ 16:00  Annulé: ...

─── ⚠ ACTIONS URGENTES (N) ───
● Réévaluer planning (échéance hier)        (U1 — click opens popover U1c)
● Inclure Olivier (aujourd'hui)
● Contacter Benoît (demain)

─── RECHERCHE ───
🔍 Rechercher…                              (R1 — popover)

─── STATS ───
3h45 passées · 2 sans projet                (S1)

─── FOOTER ───
Ouvrir OneToOne
Quitter
```

Icon badge (U2): when at least one urgent action exists, append ` ●N` to the status item's title (red if any overdue, otherwise orange).

## 3. Quick actions

### Q1 — Nouvelle réunion ad-hoc

- Title: `"Réunion ad-hoc \(HH:mm)"`
- `kind = .global`, `date = Date()`
- `QuickLaunchRouter.startAdHocMeeting(in:)` — new method to add; publishes a token with `autoStartRecording = true`
- Opens the 1to1-meeting WindowGroup with recording on launch.

### Q2 — Démarrer 1:1 (submenu)

Submenu populated from collaborators where `pinLevel >= 1`, ordered:
1. `pinLevel == 2` (pinned/sidebar) sorted A–Z.
2. Divider.
3. `pinLevel == 1` (favourites) sorted A–Z.

Click → `QuickLaunchRouter.startOneToOne(collaborator:, autoStartRecording: true, in: context)`.

Empty case: a disabled item "(aucun favori — épinglez depuis Collaborateurs)".

### Q3 — 1:1 Manager

- Resolves `settings.managerEmail` to a `Collaborator`.
- If found: extends `QuickLaunchRouter` with `startManagerMeeting(collaborator:in:)` — sets `kind = .manager`, autoStartRecording true.
- If not configured: disabled with tooltip "(Manager non configuré dans Préférences)".

### Q4 — Nouvelle action (popover)

NSPopover anchored on the status item button, ~360pt wide:

```
[TextField "Titre de l'action..."]
[Menu Projet ▾]  [Menu Assigné à ▾]  [DatePicker échéance]
                            [ Créer ]
```

- Title required (Créer disabled if empty after trim).
- Projet picker uses the hierarchical entity → projets layout from `ActionsListView`.
- Assigné à picker uses `CollaboratorPickerOptions` (favourites first).
- DatePicker compact; nil if not set.
- On Créer: insert `ActionTask`, save, dismiss.

### Q5 — Note rapide (popover)

NSPopover ~400pt wide:

```
[TextEditor (6 rows) "Note..."]
[Menu Lié à ▾]    [ Sauver ]
```

- "Lié à" optional: single picker that exposes "Aucun", then a divider, then projects (A–Z) and collaborators (A–Z) flagged with `📁` / `👤`.
- On Sauver: insert `Note` with appropriate relationship (or standalone), save, dismiss.

## 4. Aujourd'hui section

Unchanged behaviour for event rows (status dots, submenu with Rejoindre Teams / Ouvrir dans OneToOne). New:
- **A2 counter** in the section header: number of events with `endDate >= now` and not cancelled.

## 5. Actions urgentes (U1, U2)

### Selection (`UrgentActionsSelector`)

`ActionTask` row qualifies when **both**:
- `!isCompleted`
- One of: `dueDate <= endOfToday` OR (`dueDate == nil` AND `createdAt <= now - 30 days`)

Sort key (ascending precedence):
1. Overdue (`dueDate < startOfToday`).
2. Today (`dueDate` within today).
3. Old without date.

Within each bucket, sort by `dueDate` ascending (nil last).

Menu shows top 3. Badge counts all qualifying rows.

### Menu rows

```
● Titre tronqué… (échéance hier)
```

- Coloured dot: red overdue, orange today, gray no-date.
- Title truncated to `settings.menubarMaxTitleChars`.
- Subtitle parenthetical: "(échéance hier)" / "(aujourd'hui)" / "(sans date — N jours)".

Click → `UrgentActionPopover` (U1c).

### Popover U1c (~380pt)

```
[Titre complet, bold]
Projet: <nom>  ·  Assigné: <collab>  ·  Échéance: <date>
─────────────
[Up to 3 most recent comments — read-only]
─────────────
[ Terminer ✓ ]  [ Ouvrir Meeting ↗ ]  [ Fermer ]
```

- Terminer: sets `isCompleted = true`, `completedAt = Date()`, save, close popover.
- Ouvrir Meeting: only enabled when `task.meeting != nil`. Publishes `QuickLaunchRouter.pendingToken` for that Meeting.
- No inline editing — ActionsListView remains the canonical edit surface.

### Badge (U2)

- Plain text suffix on `statusItem.button.attributedTitle`: ` ●N` after the regular menubar title.
- Foreground colour: red when any qualifying task is overdue, orange otherwise.
- Suppressed when N == 0.

## 6. Recherche rapide (R1)

NSPopover ~440 × 360pt:

```
[NSSearchField "Rechercher..."]
─────────────
RÉUNIONS
  ▸ 12 mai — Echange LDB x TAC
  ▸ 28 avr — [Téléphonie iPMI] Cadrage
COLLABORATEURS
  ▸ ⭐ Wilfried THEDREZ
  ▸ Sylvain Estellé
PROJETS
  ▸ Téléphonie iPMI
  ▸ Diapason
```

- 200 ms debounce.
- Top 5 per section.
- Predicates:
  - `Meeting.title.localizedStandardContains(q)` — order `date` desc.
  - `Collaborator.name.localizedStandardContains(q)` AND `!isArchived` — favourites first then A–Z.
  - `Project.(name|code).localizedStandardContains(q)` AND `!isArchived` — A–Z.
- Click → activate app + open the appropriate detail view; popover dismisses.
- Esc / Cmd+W closes popover.
- ↑/↓ to navigate, Return to open.

## 7. Stats footer (S1)

Computed daily from `meetings`:
- `tempsPasse` = sum of `effectiveDuration` for meetings whose `endDate < now` and whose `date` is within today.
- `sansProjet` = count of meetings within today (any status) where `project == nil`.

Format (italic, disabled menu item):
- Both present: `Xh YYmin passées · N sans projet`
- Only `tempsPasse > 0`: `Xh YYmin passées`
- Only `sansProjet > 0`: `Pas encore de réunion terminée · N sans projet`
- Both zero: omit the entire stats line.

## 8. Refresh triggers

- Existing: 30 s timer, `EKEventStoreChanged`, `CalendarAgendaService.$eventsToday`, `scenePhase` → `.active`.
- **New**: `NSNotification.Name.NSManagedObjectContextDidSave` observer filtered on `ActionTask` / `Meeting` inserts/updates/deletes → triggers `refresh()` (badge + section urgentes + stats + Aujourd'hui counter).
- All refreshes coalesced through the existing `MenuBarController.refresh()` which is idempotent.

## 9. Architecture

**Files**:
- Modify: `OneToOne/Services/MenuBarController.swift` (host the new sections + popover instances).
- Modify: `OneToOne/Services/QuickLaunchRouter.swift` (add `startAdHocMeeting`, `startManagerMeeting`).
- New: `OneToOne/Services/MenuBarStats.swift` (pure helpers: `UrgentActionsSelector`, `TodayStatsCalculator`, `MenubarBadgeText`).
- New SwiftUI views (each in its own file under `OneToOne/Views/Menubar/`):
  - `QuickActionPopover.swift`
  - `QuickNotePopover.swift`
  - `UrgentActionPopover.swift`
  - `SearchPopover.swift`

**Popover hosting pattern**: one `NSPopover` per type, owned by `MenuBarController`. SwiftUI content wrapped in `NSHostingController`. Anchored on `statusItem.button` with `NSRectEdge.minY`. Behaviour `.transient` (closes on outside click).

## 10. Edge cases

- App not activated when triggering Q2/Q3: call `NSApp.activate(ignoringOtherApps: true)` before publishing the launch token.
- Empty managerEmail in settings: Q3 disabled with tooltip.
- No favourites: Q2 submenu shows disabled hint.
- No urgent actions: section header omitted.
- Badge text rebuild safe across colour scheme changes (uses semantic NSColor values).
- ModelContainer unavailable during early init: every quick action disabled until `install(container:)` has run.

## 11. Out of scope (deferred)

- Inline editing in U1c (read-only by design).
- "Demain" / "Cette semaine" submenus (D1/D2 rejected during brainstorming).
- Project list as a top-level submenu (R2 rejected — projects reachable via R1).
- Drag-and-drop image / attachments into Q5.
- Stats for upcoming meetings (only past ones requested).

## 12. Testing

**Unit (XCTest, in-memory `ModelContext`) — in `MenuBarStats.swift` helpers**:
- `UrgentActionsSelector` with mixed corpus → verifies bucket order + 30-day stale filter.
- `TodayStatsCalculator` with meetings before/after `now` → past-only sum, count without project.
- `MenubarBadgeText`: counts {0, 3, 12} → format `""`, `" ●3"`, `" ●12"` with correct colour.

**Manual** (NSStatusItem / NSPopover not unit-testable):
- All Q1–Q5 actions reach the right model state and reopen the right window/view.
- U1c "Terminer" updates task and removes it from menu on next refresh.
- R1 returns relevant results across the three sections, debounce smooth, Return opens.
- Badge updates within ~1 s when an action is completed via the app.

## 13. Open follow-ups (post-merge)

- Persisting the popover's last-used "Lié à" / project in `AppSettings` for faster reuse.
- Keyboard shortcuts on the status item (`Cmd+Shift+N` for Nouvelle réunion, etc.).
- Notification when an urgent action becomes overdue (separate notification stream from meeting reminders).
