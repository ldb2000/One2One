import SwiftUI

/// La pastille d'avatar du domaine 1:1 : `LN`, `YP`.
///
/// Deux tailles seulement, celles des captures : **16 px** devant un sujet
/// d'ordre du jour ou une carte d'engagement, **34 px** en tête de la carte
/// personne (spec §3.3). La couleur vient d'`AvatarPalette`, donc la même
/// personne garde la même teinte partout dans l'application — y compris entre
/// deux lancements (le hachage y est calculé à la main pour cette raison).
///
/// Partagé (`Shared/`) : les quatre captures 1:1 en portent.
struct AvatarSide: View {

    /// Diamètre d'un avatar devant une ligne (ordre du jour, engagement).
    static let inline: CGFloat = 16
    /// Diamètre de l'avatar de la carte personne.
    static let large: CGFloat = 34

    let initials: String
    /// L'identité qui choisit la couleur — le nom complet, jamais les
    /// initiales : deux personnes aux mêmes initiales doivent se distinguer.
    let identity: String
    var diametre: CGFloat = Self.inline
    /// Bulle d'aide, quand la pastille est le seul endroit qui nomme la
    /// personne.
    var aide: String?

    var body: some View {
        let paire = AvatarPalette.pair(for: identity)
        Text(initials)
            .font(.plexSans(diametre <= Self.inline ? 8 : 12.5, .semibold))
            .foregroundStyle(paire.texte)
            .frame(width: diametre, height: diametre)
            .background(Circle().fill(paire.fond))
            .help(aide ?? identity)
    }
}

#Preview("AvatarSide") {
    HStack(spacing: 10) {
        AvatarSide(initials: "LN", identity: "Laurent NOMINÉ")
        AvatarSide(initials: "YP", identity: "Yann PENVEN")
        AvatarSide(initials: "LN", identity: "Laurent NOMINÉ", diametre: AvatarSide.large)
    }
    .padding(20)
    .background(One2OneToken.surface)
}
