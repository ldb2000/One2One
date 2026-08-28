import Foundation

/// Token transmis comme valeur de `WindowGroup(for: OneToOneLaunchToken.self)`
/// — `Codable` + `Hashable` requis par SwiftUI WindowGroup.
///
/// L'identité d'une fenêtre est la réunion, pas ses options de lancement :
/// SwiftUI déduplique les fenêtres par égalité de valeur, et deux tokens
/// pour la même réunion doivent donc être égaux quel que soit
/// `autoStartRecording`. Sinon, ouvrir une réunion déjà à l'écran avec
/// d'autres options crée une seconde fenêtre au lieu de rappeler la première.
struct OneToOneLaunchToken: Codable, Hashable {
    /// `Meeting.stableID` du meeting à présenter.
    let meetingID: UUID
    /// Si vrai, démarre l'enregistrement à `onAppear`. Ne participe ni à
    /// l'égalité ni au hachage — voir ci-dessus.
    let autoStartRecording: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.meetingID == rhs.meetingID }
    func hash(into hasher: inout Hasher) { hasher.combine(meetingID) }
}
