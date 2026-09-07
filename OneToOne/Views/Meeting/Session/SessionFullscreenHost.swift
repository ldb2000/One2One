import SwiftUI
import AppKit

/// Ce que la **racine d'une fenêtre** monte (spec §2.6, correctif du
/// 2026-09-08).
///
/// Deux cas, et un seul critère : l'état du mode séance publié par l'écran
/// (`screen.session`). Le plein écran d'AppKit n'entre pas dans la décision —
/// il est la conséquence du mode, pas sa cause. Le lot 4 les avait confondus :
/// il demandait `toggleFullScreen` **et** substituait le `contentView` de la
/// fenêtre, or cette substitution détache la vue qui l'avait commandée et
/// annule aussitôt la présentation. La fenêtre partait donc en plein écran sur
/// le cockpit clair, et l'écran 1b n'a jamais été vu (recette du 2026-09-07,
/// écart n° 1).
///
/// Pur et testable exprès : c'est la seule règle du correctif, et un test la
/// vérifie sans fenêtre ni AppKit (`SessionFullscreenRootTests`).
enum SessionFullscreenRoot: Equatable, Sendable {
    /// La fenêtre ordinaire : barre du haut, barre d'espaces, cockpit.
    case fenetre
    /// Le mode séance, plein cadre, à la place de tout le reste.
    case seance

    /// La racine, décidée par le seul état du mode.
    static func pour(seanceAffichee: Bool) -> SessionFullscreenRoot {
        seanceAffichee ? .seance : .fenetre
    }
}

/// Monte le mode séance à la racine d'une fenêtre, par-dessus son contenu.
private struct SessionFullscreenHostModifier: ViewModifier {

    @State private var fenetre: NSWindow?
    private var presentateur: SessionFullscreenPresenter { .shared }

    /// La séance publiée est-elle celle de **cette** fenêtre ? Deux fenêtres
    /// réunion peuvent être ouvertes ; la racine de l'autre ne monte rien.
    private var racine: SessionFullscreenRoot {
        .pour(seanceAffichee: presentateur.estAffiche(dans: fenetre))
    }

    /// `ZStack` et non `if/else` : démonter le contenu de la fenêtre
    /// détruirait le `@State` de `MeetingView` — dont le `MeetingScreenModel`
    /// que le mode séance est justement en train de lire — et ferait partir le
    /// `onDisappear` de `MeetingSpaceView`, qui referme le mode. Le contenu
    /// reste donc monté, entièrement recouvert par la surface opaque du mode
    /// (`dark/base`), et retiré de l'arbre d'accessibilité : « aucun chrome »
    /// (spec §2.6) vaut aussi pour VoiceOver, et c'est ce que la recette
    /// vérifie.
    func body(content: Content) -> some View {
        ZStack {
            content
                .accessibilityHidden(racine == .seance)
            if racine == .seance, let vue = presentateur.vue {
                vue()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SessionWindowReader { fenetre = $0 })
    }
}

extension View {
    /// Réserve la racine de cette fenêtre au mode séance quand un écran le
    /// demande (spec §2.6).
    ///
    /// Posé sur le contenu de chaque scène qui peut afficher une réunion — la
    /// fenêtre principale et la fenêtre dédiée `1to1-meeting`. C'est le
    /// **repli** que le lot 4 n'avait pas : sans une racine qui sache monter le
    /// mode, la demande de plein écran n'a nulle part où l'afficher.
    func sessionFullscreenHost() -> some View {
        modifier(SessionFullscreenHostModifier())
    }
}
