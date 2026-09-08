import SwiftUI
import SwiftData

/// Métadonnées de matching de locuteur pour un cluster, décodées depuis
/// `meeting.speakerMatchMetaJSON` (confiance, assignation automatique,
/// ambiguïté, candidats par `stableID`).
///
/// Déplacé de `MeetingView.swift` au lot 2 avec le badge qui le lit : le
/// programme §2.4 impose que les lots suivants n'ajoutent **rien** à ce fichier
/// et en retirent l'orchestration d'affichage.
struct SpeakerMeta {
    let confidence: Double
    let auto: Bool
    let ambiguous: Bool
    let candidateStableIDs: [String]

    static func parse(json: String, clusterID: Int) -> SpeakerMeta? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = dict[String(clusterID)] as? [String: Any] else {
            return nil
        }
        return SpeakerMeta(
            confidence: (entry["confidence"] as? Double) ?? 0,
            auto: (entry["auto"] as? Bool) ?? false,
            ambiguous: (entry["ambiguous"] as? Bool) ?? false,
            candidateStableIDs: (entry["candidates"] as? [String]) ?? []
        )
    }
}

/// Les gestes de locuteur de la colonne de transcription : couleur de cluster,
/// assignation d'un cluster à un participant, acceptation ou refus d'une
/// suggestion.
///
/// L'orchestration lourde — diarisation VAD, ré-identification — **reste** dans
/// `MeetingView` : c'est elle qui possède les tâches longues, les phases et les
/// files de travail. Ici, seuls les gestes déclenchés depuis un segment.
@MainActor
enum TranscriptSpeakerTools {

    /// Palette stable par `speakerID`. `0` = non assigné, en gris.
    static func speakerColor(_ id: Int) -> Color {
        guard id > 0 else { return One2OneToken.ink4 }
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .brown]
        return palette[(id - 1) % palette.count]
    }

    /// Premier candidat résoluble parmi des `stableID` proposés.
    static func firstCandidate(stableIDs: [String],
                               among collaborators: [Collaborator]) -> Collaborator? {
        guard let premier = stableIDs.first, let uuid = UUID(uuidString: premier) else { return nil }
        return collaborators.first { $0.stableID == uuid }
    }

    /// Assigne **tous** les segments d'un `speakerID` à un collaborateur,
    /// persiste le mapping dans `speakerAssignmentsJSON` et applique la mise à
    /// jour EMA du voiceprint si un embedding frais est en cache pour ce
    /// cluster.
    ///
    /// Le cache d'embeddings vient de `MeetingScreenModel` : il vivait en
    /// `@State` de `MeetingView`, entre la diarisation qui le remplit et ce
    /// geste qui le consomme. Le geste ayant déménagé, le cache a suivi là où
    /// les deux le voient.
    static func assignSpeaker(speakerID: Int,
                              to collaborator: Collaborator,
                              in meeting: Meeting,
                              embeddings: [Int: [Float]],
                              context: ModelContext) {
        for segment in meeting.transcriptSegments where segment.speakerID == speakerID {
            segment.speaker = collaborator
        }
        let clusterID = speakerID - 1
        var assignments = (try? JSONSerialization.jsonObject(
            with: meeting.speakerAssignmentsJSON.data(using: .utf8) ?? Data()
        ) as? [String: Any]) ?? [:]
        assignments[String(clusterID)] = collaborator.ensuredStableID.uuidString
        if let data = try? JSONSerialization.data(withJSONObject: assignments),
           let json = String(data: data, encoding: .utf8) {
            meeting.speakerAssignmentsJSON = json
        }
        if let embedding = embeddings[clusterID] {
            SpeakerMatcher.applyEMAUpdate(to: collaborator, newEmbedding: embedding, in: context)
        }
        try? context.save()
    }

    /// Refuse la suggestion faite pour le cluster d'un segment : la métadonnée
    /// est retirée, la suggestion ne revient pas.
    static func rejectSuggestion(for segment: TranscriptSegment,
                                 in meeting: Meeting,
                                 context: ModelContext) {
        let clusterID = segment.speakerID - 1
        var meta = (try? JSONSerialization.jsonObject(
            with: meeting.speakerMatchMetaJSON.data(using: .utf8) ?? Data()
        ) as? [String: Any]) ?? [:]
        meta.removeValue(forKey: String(clusterID))
        if let data = try? JSONSerialization.data(withJSONObject: meta),
           let json = String(data: data, encoding: .utf8) {
            meeting.speakerMatchMetaJSON = json
            try? context.save()
        }
    }
}

// MARK: - Badge de locuteur

/// Le badge `Locuteur —` en tête d'un segment : nom résolu, suggestion à
/// accepter ou refuser, ou cluster anonyme cliquable.
///
/// Déplacé de `MeetingView.speakerBadge(for:)`. Le comportement est inchangé —
/// popover de renommage, `✓` vert d'assignation automatique avec sa confiance,
/// menu contextuel de segment ; seule la typographie suit les jetons de la
/// refonte.
struct TranscriptSpeakerBadge: View {

    let segment: TranscriptSegment
    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    /// Menu contextuel du segment, fourni par la colonne (importance,
    /// suppression) : il porte l'état de la colonne, pas celui du badge.
    @ViewBuilder let segmentMenu: () -> AnyView

    @Environment(\.modelContext) private var context
    @State private var isRenaming = false

    private var meta: SpeakerMeta? {
        SpeakerMeta.parse(json: meeting.speakerMatchMetaJSON, clusterID: segment.speakerID - 1)
    }

    var body: some View {
        contenu
            .contextMenu { segmentMenu() }
    }

    @ViewBuilder
    private var contenu: some View {
        if let locuteur = segment.speaker {
            Button { isRenaming = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: meta?.auto == true ? "checkmark.seal.fill" : "person.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(meta?.auto == true
                                         ? One2OneToken.ok
                                         : TranscriptSpeakerTools.speakerColor(segment.speakerID))
                    Text(locuteur.name)
                        .font(.plexSans(11.5, .semibold))
                        .foregroundStyle(One2OneToken.ink1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let m = meta, m.auto {
                        MonoMeta("\(Int(m.confidence * 100))%")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isRenaming) { picker }
        } else if let m = meta,
                  m.confidence >= settings.speakerIdSuggestThreshold,
                  let suggere = TranscriptSpeakerTools.firstCandidate(
                    stableIDs: m.candidateStableIDs, among: allCollaborators) {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(One2OneToken.warn)
                Text("\(suggere.name) ? (\(Int(m.confidence * 100))%)")
                    .font(.plexSans(11.5, .medium))
                    .foregroundStyle(One2OneToken.warnInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    TranscriptSpeakerTools.assignSpeaker(
                        speakerID: segment.speakerID, to: suggere, in: meeting,
                        embeddings: screen.lastDiarizationEmbeddings, context: context)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(One2OneToken.ok)
                }
                .buttonStyle(.plain)
                .help("Accepter la suggestion")
                Button {
                    TranscriptSpeakerTools.rejectSuggestion(for: segment, in: meeting,
                                                            context: context)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(One2OneToken.ink4)
                }
                .buttonStyle(.plain)
                .help("Refuser la suggestion")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(One2OneToken.warnBg))
        } else {
            Button { isRenaming = true } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(TranscriptSpeakerTools.speakerColor(segment.speakerID))
                        .frame(width: 7, height: 7)
                    Text(segment.displayLabel)
                        .font(.plexSans(11.5, .semibold))
                        .foregroundStyle(TranscriptSpeakerTools.speakerColor(segment.speakerID))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isRenaming) { picker }
            .help("Attribuer ce locuteur à un participant")
        }
    }

    private var picker: some View {
        TranscriptSpeakerPicker(
            speakerID: segment.speakerID,
            meeting: meeting,
            allCollaborators: allCollaborators,
            onAssign: { collaborateur in
                TranscriptSpeakerTools.assignSpeaker(
                    speakerID: segment.speakerID, to: collaborateur, in: meeting,
                    embeddings: screen.lastDiarizationEmbeddings, context: context)
                isRenaming = false
            },
            onCancel: { isRenaming = false }
        )
        .padding(12)
        .frame(minWidth: 240)
    }
}

// MARK: - Sélecteur de participant

/// Le popover « Speaker n → participant ». Déplacé de
/// `MeetingView.speakerRenamePopover(speakerID:)`, comportement inchangé :
/// participants de la réunion d'abord, autres collaborateurs ensuite,
/// recherche insensible à la casse, marque `waveform` si un voiceprint existe.
struct TranscriptSpeakerPicker: View {

    let speakerID: Int
    let meeting: Meeting
    let allCollaborators: [Collaborator]
    let onAssign: (Collaborator) -> Void
    let onCancel: () -> Void

    @State private var recherche = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speaker \(speakerID) → participant")
                .font(.plexSans(11.5, .semibold))
                .foregroundStyle(One2OneToken.ink1)

            EditableTextField(placeholder: "Rechercher…",
                              text: Binding(get: { recherche }, set: { recherche = $0 }))
                .frame(height: 22)

            let participantIDs = Set(meeting.participants.map(\.persistentModelID))
            let requete = recherche.trimmingCharacters(in: .whitespaces)
            let correspond: (Collaborator) -> Bool = { c in
                requete.isEmpty || c.name.localizedCaseInsensitiveContains(requete)
            }
            let participants = meeting.participants
                .filter { !$0.isArchived && correspond($0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let autres = allCollaborators
                .filter { !participantIDs.contains($0.persistentModelID) && correspond($0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if participants.isEmpty && autres.isEmpty {
                Text(requete.isEmpty
                     ? "Aucun collaborateur dans la base."
                     : "Aucun résultat.")
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.inkMuted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if !participants.isEmpty {
                            SectionLabel("participants de la réunion")
                            ForEach(participants, id: \.persistentModelID) { c in
                                rangee(c, dansLaReunion: true)
                            }
                        }
                        if !autres.isEmpty {
                            if !participants.isEmpty { Divider() }
                            SectionLabel("autres collaborateurs")
                            ForEach(autres, id: \.persistentModelID) { c in
                                rangee(c, dansLaReunion: false)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
                Divider()
            }
            Button("Annuler", action: onCancel)
                .buttonStyle(.plain)
                .font(.plexSans(11, .medium))
                .foregroundStyle(One2OneToken.ink3)
        }
        .frame(width: 280)
    }

    private func rangee(_ collaborateur: Collaborator, dansLaReunion: Bool) -> some View {
        Button {
            onAssign(collaborateur)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: dansLaReunion ? "person.fill.checkmark" : "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(dansLaReunion ? One2OneToken.ok : One2OneToken.action)
                Text(collaborateur.name)
                    .font(.plexSans(11.5, dansLaReunion ? .semibold : .regular))
                    .foregroundStyle(One2OneToken.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if collaborateur.voicePrint != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(One2OneToken.ink4)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
