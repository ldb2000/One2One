# MeetingView Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `OneToOne/Views/MeetingView.swift` from a dense 1578-line native macOS layout to an editorial cream/serif layout (per `docs/superpowers/specs/2026-04-24-meeting-view-redesign-design.md`) without changing any business logic.

**Architecture:** In-place refactor. Extract MeetingView into one orchestrator (state + services + async actions) plus 8 focused subviews under `OneToOne/Views/Meeting/`. Each subview receives `@Bindable var meeting` and/or service `@ObservedObject`s + closures for async actions. Shared design tokens live in `MeetingTheme`. Collapsible states persist via `@SceneStorage`.

**Tech Stack:** SwiftUI (macOS 14+), SwiftData, Swift 5.9+. Build via `swift run -c release OneToOne` (see `run.sh`). No existing UI test framework; verification is build success + SwiftUI Previews + manual smoke tests at Task 9.

**Non-goals (from spec §8):** no model changes (except optional `ActionTask.sortIndex` — we skip it in phase 1 and fall back to insertion order), no service changes, no refactor of `transcriptView`/`reportView`/`documentsView` bodies beyond padding + serif typography, no dark mode.

**Conventions:**
- File header: no multi-line comment block. Just `import SwiftUI` and the type.
- Colors: never hardcode; always `MeetingTheme.xxx`.
- Strings: French for user-facing labels (matches existing app).
- Previews: each new subview ships with a `#Preview` using dummy `Meeting`/`Collaborator` fixtures.

---

## File Map

**Created:**
- `OneToOne/Views/Meeting/MeetingTheme.swift` — design tokens (colors, fonts).
- `OneToOne/Views/Meeting/MeetingAvatarStack.swift` — overlapping avatars + `AvatarCircle` + `AvatarMini`.
- `OneToOne/Views/Meeting/MeetingHeaderEditorial.swift` — badge + serif title + date + avatar stack.
- `OneToOne/Views/Meeting/MeetingDetailsBlock.swift` — collapsible details (type/project/participants/collaborators/prompt).
- `OneToOne/Views/Meeting/MeetingTabsUnderline.swift` — underline tab bar.
- `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` — breadcrumb + recorder pill + capture + rapport + ⋯ menu.
- `OneToOne/Views/Meeting/MeetingContextualRecorderBar.swift` — recording/playback/capture/progress segments.
- `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` — tasks list + form + capture preview + 44pt rail.
- `OneToOne/Views/Layouts/FlowLayout.swift` — extracted existing `FlowLayout`.

**Modified:**
- `OneToOne/Views/MeetingView.swift` — shrunk from ~1578 to ~350 lines; keeps state, services, async actions, orchestration.
- `Package.swift` — nothing expected; verify no source file additions break the target.

**Unchanged (do not touch):**
- `OneToOne/Models/*` — no model migration.
- `OneToOne/Services/*` — zero changes.
- `OneToOne/Views/EditableTextField.swift` — reused as-is.
- Other views — not touched.

---

## Task 1: Scaffold folder + MeetingTheme + extract FlowLayout

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingTheme.swift`
- Create: `OneToOne/Views/Layouts/FlowLayout.swift`
- Modify: `OneToOne/Views/MeetingView.swift` (remove `FlowLayout` struct at lines ~1549-1578)

- [ ] **Step 1: Create the Meeting folder and MeetingTheme.swift**

Create `OneToOne/Views/Meeting/MeetingTheme.swift`:

```swift
import SwiftUI
import AppKit

enum MeetingTheme {
    static let canvasCream  = Color(nsColor: NSColor(srgbRed: 0.976, green: 0.960, blue: 0.929, alpha: 1))
    static let surfaceCream = Color(nsColor: NSColor(srgbRed: 0.988, green: 0.980, blue: 0.957, alpha: 1))
    static let accentOrange = Color(nsColor: NSColor(srgbRed: 0.776, green: 0.400, blue: 0.400, alpha: 1))
    static let hairline     = Color.secondary.opacity(0.18)
    static let badgeBlack   = Color(nsColor: NSColor(white: 0.10, alpha: 1))
    static let softShadow   = Color.black.opacity(0.06)

    static let titleSerif   = Font.system(size: 34, weight: .semibold, design: .serif)
    static let bodySerif    = Font.system(.body, design: .serif)
    static let sectionLabel = Font.caption2.weight(.bold)
    static let meta         = Font.caption.monospacedDigit()
}
```

- [ ] **Step 2: Create Layouts folder and extract FlowLayout**

Create `OneToOne/Views/Layouts/FlowLayout.swift`:

```swift
import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, maxH: CGFloat = 0, maxW: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > width && x > 0 {
                x = 0; y += maxH + spacing; maxH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxH = max(maxH, sz.height)
            x += sz.width + spacing
            maxW = max(maxW, x)
        }
        return (CGSize(width: maxW, height: y + maxH), positions)
    }
}
```

- [ ] **Step 3: Remove FlowLayout from MeetingView.swift**

Open `OneToOne/Views/MeetingView.swift`. Delete the entire `// MARK: - FlowLayout (inchangé)` block and the `struct FlowLayout: Layout { … }` definition at the bottom of the file (lines ~1547 to end-of-file).

- [ ] **Step 4: Build and verify**

Run: `swift build -c debug --target OneToOne`

Expected: success. If `FlowLayout` is referenced elsewhere, the build fails — grep for it and add `import` only if it was accessed across modules (it's not — same target).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingTheme.swift \
        OneToOne/Views/Layouts/FlowLayout.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "refactor(meeting): extract MeetingTheme tokens + FlowLayout"
```

---

## Task 2: AvatarCircle, AvatarMini, MeetingAvatarStack

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingAvatarStack.swift`

- [ ] **Step 1: Write the component file**

Create `OneToOne/Views/Meeting/MeetingAvatarStack.swift`:

```swift
import SwiftUI

struct AvatarCircle: View {
    let collaborator: Collaborator
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Text(initials(for: collaborator.name))
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(whereSeparator: { !$0.isLetter })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

struct AvatarMini: View {
    let collaborator: Collaborator
    let tint: Color
    var body: some View {
        AvatarCircle(collaborator: collaborator, size: 18, tint: tint)
    }
}

struct MeetingAvatarStack: View {
    let participants: [Collaborator]
    let max: Int
    let tint: (Collaborator) -> Color
    let borderColor: Color

    init(
        participants: [Collaborator],
        max: Int = 8,
        borderColor: Color = MeetingTheme.canvasCream,
        tint: @escaping (Collaborator) -> Color
    ) {
        self.participants = participants
        self.max = max
        self.borderColor = borderColor
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(participants.prefix(max).enumerated()), id: \.element.persistentModelID) { idx, p in
                AvatarCircle(collaborator: p, size: 26, tint: tint(p))
                    .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
                    .zIndex(Double(max - idx))
            }
            if participants.count > max {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.25))
                    Text("+\(participants.count - max)")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
            }
        }
    }
}

#Preview {
    let c1 = Collaborator(name: "Jimmy DUONG")
    let c2 = Collaborator(name: "Frederic NGUYEN")
    let c3 = Collaborator(name: "Manuel RIGAUT")
    return MeetingAvatarStack(
        participants: [c1, c2, c3],
        tint: { _ in .blue }
    )
    .padding()
    .background(MeetingTheme.canvasCream)
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Visual check via Preview**

Open the file in Xcode, open the canvas (`Cmd+Opt+Enter`), click "Resume". Expect three overlapping circles with initials `JD`, `FN`, `MR` on a cream background.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingAvatarStack.swift
git commit -m "feat(meeting): add AvatarCircle, AvatarMini, MeetingAvatarStack"
```

---

## Task 3: MeetingHeaderEditorial (replace existing header)

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingHeaderEditorial.swift`
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Create the header component**

Create `OneToOne/Views/Meeting/MeetingHeaderEditorial.swift`:

```swift
import SwiftUI

struct MeetingHeaderEditorial: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    @Binding var detailsExpanded: Bool

    @State private var showDatePopover = false

    private var kindLabel: String {
        switch meeting.kind {
        case .project:   return "COPIL · PROJET"
        case .oneToOne:
            let name = meeting.participants.first?.name.uppercased() ?? ""
            return name.isEmpty ? "1:1" : "1:1 · \(name)"
        case .work:      return "RÉUNION DE TRAVAIL"
        case .global:    return "RÉUNION"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: badge + kind label
            HStack(spacing: 10) {
                if let project = meeting.project {
                    Text(project.code)
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MeetingTheme.badgeBlack)
                        .clipShape(Capsule())
                }
                Text(kindLabel)
                    .font(MeetingTheme.sectionLabel)
                    .tracking(1.4)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Row 2: editable title
            EditableTextField(placeholder: "Titre de la réunion…", text: $meeting.title)
                .font(MeetingTheme.titleSerif)
                .frame(minHeight: 44, alignment: .leading)

            // Row 3: date · avatars · count
            HStack(spacing: 14) {
                Button { showDatePopover.toggle() } label: {
                    Text(dateLabel)
                        .font(MeetingTheme.meta)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePopover) {
                    DatePicker("", selection: $meeting.date, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .padding()
                }

                if !meeting.participants.isEmpty {
                    MeetingAvatarStack(
                        participants: meeting.participants,
                        tint: { settings.meetingParticipantColor }
                    )

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            detailsExpanded.toggle()
                        }
                    } label: {
                        Text("\(meeting.participants.count) participants")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(MeetingTheme.canvasCream)
    }

    private var dateLabel: String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy · HH:mm"
        return df.string(from: meeting.date)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Wire into MeetingView.mainPanel, delete old header**

In `OneToOne/Views/MeetingView.swift`:

1. Add `@State private var detailsExpanded: Bool = true` near the other `@State` variables (after `@State private var saveStatusMessage: String?`).
2. In `mainPanel`, replace the line `header` with:
   ```swift
   MeetingHeaderEditorial(
       meeting: meeting,
       settings: settings,
       detailsExpanded: $detailsExpanded
   )
   ```
3. Delete the entire `private var header: some View { … }` computed property block (the `MARK: - Header` section, ~lines 134-244 of the current file).
4. Keep `participantsSection` for now — it will be replaced in Task 4.
5. Inside `mainPanel`, add `participantsSection` call directly below the new header so participants stay visible for now:
   ```swift
   MeetingHeaderEditorial(...)
   participantsSection
       .padding(.horizontal, 28)
   ```
   (Temporary — Task 4 removes `participantsSection`.)

- [ ] **Step 4: Build and run**

Run: `swift build -c debug --target OneToOne`

Expected: success.

Run: `./run.sh`

Open a meeting. Expected: editorial header visible with cream background, badge (if project), kind label, large serif title, date + avatars + participant count. Clicking the count does nothing useful yet — details toggle wires in Task 4. Clicking the date opens DatePicker popover.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingHeaderEditorial.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): editorial header with serif title + avatar stack"
```

---

## Task 4: MeetingDetailsBlock (replace participantsSection + TYPE/PROJET rows)

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingDetailsBlock.swift`
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Create the details block**

Create `OneToOne/Views/Meeting/MeetingDetailsBlock.swift`:

```swift
import SwiftUI
import SwiftData

struct MeetingDetailsBlock: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let availableCollaborators: [Collaborator]
    let projects: [Project]

    @Binding var expanded: Bool
    @Binding var showCustomPrompt: Bool
    @Binding var newAdhocName: String
    @Binding var calendarImportError: String?

    let addParticipant: (Collaborator) -> Void
    let removeParticipant: (Collaborator) -> Void
    let setParticipantStatus: (MeetingAttendanceStatus, Collaborator) -> Void
    let participantStatus: (Collaborator) -> MeetingAttendanceStatus
    let addAdhoc: () -> Void
    let saveContext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Détails de la réunion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    typeProjectRow
                    participantsBlock
                    if !availableCollaborators.isEmpty { collaboratorsBlock }
                    adhocRow
                    if showCustomPrompt {
                        TextEditor(text: $meeting.customPrompt)
                            .font(.body)
                            .frame(height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(MeetingTheme.hairline, lineWidth: 1)
                            )
                    }
                    if let calendarImportError, !calendarImportError.isEmpty {
                        Text(calendarImportError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
        }
        .background(MeetingTheme.canvasCream)
    }

    private var typeProjectRow: some View {
        HStack(spacing: 16) {
            labeled("TYPE") {
                Picker("", selection: Binding(
                    get: { meeting.kind },
                    set: { meeting.kind = $0; saveContext() }
                )) {
                    ForEach(MeetingKind.allCases) { k in
                        Label(k.label, systemImage: k.sfSymbol).tag(k)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
            }
            if meeting.kind == .project {
                labeled("PROJET") {
                    Picker("", selection: Binding(
                        get: { meeting.project },
                        set: { meeting.project = $0; saveContext() }
                    )) {
                        Text("Aucun projet").tag(nil as Project?)
                        ForEach(projects.sorted(by: { $0.name < $1.name })) { p in
                            Text(p.name).tag(p as Project?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)
                }
            }
            Spacer()
        }
    }

    private var participantsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PARTICIPANTS")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            if !meeting.calendarEventTitle.isEmpty {
                Label(
                    "\(meeting.calendarEventTitle) • \(meeting.date.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(meeting.participants, id: \.persistentModelID) { p in
                    Menu {
                        ForEach(MeetingAttendanceStatus.allCases) { status in
                            Button(action: { setParticipantStatus(status, p) }) {
                                Label(status.label, systemImage: status.sfSymbol)
                            }
                        }
                        Divider()
                        Button(role: .destructive, action: { removeParticipant(p) }) {
                            Label("Retirer", systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            AvatarMini(collaborator: p, tint: settings.meetingParticipantColor)
                            Text(p.name).font(.caption)
                            if participantStatus(p) == .absent {
                                Image(systemName: MeetingAttendanceStatus.absent.sfSymbol)
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(participantChipColor(for: p))
                        .cornerRadius(12)
                    }
                    .menuStyle(.borderlessButton)
                }

                Menu {
                    ForEach(availableCollaborators) { c in
                        Button(c.name) { addParticipant(c) }
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus.circle").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 100)
            }
        }
    }

    private var collaboratorsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLLABORATEURS")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(availableCollaborators, id: \.persistentModelID) { c in
                    Button(action: { addParticipant(c) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill").font(.caption2)
                            Text(c.name).font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(settings.meetingCollaboratorColor)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var adhocRow: some View {
        HStack(spacing: 6) {
            TextField("Ad-hoc : nom…", text: $newAdhocName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit { addAdhoc() }
            Button(action: addAdhoc) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(newAdhocName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func participantChipColor(for c: Collaborator) -> Color {
        switch participantStatus(c) {
        case .participant: return settings.meetingParticipantColor
        case .absent:      return settings.meetingAbsentColor
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Wire into MeetingView, remove old participantsSection**

In `OneToOne/Views/MeetingView.swift`:

1. Replace the `@State private var detailsExpanded: Bool = true` added in Task 3 with persistent storage:
   ```swift
   @SceneStorage("meeting.detailsExpanded") private var detailsExpanded: Bool = true
   ```
   (Single key for all meetings — acceptable in phase 1. Per-meeting persistence can be added later if needed — the spec §4 mentions `@SceneStorage("meeting.\(id)...")` but keying on `persistentModelID` from SwiftData inside `@SceneStorage` is unreliable. Phase 1: one global setting.)
2. In `mainPanel`, replace the temporary `participantsSection` call added in Task 3 with:
   ```swift
   MeetingDetailsBlock(
       meeting: meeting,
       settings: settings,
       allCollaborators: allCollaborators,
       availableCollaborators: availableCollaborators,
       projects: projects,
       expanded: $detailsExpanded,
       showCustomPrompt: $showCustomPrompt,
       newAdhocName: $newAdhocName,
       calendarImportError: $calendarImportError,
       addParticipant: addParticipant,
       removeParticipant: removeParticipant,
       setParticipantStatus: setParticipantStatus,
       participantStatus: participantStatus,
       addAdhoc: addAdhocParticipant,
       saveContext: saveContext
   )
   ```
3. Delete the `private var participantsSection: some View { … }` computed property block.
4. Delete helpers that only `participantsSection` used: `participantChipColor(for:)` and `collaboratorChipColor` (now duplicated inside `MeetingDetailsBlock`). Keep `participantStatus(for:)`, `setParticipantStatus(_:for:)`, `addParticipant(_:)`, `removeParticipant(_:)`, `addAdhocParticipant()`, `availableCollaborators` computed — they're passed as closures.

- [ ] **Step 4: Build and run**

Run: `swift build -c debug --target OneToOne`

Expected: success.

Run: `./run.sh`. Open a meeting. Expect: below the editorial header, a row `▾ Détails de la réunion`. Clicking collapses/expands the type/project/participants/collaborators/ad-hoc rows. All existing functionality (add/remove participant, set status, add collaborator, ad-hoc) works.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingDetailsBlock.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): collapsible details block (type, project, participants, collaborators)"
```

---

## Task 5: MeetingTabsUnderline (replace sectionPicker)

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingTabsUnderline.swift`
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Create the tabs component**

Create `OneToOne/Views/Meeting/MeetingTabsUnderline.swift`:

```swift
import SwiftUI

struct MeetingTabsUnderline: View {
    @Binding var selection: MeetingView.MeetingSection
    let attachmentsCount: Int
    let hasReport: Bool

    @Namespace private var underlineNS

    var body: some View {
        HStack(spacing: 28) {
            ForEach(MeetingView.MeetingSection.allCases) { section in
                tab(section)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MeetingTheme.hairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tab(_ section: MeetingView.MeetingSection) -> some View {
        let isActive = selection == section
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = section }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(section.rawValue)
                        .font(isActive ? .body.weight(.semibold) : .body)
                        .foregroundColor(isActive ? .primary : .secondary)
                    badge(for: section)
                }
                if isActive {
                    Rectangle()
                        .fill(MeetingTheme.accentOrange)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underlineNS)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badge(for section: MeetingView.MeetingSection) -> some View {
        switch section {
        case .documents where attachmentsCount > 0:
            Text("\(attachmentsCount)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary))
        case .report where hasReport:
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundColor(MeetingTheme.accentOrange)
        default:
            EmptyView()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Wire into MeetingView, remove sectionPicker**

In `OneToOne/Views/MeetingView.swift`:

1. Replace the `sectionPicker` usage inside `mainPanel` with:
   ```swift
   MeetingTabsUnderline(
       selection: $activeSection,
       attachmentsCount: meeting.attachments.count,
       hasReport: !meeting.summary.isEmpty
   )
   ```
2. Delete the `private var sectionPicker: some View { … }` block.
3. Also remove the `Divider()` that appears above it in `mainPanel` (the underline bar replaces it visually).
4. Adjust `sectionContent` padding to match spec (28 horizontal):
   ```swift
   sectionContent
       .padding(.horizontal, 28)
       .padding(.top, 12)
       .padding(.bottom, 16)
   ```

- [ ] **Step 4: Build and run**

Run: `swift build -c debug --target OneToOne` then `./run.sh`

Expected: the segmented picker is gone; four underlined tabs appear. Clicking animates the underline. Badge `(N)` on Documents when attachments exist, `✓` on Rapport when summary exists.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingTabsUnderline.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): underline tab bar with badges"
```

---

## Task 6: MeetingTopChromeBar

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingTopChromeBar.swift`
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Create the top chrome bar**

Create `OneToOne/Views/Meeting/MeetingTopChromeBar.swift`:

```swift
import SwiftUI

struct MeetingTopChromeBar: View {
    @Bindable var meeting: Meeting
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var captureService: ScreenCaptureService
    let isGeneratingReport: Bool
    let capturedSlidesCount: Int
    let hasWav: Bool

    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onTogglePause: () -> Void
    let onTogglePlay: () -> Void
    let onRetranscribe: () -> Void
    let onGenerateReport: () -> Void
    let onShowCaptureSetup: () -> Void
    let onShowSlides: () -> Void
    let onToggleCustomPrompt: () -> Void
    let onImportCalendar: () -> Void
    let onExportMarkdown: () -> Void
    let onExportPDF: () -> Void
    let onExportMail: () -> Void
    let onExportEML: () -> Void
    let onExportAppleNotes: () -> Void
    let onSaveNow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            breadcrumb
            Spacer()
            recorderPill
            captureButton
            reportButton
            moreMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MeetingTheme.canvasCream)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MeetingTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text("One2One").foregroundColor(.secondary)
            chevron
            if let project = meeting.project {
                Text("Projets").foregroundColor(.secondary)
                chevron
                Text(project.name).fontWeight(.semibold).foregroundColor(.primary)
            } else {
                Text(meeting.kind.label).fontWeight(.semibold).foregroundColor(.primary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
    }

    // MARK: - Recorder pill

    @ViewBuilder
    private var recorderPill: some View {
        if recorder.isRecording {
            recordingPill
        } else if hasWav {
            playbackPill
        } else {
            idlePill
        }
    }

    private var idlePill: some View {
        Button(action: onStartRecording) {
            Label("Enregistrer", systemImage: "record.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.red))
        }
        .buttonStyle(.plain)
        .disabled(stt.isTranscribing || isGeneratingReport)
    }

    private var recordingPill: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(formatDuration(recorder.elapsedSeconds))
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
            Button(action: onTogglePause) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            Button(action: onStopRecording) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(MeetingTheme.badgeBlack))
    }

    private var playbackPill: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlay) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            Text("\(formatDuration(player.currentTime)) / \(formatDuration(max(player.duration, TimeInterval(meeting.durationSeconds))))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
            Button(action: onRetranscribe) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .disabled(stt.isTranscribing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(MeetingTheme.badgeBlack))
    }

    // MARK: - Capture button

    @ViewBuilder
    private var captureButton: some View {
        if captureService.isCapturing {
            Button(action: onShowSlides) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("\(captureService.capturedSlidesCount) slides")
                }
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.blue.opacity(0.15)))
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        } else if capturedSlidesCount > 0 {
            Button(action: onShowSlides) {
                Label("Capture", systemImage: "camera.viewfinder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .overlay(alignment: .topTrailing) {
                Text("\(capturedSlidesCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 4, y: -4)
            }
        } else {
            Button(action: onShowCaptureSetup) {
                Label("Capture", systemImage: "camera.viewfinder").font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Report button

    @ViewBuilder
    private var reportButton: some View {
        let disabled = meeting.rawTranscript.isEmpty || recorder.isRecording || stt.isTranscribing || isGeneratingReport
        Button(action: onGenerateReport) {
            HStack(spacing: 4) {
                if isGeneratingReport {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(meeting.summary.isEmpty ? "Rapport" : "Rapport ✓")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(disabled ? Color.secondary.opacity(0.4) : MeetingTheme.accentOrange)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - More menu

    private var moreMenu: some View {
        Menu {
            Section("Exporter") {
                Button(action: onExportMarkdown) { Label("Copier Markdown", systemImage: "doc.text") }
                Button(action: onExportPDF) { Label("Exporter PDF", systemImage: "doc.richtext") }
                Button(action: onExportMail) { Label("Envoyer par mail", systemImage: "envelope") }
                Button(action: onExportEML) { Label("Exporter Outlook (.eml)", systemImage: "envelope.badge") }
                Button(action: onExportAppleNotes) { Label("Exporter vers Apple Notes", systemImage: "note.text") }
            }
            Divider()
            Button(action: onToggleCustomPrompt) { Label("Prompt spécifique", systemImage: "text.bubble") }
            Button(action: onImportCalendar) { Label("Importer Calendrier", systemImage: "calendar.badge.plus") }
            Divider()
            Button(action: onSaveNow) { Label("Enregistrer maintenant", systemImage: "checkmark.circle") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Wire into MeetingView.body, strip toolbar, expose async actions**

In `OneToOne/Views/MeetingView.swift`:

1. Modify `var body: some View` to:
   ```swift
   var body: some View {
       VStack(spacing: 0) {
           MeetingTopChromeBar(
               meeting: meeting,
               recorder: recorder,
               stt: stt,
               player: player,
               captureService: captureService,
               isGeneratingReport: isGeneratingReport,
               capturedSlidesCount: currentSlides.count,
               hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
               onStartRecording: { Task { await startRecording() } },
               onStopRecording:  { Task { await stopRecordingAndTranscribe() } },
               onTogglePause:    { if recorder.isPaused { recorder.resume() } else { recorder.pause() } },
               onTogglePlay:     { if let wav = meeting.wavFileURL { togglePlay(url: wav) } },
               onRetranscribe:   { if let wav = meeting.wavFileURL { Task { await retranscribe(wavURL: wav) } } },
               onGenerateReport: { Task { await generateReport() } },
               onShowCaptureSetup: { showCaptureSetup = true },
               onShowSlides:       { showSlidesList = true },
               onToggleCustomPrompt: { showCustomPrompt.toggle() },
               onImportCalendar:     { showCalendarImporter = true },
               onExportMarkdown: {
                   let md = ExportService().exportMeetingMarkdown(meeting: meeting)
                   let pb = NSPasteboard.general
                   pb.clearContents()
                   pb.setString(md, forType: .string)
               },
               onExportPDF: {
                   let name = "Reunion_\(meeting.date.formatted(.iso8601.year().month().day()))_\(meeting.title).pdf"
                   ExportService().exportMeetingPDF(meeting: meeting, fileName: name)
               },
               onExportMail:       { ExportService().exportMeetingMail(meeting: meeting) },
               onExportEML:        { ExportService().exportMeetingOutlookEML(meeting: meeting) },
               onExportAppleNotes: {
                   let title = meeting.title.isEmpty ? "Réunion" : meeting.title
                   let md = ExportService().exportMeetingMarkdown(meeting: meeting, options: .shareable)
                   ExportService().exportToAppleNotes(title: title, markdownContent: md)
               },
               onSaveNow: saveMeetingNow
           )

           HSplitView {
               mainPanel.frame(minWidth: 520)
               actionsPanel.frame(minWidth: 300, maxWidth: 420)
           }
       }
       .navigationTitle(meeting.title.isEmpty ? "Réunion" : meeting.title)
       .sheet(isPresented: $showCalendarImporter) {
           CalendarEventImportSheet(anchorDate: meeting.date) { event in
               importCalendarEvent(event)
           }
       }
       .popover(isPresented: $showSlidesList) { slidesPopover }
       .popover(isPresented: $showCaptureSetup) {
           ScreenCaptureConfigView(service: captureService, meeting: meeting)
       }
   }
   ```
2. Delete the entire `.toolbar { ToolbarItemGroup(placement: .primaryAction) { … } }` modifier — its items now live in the top chrome `moreMenu`.
3. Remove the `showCaptureSetup` / `showSlidesList` popover attachments that were on specific buttons inside `recorderBar` (they're now attached at the `VStack` level).
4. The `recorderBar` / `sectionPicker` calls in `mainPanel` still exist — they'll be trimmed in next tasks.

- [ ] **Step 4: Build and run**

Run: `swift build -c debug --target OneToOne` then `./run.sh`

Expected: top chrome bar visible at top with breadcrumb, recorder pill, capture button, orange rapport button, ⋯ menu. The native toolbar is empty/minimal. Clicking "Enregistrer" starts recording; pill turns black with timer + pause/stop. Menu ⋯ exposes Export / Prompt / Calendrier / Enregistrer maintenant.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingTopChromeBar.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): top chrome bar replaces toolbar (breadcrumb, pill, capture, rapport, menu)"
```

---

## Task 7: MeetingContextualRecorderBar (replace recorderBar)

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingContextualRecorderBar.swift`
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Create the contextual bar**

Create `OneToOne/Views/Meeting/MeetingContextualRecorderBar.swift`:

```swift
import SwiftUI

struct MeetingContextualRecorderBar: View {
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var captureService: ScreenCaptureService

    let hasWav: Bool
    let showPlayback: Bool
    let onSnapshot: () -> Void
    let onStopCapture: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSkip: (TimeInterval) -> Void

    let errors: [String]
    let onDismissErrors: () -> Void

    var body: some View {
        let visible = recorder.isRecording || (showPlayback && hasWav) || captureService.isCapturing
            || stt.isTranscribing || captureService.ocrProgress != nil || !errors.isEmpty

        if visible {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if recorder.isRecording {
                        recordingSegment
                    } else if showPlayback && hasWav {
                        playbackSegment
                    }

                    if recorder.isRecording || (showPlayback && hasWav), captureService.isCapturing {
                        Divider().frame(height: 20)
                    }

                    if captureService.isCapturing {
                        captureSegment
                    }

                    Spacer()

                    progressSegment
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)

                if !errors.isEmpty {
                    errorBar
                }
            }
            .background(MeetingTheme.surfaceCream)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MeetingTheme.hairline).frame(height: 0.5)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var recordingSegment: some View {
        HStack(spacing: 10) {
            vuMeter
            Text(String(format: "Niveau : %.0f dB", recorder.averagePower))
                .font(MeetingTheme.meta)
                .foregroundColor(.secondary)
        }
    }

    private var vuMeter: some View {
        let level = max(0, min(1, (recorder.averagePower + 60) / 60))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(level > 0.7 ? Color.red : (level > 0.3 ? Color.orange : Color.green))
                    .frame(width: CGFloat(level) * geo.size.width)
            }
        }
        .frame(width: 140, height: 8)
    }

    private var playbackSegment: some View {
        HStack(spacing: 8) {
            Button { onSkip(-15) } label: { Image(systemName: "gobackward.15") }.buttonStyle(.borderless)
            Button { onSkip(15) } label: { Image(systemName: "goforward.15") }.buttonStyle(.borderless)

            if player.duration > 0 {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { onSeek($0) }
                    ),
                    in: 0...max(player.duration, 0.1)
                )
                .frame(minWidth: 160, maxWidth: 360)
            } else {
                Color.clear.frame(width: 160, height: 1)
            }
        }
    }

    private var captureSegment: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder").foregroundColor(.blue)
            Text("Capture : \(captureService.capturedSlidesCount) slides")
                .font(.caption)
            Button(action: onSnapshot) { Image(systemName: "camera.fill") }
                .buttonStyle(.bordered)
                .help("Snapshot manuel")
            Button(action: onStopCapture) { Image(systemName: "stop.fill") }
                .buttonStyle(.bordered)
                .help("Arrêter la capture")
        }
    }

    @ViewBuilder
    private var progressSegment: some View {
        HStack(spacing: 10) {
            if stt.isTranscribing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("STT…").font(.caption.monospacedDigit())
                }
            }
            if let p = captureService.ocrProgress {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("OCR \(p.current)/\(p.total)").font(.caption.monospacedDigit())
                }
            }
        }
    }

    private var errorBar: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, msg in
                    Text(msg).font(.caption).foregroundColor(.red)
                }
            }
            Spacer()
            Button(action: onDismissErrors) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Wire into MeetingView, remove old recorderBar**

In `OneToOne/Views/MeetingView.swift`:

1. Add state for showing playback controls:
   ```swift
   @State private var showPlayback: Bool = false
   ```
2. Modify `onTogglePlay` closure inside `MeetingTopChromeBar` construction so it also flips `showPlayback = true` on play:
   ```swift
   onTogglePlay: {
       if let wav = meeting.wavFileURL {
           togglePlay(url: wav)
           showPlayback = true
       }
   }
   ```
3. In `body`, between `MeetingTopChromeBar(...)` and `HSplitView`, insert:
   ```swift
   MeetingContextualRecorderBar(
       recorder: recorder,
       stt: stt,
       player: player,
       captureService: captureService,
       hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
       showPlayback: showPlayback,
       onSnapshot: { captureService.snapshot() },
       onStopCapture: { Task { await captureService.stop() } },
       onSeek: { player.seek(to: $0) },
       onSkip: { player.skip(by: $0) },
       errors: [
           recorder.lastError,
           transcribeError,
           reportError,
           captureService.lastError,
           attachmentError,
           calendarImportError
       ].compactMap { $0 }.filter { !$0.isEmpty },
       onDismissErrors: {
           recorder.lastError = nil
           transcribeError = nil
           reportError = nil
           captureService.lastError = nil
           attachmentError = nil
           calendarImportError = nil
       }
   )
   .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
   .animation(.easeInOut(duration: 0.15), value: captureService.isCapturing)
   .animation(.easeInOut(duration: 0.15), value: showPlayback)
   ```
4. In `mainPanel`, remove `recorderBar` call and the surrounding `Divider()` / hairline `Rectangle`.
5. Delete `private var recorderBar: some View { … }` block (the `MARK: - Recorder bar` section).
6. Delete `private func playerControls(wavURL:)` block (now unused).
7. Delete `private var vuMeter: some View` block (now inside MeetingContextualRecorderBar).

- [ ] **Step 4: Build and run**

Run: `swift build -c debug --target OneToOne` then `./run.sh`

Expected:
- Start recording → top chrome pill goes black with timer; contextual bar slides in below with VU meter + level dB.
- Stop → WAV created; clicking pill toggles play → contextual bar shows playback controls (slider + skip buttons). Top chrome pill displays play state + current time.
- Start capture → contextual bar shows snapshot / stop capture buttons.
- STT running → progress spinner on the right.
- Trigger an error (invalid audio) → red band appears at bottom of contextual bar, `×` dismisses.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingContextualRecorderBar.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): contextual recorder bar (VU/playback/capture/progress/errors)"
```

---

## Task 8: MeetingActionsSidebar (collapsible)

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Create the sidebar**

Create `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`:

```swift
import SwiftUI
import SwiftData

struct MeetingActionsSidebar: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let currentSlides: [SlideCapture]

    @Binding var collapsed: Bool
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?

    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void
    let saveContext: () -> Void

    var body: some View {
        if collapsed {
            collapsedRail
        } else {
            expandedPanel
        }
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tasksList
            formSection
            Divider()
            capturePreviewCard
        }
        .frame(minWidth: 300, maxWidth: 440)
        .background(MeetingTheme.surfaceCream)
    }

    private var header: some View {
        HStack {
            Text("ACTIONS")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)
            let openCount = meeting.tasks.filter { !$0.isCompleted }.count
            if openCount > 0 {
                Text("\(openCount)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(MeetingTheme.accentOrange))
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = true }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Replier le panneau")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var tasksList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(meeting.tasks) { task in
                    taskRow(task)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func taskRow(_ task: ActionTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { onToggleTaskCompletion(task) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                EditableTextField(placeholder: "Action…", text: Bindable(task).title)
                    .strikethrough(task.isCompleted)
                    .frame(height: 22)

                Spacer()
                Menu {
                    Button(role: .destructive) { onDeleteTask(task) } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 10) {
                if let c = task.collaborator {
                    HStack(spacing: 4) {
                        AvatarMini(collaborator: c, tint: settings.meetingParticipantColor)
                        Text(c.name).font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text("Non assigné").font(.caption).foregroundColor(.secondary)
                }
                Text("·").foregroundColor(.secondary)
                if let dd = task.dueDate {
                    Text(shortDate(dd)).font(MeetingTheme.meta).foregroundColor(.secondary)
                } else {
                    Text("Pas d'échéance").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
    }

    private var formSection: some View {
        VStack(spacing: 8) {
            EditableTextField(placeholder: "Nouvelle action…", text: $newTaskTitle)
                .frame(height: 24)
            HStack(spacing: 8) {
                Picker("Assigné à", selection: $selectedCollaborator) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                }
                .pickerStyle(.menu)
                Toggle(isOn: $showNewTaskDueDate) {
                    Label("Échéance", systemImage: "calendar").font(.caption)
                }
                .toggleStyle(.checkbox)
                if showNewTaskDueDate {
                    DatePicker("", selection: Binding(
                        get: { newTaskDueDate ?? Date() },
                        set: { newTaskDueDate = $0 }
                    ), displayedComponents: .date).labelsHidden()
                }
            }
            Button(action: onAddTask) {
                Label("Ajouter l'action", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MeetingTheme.accentOrange)
            .disabled(newTaskTitle.isEmpty)
        }
        .padding(14)
        .background(MeetingTheme.canvasCream)
    }

    @ViewBuilder
    private var capturePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            if let latest = currentSlides.last,
               let image = NSImage(contentsOfFile: latest.imagePath) {
                Button(action: onShowSlides) {
                    ZStack(alignment: .bottomLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Slide \(latest.index)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                            Text(latest.capturedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(MeetingTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onShowCaptureSetup) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Aucune capture")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    // MARK: - Collapsed rail

    private var collapsedRail: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = false }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .help("Déplier le panneau")

            let openCount = meeting.tasks.filter { !$0.isCompleted }.count
            if openCount > 0 {
                ZStack {
                    Circle().fill(MeetingTheme.accentOrange)
                    Text("\(openCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                }
                .frame(width: 22, height: 22)
                .help(openTasksTooltip)
            }

            Image(systemName: "checkmark.circle")
                .foregroundColor(.secondary)

            Spacer()

            if !currentSlides.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { collapsed = false }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "camera.viewfinder").foregroundColor(.secondary)
                        Text("\(currentSlides.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 8, y: -4)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(MeetingTheme.surfaceCream)
        .overlay(alignment: .leading) {
            Rectangle().fill(MeetingTheme.hairline).frame(width: 0.5)
        }
    }

    private var openTasksTooltip: String {
        meeting.tasks
            .filter { !$0.isCompleted }
            .prefix(3)
            .map { String($0.title.prefix(40)) }
            .joined(separator: "\n")
    }

    private func shortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        return df.string(from: d)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success.

- [ ] **Step 3: Wire into MeetingView, remove old actionsPanel**

In `OneToOne/Views/MeetingView.swift`:

1. Add state:
   ```swift
   @SceneStorage("meeting.actionsCollapsed") private var actionsCollapsed: Bool = false
   ```
2. In `body`, replace the right side of `HSplitView` from:
   ```swift
   actionsPanel.frame(minWidth: 300, maxWidth: 420)
   ```
   to:
   ```swift
   MeetingActionsSidebar(
       meeting: meeting,
       settings: settings,
       allCollaborators: allCollaborators,
       currentSlides: currentSlides,
       collapsed: $actionsCollapsed,
       newTaskTitle: $newTaskTitle,
       selectedCollaborator: $selectedCollaborator,
       showNewTaskDueDate: $showNewTaskDueDate,
       newTaskDueDate: $newTaskDueDate,
       onAddTask: addTask,
       onDeleteTask: { task in
           context.delete(task)
           saveContext()
       },
       onToggleTaskCompletion: { task in
           task.isCompleted.toggle()
           saveContext()
       },
       onShowSlides:       { showSlidesList = true },
       onShowCaptureSetup: { showCaptureSetup = true },
       saveContext: saveContext
   )
   .frame(minWidth: actionsCollapsed ? 44 : 300, maxWidth: actionsCollapsed ? 44 : 440)
   ```
3. Delete `private var actionsPanel: some View { … }` block.
4. Delete `private var capturePreviewPanel: some View { … }` block.
5. Delete `private func taskRow(_ task: ActionTask)` block.
6. Delete `private func deleteTasks(offsets:)` (no longer called — deletions now go via the menu closure).
7. Delete `private var latestCaptureThumbnail` block (moved into sidebar + top chrome badge).

Note: `addTask()`, `saveContext()`, `showSlidesList`/`showCaptureSetup` popovers stay — already set up in Task 6.

- [ ] **Step 4: Build and run**

Run: `swift build -c debug --target OneToOne` then `./run.sh`

Expected: the right panel now shows the new styled sidebar: ACTIONS header with count, task cards with avatar + date, sticky form, capture preview card at the bottom. Clicking `sidebar.right` button collapses to a 44pt rail with expand button + task count badge + capture icon. Clicking expand restores.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingActionsSidebar.swift \
        OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): collapsible actions sidebar with capture preview card"
```

---

## Task 9: Final cleanup + serif body typography + manual verification

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Remove any remaining dead code and imports**

Open `OneToOne/Views/MeetingView.swift`. Verify:
- No reference to `header`, `recorderBar`, `sectionPicker`, `actionsPanel`, `capturePreviewPanel`, `playerControls`, `vuMeter`, `latestCaptureThumbnail`, `taskRow`, `deleteTasks`, `participantsSection`, `collaboratorChipColor`.
- `slidesPopover` is still used (attached to `showSlidesList` popover in body).
- `attachmentRow`, `transcriptView`, `reportView`, `documentsView`, `section(_:_:)`, `handleFileDrop`, `icon(for:)`, `importDocuments`, and all async recording/report functions remain.
- `mainPanel` is now:
  ```swift
  private var mainPanel: some View {
      VStack(alignment: .leading, spacing: 0) {
          MeetingHeaderEditorial(
              meeting: meeting,
              settings: settings,
              detailsExpanded: $detailsExpanded
          )
          MeetingDetailsBlock(
              meeting: meeting,
              settings: settings,
              allCollaborators: allCollaborators,
              availableCollaborators: availableCollaborators,
              projects: projects,
              expanded: $detailsExpanded,
              showCustomPrompt: $showCustomPrompt,
              newAdhocName: $newAdhocName,
              calendarImportError: $calendarImportError,
              addParticipant: addParticipant,
              removeParticipant: removeParticipant,
              setParticipantStatus: setParticipantStatus,
              participantStatus: participantStatus,
              addAdhoc: addAdhocParticipant,
              saveContext: saveContext
          )
          MeetingTabsUnderline(
              selection: $activeSection,
              attachmentsCount: meeting.attachments.count,
              hasReport: !meeting.summary.isEmpty
          )
          sectionContent
              .padding(.horizontal, 28)
              .padding(.top, 12)
              .padding(.bottom, 16)
      }
      .background(MeetingTheme.canvasCream)
  }
  ```

- [ ] **Step 2: Apply serif to body content**

In `OneToOne/Views/MeetingView.swift`:

1. In `transcriptView`, change `Text(meeting.mergedTranscript)` and `Text(meeting.rawTranscript)` to use `.font(MeetingTheme.bodySerif)` instead of `.body`.
2. In `reportView`, change `Text(meeting.summary)` to `.font(MeetingTheme.bodySerif)`.
3. In `section(_:_:)`, leave the title font as `.headline` (non-serif), keep items as-is.
4. Do NOT change `documentsView` or `attachmentRow` — they stay with system font (they display filenames + meta, serif would hurt readability).

- [ ] **Step 3: Build**

Run: `swift build -c debug --target OneToOne`

Expected: success, no new warnings.

- [ ] **Step 4: Check line count**

Run: `wc -l OneToOne/Views/MeetingView.swift`

Expected: under 450 lines (target was ~350; +100 acceptable slack). If over 600, look for duplicated logic.

- [ ] **Step 5: Manual smoke test (golden path)**

Run: `./run.sh`

Test sequence — run through every item and confirm no regression:

1. **Create a new meeting** from the sidebar. Verify: editorial header with placeholder title, `Détails` block open, no badge (no project), kind label `RÉUNION`.
2. **Type a title**, set kind to `1:1`, pick a collaborator as participant. Verify: title wraps at 2 lines, kind label becomes `1:1 · NAME`, avatar stack shows 1 circle.
3. **Switch to `Projet`** kind, pick a project. Verify: badge with project code appears, kind label becomes `COPIL · PROJET`, breadcrumb shows `One2One › Projets › [project]`.
4. **Open `Détails` → add 2 more participants**. Verify: avatar stack shows 3 circles, participant count = 3. Collapse and re-open `Détails`: state persists during session.
5. **Click `Enregistrer`**. Verify: top chrome pill turns black with timer; contextual bar slides in with VU meter. Pause + resume. Stop. Transcription kicks off.
6. **After transcription**: pill shows play button + times. Click play → contextual bar shows seek + slider. Seek +15s, -15s. Pause.
7. **Click `Capture`** → capture setup popover opens. Start a capture session. Verify: button becomes blue `● N slides` pill; contextual bar shows snapshot + stop. Click snapshot 2 times → N increments. Stop capture. Capture button shows `Capture` with red `2` badge.
8. **Open Rapport tab via underline tabs**. Verify: tab underline animates. Click `Rapport` button in top chrome. Verify: spinner, then sections populated (Résumé, Points clés, etc.).
9. **Documents tab**: badge `(N)` shows if attachments exist. Import a PDF via drag-drop. Verify: imports, appears in list.
10. **Actions sidebar**: add 3 tasks with different assignees and dates. Check one. Verify: strikethrough. Click `sidebar.right` → sidebar collapses to 44pt rail, red badge `2` shows open count. Hover badge: tooltip lists open tasks. Click expand → sidebar restores.
11. **Capture preview card** (bottom of sidebar): shows latest slide thumbnail. Click → slides popover opens.
12. **Menu ⋯** (top chrome): run each item: Copier Markdown (verify clipboard), Exporter PDF (save dialog), Envoyer par mail, etc. Prompt spécifique toggle → TextEditor appears in Détails block.
13. **Trigger an error** (e.g., start recording without mic permission, or stop instantly < 1s). Verify: red error band appears at bottom of contextual bar; × dismisses.
14. **Navigate away** (click sidebar other meeting) and back. Verify: `actionsCollapsed` and `detailsExpanded` persist (global, not per-meeting, in phase 1).

If any step fails, note the issue but **do not fix in this task** — open a follow-up issue or, if trivial, fix + separate commit.

- [ ] **Step 6: Final commit (dead code sweep)**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "refactor(meeting): sweep dead code, apply serif body typography"
```

- [ ] **Step 7: Verify branch state**

```bash
git log --oneline -10
wc -l OneToOne/Views/MeetingView.swift
ls OneToOne/Views/Meeting/
```

Expected: 9+ new commits, MeetingView.swift under 450 lines, 8 files in `Meeting/` directory.

---

## Self-Review Check

**Spec coverage** (mapping each design section to a task):
- §3 squelette → Task 1-9 collectively.
- §3.1 TopChromeBar → Task 6.
- §3.2 ContextualRecorderBar → Task 7.
- §3.3 HeaderEditorial → Task 3.
- §3.4 DetailsBlock → Task 4.
- §3.5 TabsUnderline → Task 5.
- §3.6 AvatarStack → Task 2.
- §3.7 ActionsSidebar → Task 8.
- §4 Theme → Task 1.
- §5 Fichiers → all tasks produce expected files.
- §6 Migration order → matches task order 1-9.
- §7 Risques — `sortIndex` explicitly deferred (plan non-goal stated in header); HSplitView 44pt fallback handled by `.frame(minWidth:maxWidth:)` on the sidebar (not HSplitView internal); breadcrumb navigation deferred to visual only (no routing); SceneStorage per-meeting downgraded to global in phase 1 (documented in Task 4 Step 3).
- §9 Definition de terminé → Task 9 Step 4 + 5 cover line count + smoke test.

**Placeholder scan**: no `TODO`, `TBD`, "handle edge cases", "similar to task N", or "write tests for the above" without code. Every code step has a full code block.

**Type consistency**: verified that `MeetingView.MeetingSection` is referenced from `MeetingTabsUnderline` — this requires the enum to stay `public`/internal inside `MeetingView`. It is declared as `enum MeetingSection: String, CaseIterable, Identifiable` inside `MeetingView` struct (line 42), internal access by default — cross-file same-module access works. OK.

`SlideCapture` used in `MeetingActionsSidebar.currentSlides` — verified: existing type from `MeetingModels.swift`/captureService. OK.

`Project.code` used in TopChromeBar — verified: existing field on `Project` (referenced in existing header code at line 146).

`MeetingKind.sfSymbol`, `MeetingKind.label`, `MeetingAttendanceStatus.sfSymbol`, `MeetingAttendanceStatus.label` — all existing (referenced in current code).

`player.skip(by:)`, `player.seek(to:)`, `player.currentTime`, `player.duration`, `player.isPlaying`, `player.loadedURL`, `player.toggle()`, `player.load(url:)` — all existing (current playerControls uses them).

`recorder.elapsedSeconds`, `recorder.averagePower`, `recorder.isRecording`, `recorder.isPaused`, `recorder.lastError`, `recorder.start()`, `recorder.stop()`, `recorder.pause()`, `recorder.resume()` — all existing.

`captureService.isCapturing`, `captureService.capturedSlidesCount`, `captureService.snapshot()`, `captureService.stop()`, `captureService.ocrProgress`, `captureService.lastError`, `captureService.currentAttachment` — all existing.

`Meeting.wavFileURL`, `Meeting.rawTranscript`, `Meeting.mergedTranscript`, `Meeting.summary`, `Meeting.durationSeconds`, `Meeting.title`, `Meeting.date`, `Meeting.kind`, `Meeting.project`, `Meeting.participants`, `Meeting.tasks`, `Meeting.attachments`, `Meeting.calendarEventTitle`, `Meeting.customPrompt`, `Meeting.highlights`, `Meeting.keyPoints`, `Meeting.decisions`, `Meeting.openQuestions`, `Meeting.persistentModelID` — all existing.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-24-meeting-view-redesign.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
