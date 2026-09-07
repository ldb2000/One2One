import Foundation

/// Ce que la section `PIÈCES & CAPTURES` du dock de l'atelier affiche
/// (spec §7.2, capture `6a-atelier-planche.png` : `PDF Archi_cible_Cléva.pdf ·
/// déposé par Yann` puis `TEAMS Capture 21:10 · schéma réseau partagé`).
///
/// Une **extension** de `ResourceItem` (lot 6) plutôt qu'un second modèle : les
/// pièces de séance et les captures ont déjà leur adaptateur commun, et le dock
/// n'a besoin que de trois libellés de plus. Tout est pur — les tests n'ouvrent
/// ni écran ni disque.
@MainActor
extension ResourceItem {

    /// Les lignes de la section, dans l'ordre de la capture : **les pièces
    /// d'abord, les captures ensuite**.
    ///
    /// Pas l'ordre de `ResourceItem.sorted` (épinglées d'abord) : une capture
    /// est épinglée par construction, elle passerait donc systématiquement
    /// devant les pièces, et la section s'appelle « pièces **et** captures ».
    /// Les pièces du projet sont exclues : on n'insère pas sur la planche un
    /// document qui n'appartient pas à la séance. Un lien non plus — il n'y a
    /// pas d'image à poser.
    static func workshopRows(for meeting: Meeting) -> [ResourceItem] {
        let lignes = all(for: meeting).filter { ligne in
            ligne.scope == .meeting && ligne.nature != .lien
        }
        let pieces = sorted(lignes.filter { $0.nature != .capture })
        let captures = lignes.filter { $0.nature == .capture }
            .sorted { ($0.pinnedAtT ?? 0) < ($1.pinnedAtT ?? 0) }
        return pieces + captures
    }

    /// Le titre affiché. Une capture porte son instant, pas son nom de
    /// fichier : `Capture 21:10` dit quelque chose, `capture-003.png` non.
    func workshopTitle() -> String {
        guard nature == .capture else { return name }
        guard let t = pinnedAtT else { return "Capture" }
        return "Capture \(MeetingPlayhead.mmss(t))"
    }

    /// Le badge de l'icône. Une capture d'un partage Teams ou Zoom porte le nom
    /// de l'outil (capture 6a : `TEAMS`) : c'est ce qui la distingue d'une
    /// copie d'écran quelconque.
    func workshopBadge(in meeting: Meeting) -> String {
        guard nature == .capture, let capture = slideCapture(in: meeting) else { return badge }
        switch capture.source {
        case .teams:  return "TEAMS"
        case .zoom:   return "ZOOM"
        case .screen, .region: return badge
        }
    }

    /// La deuxième ligne : qui l'a déposée, ou ce que la capture montre.
    func workshopSubtitle(in meeting: Meeting) -> String {
        if nature == .capture {
            let description = slideCapture(in: meeting)?.ocrText
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return description.isEmpty ? "capture d'écran de la séance" : description
        }
        return addedByName.isEmpty ? "déposé dans la séance" : "déposé par \(addedByName)"
    }

    /// Insérable sur la planche : il faut une image à poser, donc un fichier
    /// présent. Un lien n'en a pas, un fichier disparu non plus.
    var isBoardInsertable: Bool {
        nature != .lien && !isOrphan && !path.isEmpty
    }

    /// La capture d'origine, quand la ligne en est une.
    private func slideCapture(in meeting: Meeting) -> SlideCapture? {
        guard case .captureDeSeance(let identifiant) = origin else { return nil }
        return meeting.attachments.flatMap(\.slides).first { $0.id == identifiant }
    }
}
