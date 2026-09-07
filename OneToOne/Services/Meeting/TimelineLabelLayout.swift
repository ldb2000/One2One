import CoreGraphics
import Foundation

/// Le placement des étiquettes de la frise audio du poste de pilotage
/// (spec §2.7 : « frise audio en pied d'écran, pleine largeur, avec étiquettes
/// de marqueurs (`04:12`, `DÉCISION`) »).
///
/// Extrait de la vue pour la même raison qu'`AudioTimelineGeometry` : ce qui
/// doit être juste ici n'est pas visible dans un `Canvas`. Deux étiquettes
/// superposées dessinent un pâté que rien ne signale, et une étiquette
/// **décalée** pour éviter le chevauchement ne désigne plus son marqueur — ce
/// qui est pire qu'une étiquette absente. D'où la règle : une étiquette qui
/// n'entre pas est **abandonnée**, jamais déplacée.
///
/// Deux passes, et non une seule de gauche à droite : les **décisions** sont
/// placées d'abord, les notes ensuite dans ce qui reste. Sur une fenêtre
/// étroite, perdre `DÉCISION` pour garder un timecode nu serait le mauvais
/// échange — c'est la décision qu'on cherche en relisant une réunion.
enum TimelineLabelLayout {

    /// Un marqueur candidat à l'étiquetage.
    struct Candidat: Equatable, Sendable {
        var t: Double
        /// Le texte affiché : `04:12` pour une note, `DÉCISION` pour une décision.
        var texte: String
        /// Teinte `accent/report` plutôt qu'`accent/action`, et priorité de
        /// placement.
        var estDecision: Bool
    }

    /// Une étiquette retenue, prête à dessiner.
    struct Etiquette: Equatable, Identifiable, Sendable {
        /// Index du candidat d'origine, pour relier l'étiquette à son marqueur.
        var id: Int
        var texte: String
        var estDecision: Bool
        /// Abscisse du centre de l'étiquette, **rentrée** dans la piste.
        var centre: CGFloat
        var largeur: CGFloat
    }

    /// Écart minimal entre deux étiquettes voisines.
    static let espacement: CGFloat = 6

    /// Hauteur de la bande d'étiquettes, au-dessus de la piste.
    static let hauteur: CGFloat = 16

    /// Largeur d'un caractère de Plex Mono à 9,5 px.
    ///
    /// Constante et non mesurée : `NSAttributedString.size()` exige une fonte
    /// chargée, donc une session graphique — et le placement doit rester
    /// vérifiable par un test. La valeur est majorée d'un cheveu, ce qui fait
    /// pencher les cas limites du bon côté (une étiquette abandonnée de
    /// justesse plutôt qu'une qui déborde).
    static let largeurCaractere: CGFloat = 5.9

    /// Rembourrage horizontal d'une étiquette (7 px de chaque côté, spec §1.2).
    static let rembourrage: CGFloat = 14

    /// Largeur estimée d'une étiquette. Jamais nulle : une étiquette de texte
    /// vide occupe tout de même son rembourrage, et lui donner zéro
    /// autoriserait deux voisines à se coller.
    static func largeur(_ texte: String) -> CGFloat {
        rembourrage + CGFloat(texte.count) * largeurCaractere
    }

    /// Les étiquettes à dessiner pour une piste de largeur `width`.
    ///
    /// - Parameters:
    ///   - candidats: les marqueurs étiquetables, dans n'importe quel ordre.
    ///   - duration: durée de l'axe. Zéro rend `[]` — pas de division, donc pas
    ///     de `NaN` dans un `Canvas`, qui n'en dessinerait rien sans rien dire.
    ///   - width: largeur utile de la piste.
    /// - Returns: les étiquettes retenues, triées par temps croissant, sans
    ///   chevauchement et toutes contenues dans `0…width`.
    static func placer(_ candidats: [Candidat],
                       duration: Double,
                       width: CGFloat) -> [Etiquette] {
        guard duration > 0, width > 0, !candidats.isEmpty else { return [] }

        // L'index d'origine est conservé : c'est lui qui relie l'étiquette à
        // son marqueur pour le dessin.
        let indexes = candidats.indices.sorted { candidats[$0].t < candidats[$1].t }
        var retenues: [Etiquette] = []

        // Passe 1 : les décisions. Passe 2 : le reste, dans les intervalles
        // laissés libres.
        for decisionsSeules in [true, false] {
            for index in indexes where candidats[index].estDecision == decisionsSeules {
                guard let etiquette = etiquetteDe(candidats[index],
                                                  index: index,
                                                  duration: duration,
                                                  width: width),
                      !chevauche(etiquette, retenues) else { continue }
                retenues.append(etiquette)
            }
        }

        return retenues.sorted { $0.centre < $1.centre }
    }

    // MARK: - Interne

    /// L'étiquette d'un candidat, rentrée dans la piste. `nil` quand elle est
    /// plus large que la piste elle-même : aucune position ne la contiendrait,
    /// et une moitié de mot ne se lit pas.
    private static func etiquetteDe(_ candidat: Candidat,
                                    index: Int,
                                    duration: Double,
                                    width: CGFloat) -> Etiquette? {
        let l = largeur(candidat.texte)
        guard l <= width else { return nil }
        let x = AudioTimelineGeometry.x(t: candidat.t, duration: duration, width: width)
        let centre = min(max(x, l / 2), width - l / 2)
        return Etiquette(id: index,
                         texte: candidat.texte,
                         estDecision: candidat.estDecision,
                         centre: centre,
                         largeur: l)
    }

    /// Vrai si l'étiquette empiète sur l'une des étiquettes déjà retenues,
    /// espacement compris.
    private static func chevauche(_ etiquette: Etiquette,
                                  _ retenues: [Etiquette]) -> Bool {
        let debut = etiquette.centre - etiquette.largeur / 2 - espacement
        let fin = etiquette.centre + etiquette.largeur / 2 + espacement
        return retenues.contains { autre in
            let debutAutre = autre.centre - autre.largeur / 2
            let finAutre = autre.centre + autre.largeur / 2
            return debut < finAutre && fin > debutAutre
        }
    }
}
