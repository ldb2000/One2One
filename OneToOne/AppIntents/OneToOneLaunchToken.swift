import Foundation

/// Token transmis comme valeur de `WindowGroup(for: OneToOneLaunchToken.self)`
/// — `Codable` + `Hashable` requis par SwiftUI WindowGroup.
struct OneToOneLaunchToken: Codable, Hashable {
    /// `Meeting.stableID` du meeting à présenter.
    let meetingID: UUID
    /// Si vrai, démarre l'enregistrement à `onAppear`.
    let autoStartRecording: Bool
}
