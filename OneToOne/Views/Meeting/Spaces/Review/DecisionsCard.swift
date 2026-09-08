import SwiftUI
import SwiftData

/// La carte `DÉCISIONS PRISES · n` du poste de pilotage (spec §2.7, capture
/// `1c-poste-de-pilotage.png` : `11:03 Le partenaire finalise la migration —
/// Olivier Freund`).
///
/// La source est `MeetingNote(kind: .decision)` et non `Meeting.decisions` : ce
/// sont les notes qui portent le **timecode**, et un timecode est ce qui rend
/// une décision vérifiable — on reclique dessus et on entend la phrase. La
/// liste JSON du rapport reste lue par les gabarits et les exports ; elle sert
/// ici de repli quand aucune note horodatée n'existe (réunion importée,
/// décisions extraites par le LLM sans axe temps).
struct DecisionsCard: View {

    /// Une ligne de la carte : timecode, texte, et le porteur détaché quand la
    /// phrase le nomme en fin.
    struct Ligne: Identifiable, Equatable {
        var id: String
        /// `nil` quand la décision vient de `Meeting.decisions` : pas d'axe
        /// temps, donc pas de timecode cliquable.
        var t: Double?
        var texte: String
        var porteur: String?
    }

    /// Les décisions de la réunion, triées par timecode croissant.
    @MainActor
    static func lignes(for meeting: Meeting) -> [Ligne] {
        let notes = meeting.timedNotes
            .filter { $0.kind == .decision }
            .sorted { ($0.t, $0.orderIndex) < ($1.t, $1.orderIndex) }
        if !notes.isEmpty {
            return notes.map { note in
                let (texte, porteur) = separerPorteur(note.text)
                return Ligne(id: note.ensuredStableID.uuidString,
                             t: note.t,
                             texte: texte,
                             porteur: porteur)
            }
        }
        // Repli : les décisions du rapport, sans timecode.
        return meeting.decisions.enumerated().map { index, texte in
            let (corps, porteur) = separerPorteur(texte)
            return Ligne(id: "rapport-\(index)", t: nil, texte: corps, porteur: porteur)
        }
    }

    /// Détache le porteur nommé en fin de phrase : `… — Olivier Freund` ou
    /// `… (Olivier Freund).`
    ///
    /// Deux formes parce que les deux existent dans les données : le rapport
    /// écrit la parenthèse, une note prise en séance écrit le tiret. Trois
    /// garde-fous, sans quoi la moitié des décisions perdraient leur fin de
    /// phrase :
    ///
    /// - le tiret doit être **le dernier** de la phrase et suivi d'au plus
    ///   quatre mots (« — reste à chiffrer la fin Marine » n'est pas un nom) ;
    /// - le premier mot du segment doit commencer par une **majuscule** (« — à
    ///   confirmer » n'est pas un nom) ;
    /// - le segment ne doit porter aucune ponctuation interne (« — Olivier
    ///   Freund, sous réserve » est une réserve, pas un porteur).
    static func separerPorteur(_ texte: String) -> (texte: String, porteur: String?) {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)

        // Forme parenthésée, en fin de phrase, point final toléré.
        var sansPointFinal = propre
        var pointFinal = ""
        if sansPointFinal.hasSuffix(".") {
            pointFinal = "."
            sansPointFinal.removeLast()
        }
        if sansPointFinal.hasSuffix(")"),
           let ouvrante = sansPointFinal.lastIndex(of: "(") {
            let candidat = String(sansPointFinal[sansPointFinal.index(after: ouvrante)...].dropLast())
            if let nom = nomValide(candidat) {
                let corps = String(sansPointFinal[..<ouvrante])
                    .trimmingCharacters(in: .whitespaces)
                return (texte: corps + pointFinal, porteur: nom)
            }
        }

        // Forme au tiret cadratin (ou demi-cadratin).
        for tiret in ["—", "–"] {
            guard let separateur = propre.range(of: " \(tiret) ", options: .backwards) else { continue }
            let candidat = String(propre[separateur.upperBound...])
            guard let nom = nomValide(candidat) else { continue }
            let corps = String(propre[..<separateur.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            guard !corps.isEmpty else { continue }
            return (texte: corps, porteur: nom)
        }

        return (texte: propre, porteur: nil)
    }

    /// Le candidat est-il un nom de personne ? `nil` sinon.
    private static func nomValide(_ candidat: String) -> String? {
        var nom = candidat.trimmingCharacters(in: .whitespacesAndNewlines)
        if nom.hasSuffix(".") { nom.removeLast() }
        nom = nom.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return nil }
        // Aucune ponctuation interne : une réserve n'est pas un porteur.
        guard nom.rangeOfCharacter(from: CharacterSet(charactersIn: ",;:.!?()")) == nil else {
            return nil
        }
        let mots = nom.split(separator: " ")
        guard (1...4).contains(mots.count) else { return nil }
        guard let premiere = mots.first?.first, premiere.isUppercase else { return nil }
        return nom
    }

    // MARK: - Entrées

    let meeting: Meeting
    /// Replace la tête de lecture sur le timecode d'une décision. `nil` = pas
    /// d'axe temps.
    let onSeek: ((Double) -> Void)?

    var body: some View {
        ReviewCard {
            let lignes = Self.lignes(for: meeting)
            HStack(spacing: 7) {
                SectionLabel("décisions prises")
                MonoMeta("· \(lignes.count)", emphase: !lignes.isEmpty)
                Spacer(minLength: 0)
            }
            if lignes.isEmpty {
                MeetingEmptyInvite(
                    titre: "Aucune décision consignée",
                    invite: "Tapez /décision dans les notes pendant la séance : la ligne se pose au timecode et se reclique ici."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                        self.ligne(ligne)
                        if index < lignes.count - 1 {
                            Rectangle().fill(One2OneToken.hair).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func ligne(_ ligne: Ligne) -> some View {
        HStack(alignment: .top, spacing: 9) {
            timecode(ligne)
            Text(ligne.texte)
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let porteur = ligne.porteur {
                Text("— \(porteur)")
                    .font(.plexSans(12.5))
                    .foregroundStyle(One2OneToken.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, One2OneToken.tableRowPaddingV)
    }

    /// Le timecode, cliquable quand il y en a un. `--:--` sinon : la décision
    /// vient du rapport et n'a pas d'ancre — le dire vaut mieux que la dater à
    /// `00:00`, instant où rien ne s'est passé.
    @ViewBuilder
    private func timecode(_ ligne: Ligne) -> some View {
        if let t = ligne.t, let onSeek {
            Button { onSeek(t) } label: {
                TimecodeLabel(seconds: t, teinte: One2OneToken.report)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Replacer la lecture sur cette décision")
        } else {
            Text(ligne.t == nil ? "--:--" : TimecodeLabel.format(ligne.t ?? 0))
                .font(.plexMono(10, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.ink4)
                .frame(width: TimecodeLabel.width, alignment: .leading)
        }
    }
}
