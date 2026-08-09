# Habillage visuel — vitrine `ActionsListView` et extraction de la trousse

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les étapes
> utilisent la syntaxe case à cocher (`- [ ]`).

**Spec** : [`docs/superpowers/specs/2026-08-09-habillage-visuel-design.md`](../specs/2026-08-09-habillage-visuel-design.md)

**Objectif** : restyler `ActionsListView` au langage visuel de la capture 3, à
fonctions strictement constantes, puis extraire de ce travail réel les jetons et
les composants qui serviront aux autres vues.

**Architecture** : un `enum` de jetons (`AppTheme`) sur le patron de
`MeetingTheme`, une règle d'urgence en fonction **pure et testée**, puis le
restylage de la barre de filtres et de la ligne. L'extraction des composants ne
vient qu'après, et seulement pour ce qui a réellement servi.

**Pile technique** : SwiftUI, SwiftData, macOS 15+. Aucune dépendance nouvelle.

---

## Contraintes globales

- **Français** pour les commentaires et les libellés d'interface, anglais pour
  les symboles et le code.
- **Zéro dépendance nouvelle.** La trousse est du SwiftUI ordinaire.
- **Aucun modèle SwiftData touché.**
- Commits conventionnels, messages en français.
- Branche dédiée, jamais de commit sur `master`.
- ⚠️ **L'arbre de travail contient 34 entrées non commitées d'un autre chantier**
  (`OneToOne/Markdown/`, `Tests/`, `Package.swift`, `Info.plist`, `CLAUDE.md`,
  `Vendor/`…). Elles ne doivent **jamais** entrer dans un commit.
  - INTERDIT : `git add -A`, `git add .`, `git add -u`, `git commit -a`,
    `git stash`, `git checkout`, `git switch`, `git restore`, `git reset`,
    `git clean`.
  - OBLIGATOIRE : `git add <chemin exact>`, puis vérifier par
    `git diff --cached --name-only` avant chaque commit.

### ⚠️ La règle qui décide de tout ce plan

**La capture 3 est une simplification de l'écran actuel, pas son habillage.**

La ligne d'aujourd'hui porte : case à cocher, titre éditable en ligne, badge
`manager`, `#ID` technique, date d'ouverture, projet, collaborateur, échéance,
compteur de commentaires, chevron de dépliage, bouton de suppression, et un
panneau dépliable. La capture n'affiche que cinq éléments.

> **On applique le vocabulaire visuel de la capture aux informations existantes.
> On n'adopte pas le jeu d'informations de la capture.**

Concrètement : **aucun contrôle n'est retiré**, aucun mode de vue n'est supprimé,
aucun filtre ne disparaît. Un implémenteur qui supprime le dépliage, les
commentaires, la suppression ou l'un des cinq modes de vue au motif qu'ils
« ne sont pas dans la capture » a commis un défaut, pas une simplification.

Une seule exception, explicite et isolée en tâche 5 : l'identifiant technique
`#A3F2`, qui n'est ni une fonction ni une information métier.

---

## Structure de fichiers

```text
OneToOne/Views/DesignSystem/
├── AppTheme.swift              jetons : couleurs, typo, espacements (tâche 1)
├── Urgence.swift               la règle d'urgence, pure et testée (tâche 1)
└── Components/
    ├── Avatar.swift            né composant (logique testable) — tâche 3
    ├── SegmentedFilter.swift   extrait après usage — tâche 6
    └── MetaValue.swift         extrait après usage — tâche 6

OneToOne/Views/ActionsListView.swift   restylé (tâches 2 à 5)

Tests/
├── UrgenceTests.swift          tâche 1
└── AvatarInitialsTests.swift   tâche 3
```

Pourquoi `Urgence` dans son propre fichier : c'est la seule logique de ce
chantier qui se teste sans écran, et elle sera consommée par plusieurs vues. La
laisser dans `AppTheme` la noierait au milieu de constantes.

---

## Vue d'ensemble des tâches

| # | Tâche | Vérification |
|---|---|---|
| 1 | Jetons `AppTheme` + règle d'urgence testée | `swift test` |
| 2 | Barre de filtres au style de la capture | à l'écran |
| 3 | Avatar à initiales (fonction pure testée + vue) | `swift test` |
| 4 | Ligne : métadonnées à droite, code projet en chasse fixe | à l'écran |
| 5 | Chrome de liste : séparateurs, teinte alternée, retrait du `#ID` | à l'écran |
| 6 | Extraction de la trousse | `swift test` + écran |

Les tâches 1 et 3 portent la logique testable. Les tâches 2, 4 et 5 sont
visuelles : elles se vérifient **à l'écran**, et leur critère de fin est
« conforme à la capture **et** aucun comportement changé ».

---

## Task 1 : jetons et règle d'urgence

**Files:**
- Create: `OneToOne/Views/DesignSystem/AppTheme.swift`
- Create: `OneToOne/Views/DesignSystem/Urgence.swift`
- Test: `Tests/UrgenceTests.swift`

**Interfaces:**
- Consomme : rien.
- Produit :
  - `enum Urgence { case forte, moyenne, aVenir, sansEcheance }`
  - `static func Urgence.pour(_ echeance: Date?, maintenant: Date, calendrier: Calendar = .current) -> Urgence`
  - `AppTheme.couleur(_ urgence: Urgence) -> Color`
  - jetons : `AppTheme.fondCreme`, `.fondContenu`, `.ligneAlternee`, `.textePrincipal`,
    `.texteSecondaire`, `.verbe`, `.urgenceForte`, `.urgenceMoyenne`, `.nominal`,
    `.accentManager`, `.separateur`
  - typo : `AppTheme.titreEcran`, `.intituleSection`, `.titreLigne`, `.sousTitre`, `.chasseFixe`
  - espacements : `AppTheme.margeContenu`, `.hauteurLigne`, `.rayonPilule`

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `Tests/UrgenceTests.swift` :

```swift
import XCTest
@testable import OneToOne

/// La règle de couleur d'urgence, déduite des captures 3 et 1a :
/// rouge au-delà de sept jours de retard, orange jusqu'à sept jours,
/// gris pour une échéance à venir.
final class UrgenceTests: XCTestCase {

    /// 8 août 2026, midi — la date de référence des captures.
    private func maintenant() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 8; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func jour(_ day: Int, _ month: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = month; c.day = day; c.hour = 9
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_echeanceDepasseeDePlusDeSeptJours_estForte() {
        // « 27/07 » et « 31/07 » de la capture 3 : rouges.
        XCTAssertEqual(Urgence.pour(jour(27, 7), maintenant: maintenant()), .forte)
        XCTAssertEqual(Urgence.pour(jour(31, 7), maintenant: maintenant()), .forte)
    }

    func test_echeanceDepasseeDeSeptJoursOuMoins_estMoyenne() {
        // « 03/08 », « 05/08 », « 06/08 » de la capture 3 : orange.
        XCTAssertEqual(Urgence.pour(jour(3, 8), maintenant: maintenant()), .moyenne)
        XCTAssertEqual(Urgence.pour(jour(5, 8), maintenant: maintenant()), .moyenne)
        XCTAssertEqual(Urgence.pour(jour(6, 8), maintenant: maintenant()), .moyenne)
    }

    func test_echeanceAVenir_estAVenir() {
        // « 11/08 », « 18/08 » de la capture 3 : grises.
        XCTAssertEqual(Urgence.pour(jour(11, 8), maintenant: maintenant()), .aVenir)
        XCTAssertEqual(Urgence.pour(jour(18, 8), maintenant: maintenant()), .aVenir)
    }

    /// Le jour même n'est pas en retard : la journée entière reste disponible.
    func test_echeanceAujourdHui_estAVenir() {
        XCTAssertEqual(Urgence.pour(jour(8, 8), maintenant: maintenant()), .aVenir)
    }

    /// La borne exacte des sept jours appartient à l'orange, pas au rouge.
    func test_borneDeSeptJours_appartientAOrange() {
        XCTAssertEqual(Urgence.pour(jour(1, 8), maintenant: maintenant()), .moyenne)
        XCTAssertEqual(Urgence.pour(jour(31, 7), maintenant: maintenant()), .forte)
    }

    func test_sansEcheance_aSonPropreCas() {
        XCTAssertEqual(Urgence.pour(nil, maintenant: maintenant()), .sansEcheance)
    }

    /// L'urgence se calcule en jours de calendrier, pas en intervalles de
    /// 24 heures : une échéance d'hier soir est en retard ce matin.
    func test_leCalculPorteSurDesJoursDeCalendrier() {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 7; c.hour = 23
        let hierSoir = Calendar(identifier: .gregorian).date(from: c)!
        var m = DateComponents()
        m.year = 2026; m.month = 8; m.day = 8; m.hour = 1
        let ceMatin = Calendar(identifier: .gregorian).date(from: m)!
        XCTAssertEqual(Urgence.pour(hierSoir, maintenant: ceMatin), .moyenne)
    }
}
```

- [ ] **Étape 2 : lancer le test pour le voir échouer**

Run : `swift test --filter UrgenceTests`
Attendu : ÉCHEC de compilation — « cannot find 'Urgence' in scope ».

- [ ] **Étape 3 : écrire `Urgence`**

Créer `OneToOne/Views/DesignSystem/Urgence.swift` :

```swift
import Foundation

/// Degré d'urgence d'une échéance, tel que les captures le donnent à voir.
///
/// C'est la seule règle de couleur conditionnelle du jeu visuel : elle vit donc
/// ici, une fois, plutôt que dans chaque vue qui affiche une date.
public enum Urgence: Equatable {
    /// Dépassée de plus de sept jours — rouge.
    case forte
    /// Dépassée de sept jours ou moins — orange.
    case moyenne
    /// Pas encore due, aujourd'hui compris — gris.
    case aVenir
    /// Aucune échéance posée.
    case sansEcheance

    /// Seuil lu sur les captures 3 et 1a : « 12 j » et « 8 j » sont rouges,
    /// « 5 j » et « 2 j » sont orange. À confirmer sur les fichiers sources.
    static let seuilForteEnJours = 7

    /// Classe une échéance par rapport à un instant donné.
    ///
    /// Le calcul porte sur des **jours de calendrier**, pas sur des intervalles
    /// de 24 heures : une échéance d'hier soir est en retard d'un jour ce matin,
    /// quelle que soit l'heure.
    public static func pour(_ echeance: Date?,
                            maintenant: Date,
                            calendrier: Calendar = .current) -> Urgence {
        guard let echeance else { return .sansEcheance }

        let jourEcheance = calendrier.startOfDay(for: echeance)
        let jourCourant = calendrier.startOfDay(for: maintenant)
        let retard = calendrier.dateComponents([.day], from: jourEcheance, to: jourCourant).day ?? 0

        if retard <= 0 { return .aVenir }
        return retard > seuilForteEnJours ? .forte : .moyenne
    }
}
```

- [ ] **Étape 4 : lancer le test pour le voir passer**

Run : `swift test --filter UrgenceTests`
Attendu : 7 tests, 0 échec.

- [ ] **Étape 5 : écrire les jetons**

Créer `OneToOne/Views/DesignSystem/AppTheme.swift` :

```swift
import SwiftUI

/// Jetons du langage visuel de l'application, lus sur les captures de design.
///
/// Patron : `enum` de constantes statiques, comme `MeetingTheme`.
///
/// ⚠️ Les valeurs de couleur sont **lues sur les images** des captures. En cas
/// d'écart avec les fichiers sources de Claude Design, le fichier source prime.
public enum AppTheme {

    // MARK: - Couleurs de fond

    /// Fond de fenêtre : barre latérale, pourtour.
    public static let fondCreme = Color(red: 0.937, green: 0.929, blue: 0.910)
    /// Fond de contenu : listes, tableaux, cartes.
    public static let fondContenu = Color(nsColor: .textBackgroundColor)
    /// Teinte des lignes alternées, très légère.
    public static let ligneAlternee = Color(red: 0.984, green: 0.980, blue: 0.973)
    /// Séparateur fin entre les lignes.
    public static let separateur = Color.secondary.opacity(0.15)

    // MARK: - Couleurs de texte

    public static let textePrincipal = Color.primary
    public static let texteSecondaire = Color.secondary

    // MARK: - Couleurs sémantiques

    /// Bleu système des verbes et des liens. Même valeur que le handoff éditeur
    /// (`#0a6cff`) : ne pas la dupliquer sous un autre nom.
    public static let verbe = Color(red: 0.039, green: 0.424, blue: 1.0)
    public static let urgenceForte = Color(red: 0.898, green: 0.282, blue: 0.302)
    public static let urgenceMoyenne = Color(red: 0.878, green: 0.502, blue: 0.0)
    public static let nominal = Color(red: 0.180, green: 0.490, blue: 0.322)
    public static let accentManager = Color(red: 0.431, green: 0.337, blue: 0.812)

    /// Couleur d'affichage d'une échéance, d'après sa seule urgence.
    public static func couleur(_ urgence: Urgence) -> Color {
        switch urgence {
        case .forte: return urgenceForte
        case .moyenne: return urgenceMoyenne
        case .aVenir, .sansEcheance: return texteSecondaire
        }
    }

    // MARK: - Typographie

    public static let titreEcran = Font.system(size: 28, weight: .semibold)
    /// Intitulé de section : petites capitales grises, interlettrage élargi.
    /// C'est le marqueur le plus caractéristique du jeu visuel.
    public static let intituleSection = Font.system(size: 11, weight: .semibold)
    public static let titreLigne = Font.system(size: 15, weight: .medium)
    public static let sousTitre = Font.system(size: 12)
    /// Codes projet, horaires, noms de commande.
    public static let chasseFixe = Font.system(size: 12, design: .monospaced)

    // MARK: - Espacements

    public static let margeContenu: CGFloat = 24
    public static let hauteurLigne: CGFloat = 44
    public static let rayonPilule: CGFloat = 6
}
```

- [ ] **Étape 6 : vérifier que le projet compile toujours**

Run : `swift build`
Attendu : succès.

- [ ] **Étape 7 : commit**

```bash
git add OneToOne/Views/DesignSystem/AppTheme.swift \
        OneToOne/Views/DesignSystem/Urgence.swift \
        Tests/UrgenceTests.swift
git diff --cached --name-only   # doit lister exactement ces trois chemins
git commit -m "feat(design): jetons visuels et règle d'urgence à sept jours"
```

---

## Task 2 : barre de filtres au style de la capture

**Files:**
- Modify: `OneToOne/Views/ActionsListView.swift` (barre de filtres, lignes 84-140)

**Interfaces:**
- Consomme : `AppTheme` (tâche 1).
- Produit : rien de réutilisable à ce stade. La forme du filtre segmenté sera
  extraite en tâche 6.

**Ce qui change et ce qui ne change pas.** La capture montre trois filtres
d'échéance à compteur intégré (`En retard 7`). L'écran actuel a un filtre de
**statut** (`En cours` / `Terminées` / `Toutes`). Ce sont deux axes différents.

> On garde **la sémantique actuelle** — statut — et on adopte **l'apparence** de
> la capture : pilule noire pleine pour l'actif, contour fin pour les autres,
> compteur intégré au libellé. Les filtres projet, collaborateur et échéance, le
> sélecteur de mode de vue et le bouton « Nouvelle action » **restent en place**.

- [ ] **Étape 1 : remplacer le `Picker` segmenté par des pilules**

Dans `ActionsListView.swift`, remplacer le bloc `Picker("Statut", …)` (lignes 85-92)
par :

```swift
HStack(spacing: 8) {
    ForEach(FilterStatus.allCases, id: \.self) { statut in
        Button {
            filterStatus = statut
        } label: {
            HStack(spacing: 6) {
                Text(statut.rawValue)
                Text("\(nombreDActions(pour: statut))")
                    .foregroundStyle(filterStatus == statut ? .white.opacity(0.7) : AppTheme.texteSecondaire)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(filterStatus == statut ? Color.white : AppTheme.textePrincipal)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.rayonPilule)
                    .fill(filterStatus == statut ? Color.black : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.rayonPilule)
                    .stroke(filterStatus == statut ? Color.clear : AppTheme.separateur, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Étape 2 : ajouter le compteur par statut**

Ajouter dans `ActionsListView`, à côté de `filteredTasks` :

```swift
/// Nombre d'actions que donnerait un statut, **les autres filtres restant
/// appliqués** : le compteur doit refléter ce qu'on obtiendra en cliquant,
/// pas un total abstrait.
private func nombreDActions(pour statut: FilterStatus) -> Int {
    var tasks = allTasks
    switch statut {
    case .pending: tasks = tasks.filter { !$0.isCompleted }
    case .completed: tasks = tasks.filter { $0.isCompleted }
    case .all: break
    }
    if let project = filterProject {
        tasks = tasks.filter { $0.project?.persistentModelID == project.persistentModelID }
    } else if let entity = filterEntity {
        tasks = tasks.filter { $0.project?.entity?.persistentModelID == entity.persistentModelID }
    }
    if let collaborator = filterCollaborator {
        tasks = tasks.filter { $0.collaborator?.persistentModelID == collaborator.persistentModelID }
    }
    if !searchText.isEmpty {
        tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    return tasks.count
}
```

- [ ] **Étape 3 : retirer le compteur redondant**

Le `Text("\(filteredTasks.count) action(s)")` de la fin de barre (lignes 137-139)
fait doublon avec les compteurs des pilules. Le supprimer.

- [ ] **Étape 4 : construire et vérifier à l'écran**

Run : `swift build`, puis lancer l'application.

À l'écran, cocher :
1. les trois pilules affichent un compteur, celui de la pilule active correspond
   au nombre de lignes réellement listées ;
2. la pilule active est noire pleine, texte blanc ; les deux autres ont un
   contour fin ;
3. cliquer une pilule change le filtre comme avant ;
4. **les filtres projet, collaborateur et échéance fonctionnent toujours** ;
5. **les cinq modes de vue sont toujours accessibles et fonctionnent** ;
6. « Nouvelle action » fonctionne toujours ;
7. changer un filtre projet met à jour les compteurs des pilules.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): filtres de statut en pilules à compteur intégré"
```

---

## Task 3 : avatar à initiales

**Files:**
- Create: `OneToOne/Views/DesignSystem/Components/Avatar.swift`
- Test: `Tests/AvatarInitialsTests.swift`

**Interfaces:**
- Consomme : `AppTheme`.
- Produit : `Avatar.initiales(de: String) -> String`, `Avatar(nom: String)` (vue).

`Avatar` naît directement comme composant, avant l'extraction de la tâche 6,
parce qu'il porte de la logique testable — les initiales. Les deux autres
composants, eux, seront extraits après usage.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `Tests/AvatarInitialsTests.swift` :

```swift
import XCTest
@testable import OneToOne

/// Initiales des avatars, telles que les captures les montrent :
/// « Sofiane Belkacem » → « SB », « Camille Roussel » → « CR ».
final class AvatarInitialsTests: XCTestCase {

    func test_deuxMots_donnentDeuxInitiales() {
        XCTAssertEqual(Avatar.initiales(de: "Sofiane Belkacem"), "SB")
        XCTAssertEqual(Avatar.initiales(de: "Camille Roussel"), "CR")
        XCTAssertEqual(Avatar.initiales(de: "Anne-Claire Petit"), "AP")
    }

    func test_unSeulMot_donneUneSeuleInitiale() {
        XCTAssertEqual(Avatar.initiales(de: "Sofiane"), "S")
    }

    func test_troisMotsOuPlus_prennentLePremierEtLeDernier() {
        XCTAssertEqual(Avatar.initiales(de: "Jean Pierre Dupont"), "JD")
    }

    func test_espacesSuperflus_sontIgnores() {
        XCTAssertEqual(Avatar.initiales(de: "  Marta   Nowak  "), "MN")
    }

    func test_nomVide_donneUneChaineVide() {
        XCTAssertEqual(Avatar.initiales(de: ""), "")
        XCTAssertEqual(Avatar.initiales(de: "   "), "")
    }

    /// Les initiales sont toujours en capitales, quelle que soit la saisie.
    func test_lesInitialesSontEnCapitales() {
        XCTAssertEqual(Avatar.initiales(de: "sofiane belkacem"), "SB")
    }

    /// Un prénom accentué garde son accent : « Étienne » → « É ».
    func test_lesAccentsSontConserves() {
        XCTAssertEqual(Avatar.initiales(de: "Étienne Roux"), "ÉR")
    }
}
```

- [ ] **Étape 2 : lancer le test pour le voir échouer**

Run : `swift test --filter AvatarInitialsTests`
Attendu : ÉCHEC de compilation — « cannot find 'Avatar' in scope ».

- [ ] **Étape 3 : écrire `Avatar`**

Créer `OneToOne/Views/DesignSystem/Components/Avatar.swift` :

```swift
import SwiftUI

/// Pastille d'initiales, telle que les captures la montrent en tête de ligne
/// et dans les listes de collaborateurs.
public struct Avatar: View {

    public let nom: String

    public init(nom: String) {
        self.nom = nom
    }

    /// Initiales d'un nom : première lettre du premier mot, première lettre du
    /// dernier. Un seul mot ne donne qu'une initiale.
    public static func initiales(de nom: String) -> String {
        let mots = nom.split(separator: " ").filter { !$0.isEmpty }
        guard let premier = mots.first else { return "" }
        let debut = String(premier.prefix(1))
        guard mots.count > 1, let dernier = mots.last else { return debut.uppercased() }
        return (debut + String(dernier.prefix(1))).uppercased()
    }

    public var body: some View {
        Text(Self.initiales(de: nom))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.textePrincipal)
            .frame(width: 22, height: 22)
            .background(Circle().fill(AppTheme.separateur))
            .help(nom)
    }
}
```

- [ ] **Étape 4 : lancer le test pour le voir passer**

Run : `swift test --filter AvatarInitialsTests`
Attendu : 7 tests, 0 échec.

- [ ] **Étape 5 : construire et tester**

Run : `swift build && swift test --filter AvatarInitialsTests`
Attendu : compilation réussie, 7 tests, 0 échec. Rien ne change à l'écran : la
vue `Avatar` n'est pas encore consommée, c'est la tâche suivante qui l'emploie.

- [ ] **Étape 6 : commit**

```bash
git add OneToOne/Views/DesignSystem/Components/Avatar.swift \
        Tests/AvatarInitialsTests.swift
git diff --cached --name-only
git commit -m "feat(design): composant avatar à initiales"
```

---

## Task 4 : métadonnées de ligne à droite

**Files:**
- Modify: `OneToOne/Views/ActionsListView.swift` (`ActionTaskRow.metaLine`, lignes 478-507 ;
  `taskStatus` / `dueColor`, lignes 509-534)

**Interfaces:**
- Consomme : `Urgence.pour(_:maintenant:)`, `AppTheme.couleur(_:)`, `AppTheme.chasseFixe`,
  `Avatar(nom:)` (tâche 3).
- Produit : rien de réutilisable à ce stade.

**Ce qui change.** La capture range les métadonnées **à droite**, en trois blocs
séparés : code projet en chasse fixe grise, avatar, échéance colorée. L'existant
les met **sous le titre**, en une ligne d'étiquettes à icônes.

**Ce qui ne change pas.** Le dépliage, le compteur de commentaires, la
suppression, l'édition en ligne du titre et le badge `manager` restent
exactement où ils sont.

- [ ] **Étape 1 : remplacer `metaLine` par un bloc de droite**

Remplacer la propriété `metaLine` (lignes 478-507) par :

```swift
/// Métadonnées alignées à droite, dans l'ordre de la capture 3 :
/// code projet, avatar du porteur, échéance colorée par l'urgence.
private var metadonneesADroite: some View {
    HStack(spacing: 12) {
        Text(task.project?.code ?? "—")
            .font(AppTheme.chasseFixe)
            .foregroundStyle(AppTheme.texteSecondaire)
            .frame(minWidth: 64, alignment: .trailing)

        if let collab = task.collaborator {
            Avatar(nom: collab.name)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }

        Text(libelleEcheance)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.couleur(urgence))
            .frame(minWidth: 52, alignment: .trailing)
            .help(task.dueDate.map { Self.dateFmt.string(from: $0) } ?? "Sans échéance")
    }
}

private var urgence: Urgence {
    Urgence.pour(task.dueDate, maintenant: Date())
}

/// Format court de la capture : « 27/07 ». Un tiret cadratin si aucune
/// échéance — jamais une case vide.
private var libelleEcheance: String {
    guard let due = task.dueDate else { return "—" }
    return Self.echeanceFmt.string(from: due)
}

private static let echeanceFmt: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = "dd/MM"
    return f
}()
```

- [ ] **Étape 2 : brancher le bloc dans la ligne**

Dans `openTaskView`, retirer l'appel à `metaLine` (ligne 426) et insérer
`metadonneesADroite` juste avant le `Spacer(minLength: 8)` de la ligne 429 :

```swift
                }

                Spacer(minLength: 8)

                metadonneesADroite

                if !task.comments.isEmpty {
```

- [ ] **Étape 3 : faire consommer la règle partagée par `taskStatus`**

`taskStatus` (lignes 515-525) garde ses cinq cas — l'icône de la case à cocher
les utilise — mais la **couleur** doit venir de la règle partagée, sinon deux
seuils cohabiteraient dans le même écran. Remplacer le corps de `dueColor` par
un renvoi à `AppTheme.couleur(Urgence.pour(...))`, et laisser `taskStatus`
inchangé.

- [ ] **Étape 4 : construire et vérifier à l'écran**

Run : `swift build`, puis lancer l'application.

À l'écran, cocher :
1. le code projet apparaît en chasse fixe grise, aligné à droite ; un tiret
   cadratin quand l'action n'a pas de projet ;
2. l'avatar affiche les bonnes initiales, et une infobulle donne le nom complet ;
3. l'échéance est au format `27/07`, alignée à droite ;
4. **une échéance dépassée de plus de sept jours est rouge, de sept jours ou
   moins orange, à venir grise** ;
5. les colonnes restent alignées d'une ligne à l'autre ;
6. **le dépliage, les commentaires, la suppression et l'édition du titre
   fonctionnent toujours** ;
7. le badge `manager` s'affiche toujours sur les actions concernées.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): métadonnées de ligne alignées à droite et colorées par l'urgence"
```

---

## Task 5 : chrome de liste

**Files:**
- Modify: `OneToOne/Views/ActionsListView.swift` (`rowBackground` lignes 472-476 ;
  `openTaskView` lignes 388-467 ; `metaLine` supprimée en tâche 4)

**Interfaces:**
- Consomme : `AppTheme`.
- Produit : rien de réutilisable.

- [ ] **Étape 1 : teinte alternée et séparateur**

`ActionTaskRow` doit savoir si sa ligne est paire ou impaire pour la teinte
alternée. Ajouter une propriété `let estPaire: Bool` à `ActionTaskRow`, la
transmettre depuis la liste (`.enumerated()`), et remplacer `rowBackground` par :

```swift
private var rowBackground: some View {
    (isHovering ? AppTheme.separateur.opacity(0.35)
                : (estPaire ? AppTheme.fondContenu : AppTheme.ligneAlternee))
        .onHover { isHovering = $0 }
}
```

Remplacer aussi la couleur du séparateur de bas de ligne (ligne 464) par
`AppTheme.separateur`.

- [ ] **Étape 2 : retirer l'identifiant technique**

C'est **la seule information retirée de l'écran** par ce plan, et elle est
isolée ici pour être facile à annuler. Supprimer de la ligne le
`Text("#\(task.persistentModelID.hashValue…)")` : c'est un identifiant de
débogage, absent de toutes les captures, et il occupe la place où la capture met
le sous-titre.

- [ ] **Étape 3 : sous-titre au vocabulaire de la capture**

Sous le titre, la capture met un sous-titre gris en une ligne :
`Sofiane Belkacem · ARC-118 · échéance 27/07`. Reconstituer l'équivalent avec ce
qui reste après le déplacement des métadonnées à droite — la date d'ouverture :

```swift
private var sousTitre: some View {
    Group {
        if let createdAt = task.createdAt {
            Text("ouverte le \(Self.dateFmt.string(from: createdAt))")
        } else {
            Text("")
        }
    }
    .font(AppTheme.sousTitre)
    .foregroundStyle(AppTheme.texteSecondaire)
}
```

L'insérer là où `metaLine` se trouvait, à la ligne 426.

- [ ] **Étape 4 : construire et vérifier à l'écran**

Run : `swift build`, puis lancer l'application.

À l'écran, cocher :
1. les lignes alternent une teinte très légère ;
2. le survol reste visible et distinct de la teinte alternée ;
3. les séparateurs sont fins et pleine largeur ;
4. plus aucun `#A3F2` nulle part ;
5. la densité générale se rapproche de la capture 3 ;
6. **toutes les fonctions des tâches 2 et 4 marchent encore.**

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): chrome de liste — teinte alternée, séparateurs, sous-titre"
```

---

## Task 6 : extraction de la trousse

**Files:**
- Create: `OneToOne/Views/DesignSystem/Components/SegmentedFilter.swift`
- Create: `OneToOne/Views/DesignSystem/Components/MetaValue.swift`
- Modify: `OneToOne/Views/ActionsListView.swift`

**Interfaces:**
- Consomme : tout ce qui précède.
- Produit :
  - `SegmentedFilter<T: Hashable>(options: [T], selection: Binding<T>, libelle: (T) -> String, compteur: (T) -> Int)`
  - `MetaValue(texte: String, urgence: Urgence)`

**Règle de l'extraction.** Elle ne doit **rien changer à l'écran**. Si
l'apparence bouge, c'est que le composant ne correspond pas à l'usage : corriger
le composant, pas la vitrine.

Et on n'extrait **que ce qui a servi**. `SectionLabel`, `StatusDot`, `TypeBadge`
et `VerbButton` figurent dans la spec mais n'apparaissent pas dans la capture 3 :
ils attendront la vue qui en aura besoin. Les créer ici serait spéculatif.

- [ ] **Étape 1 : extraire `SegmentedFilter`**

Créer `OneToOne/Views/DesignSystem/Components/SegmentedFilter.swift` :

```swift
import SwiftUI

/// Filtres en pilules à compteur intégré, comme « En retard 7 » de la capture 3.
/// L'option active est une pilule noire pleine ; les autres, un contour fin.
public struct SegmentedFilter<Option: Hashable>: View {

    public let options: [Option]
    @Binding public var selection: Option
    public let libelle: (Option) -> String
    public let compteur: (Option) -> Int

    public init(options: [Option],
                selection: Binding<Option>,
                libelle: @escaping (Option) -> String,
                compteur: @escaping (Option) -> Int) {
        self.options = options
        self._selection = selection
        self.libelle = libelle
        self.compteur = compteur
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let actif = option == selection
                Button { selection = option } label: {
                    HStack(spacing: 6) {
                        Text(libelle(option))
                        Text("\(compteur(option))")
                            .foregroundStyle(actif ? .white.opacity(0.7) : AppTheme.texteSecondaire)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(actif ? Color.white : AppTheme.textePrincipal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.rayonPilule)
                            .fill(actif ? Color.black : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.rayonPilule)
                            .stroke(actif ? Color.clear : AppTheme.separateur, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Étape 2 : extraire `MetaValue`**

Créer `OneToOne/Views/DesignSystem/Components/MetaValue.swift` :

```swift
import SwiftUI

/// Métadonnée alignée à droite, colorée par son urgence — « 12 j », « 27/07 »,
/// « 6 semaines » dans les captures. La couleur porte l'information ; le libellé
/// reste court.
public struct MetaValue: View {

    public let texte: String
    public let urgence: Urgence
    public let largeurMinimale: CGFloat

    public init(texte: String, urgence: Urgence, largeurMinimale: CGFloat = 52) {
        self.texte = texte
        self.urgence = urgence
        self.largeurMinimale = largeurMinimale
    }

    public var body: some View {
        Text(texte)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.couleur(urgence))
            .frame(minWidth: largeurMinimale, alignment: .trailing)
    }
}
```

- [ ] **Étape 3 : faire consommer les composants par la vitrine**

Dans `ActionsListView`, remplacer le `HStack` de pilules de la tâche 2 par :

```swift
SegmentedFilter(options: FilterStatus.allCases,
                selection: $filterStatus,
                libelle: { $0.rawValue },
                compteur: { nombreDActions(pour: $0) })
```

Dans `ActionTaskRow.metadonneesADroite`, remplacer le `Text(libelleEcheance)` et
ses modificateurs par :

```swift
MetaValue(texte: libelleEcheance, urgence: urgence)
    .help(task.dueDate.map { Self.dateFmt.string(from: $0) } ?? "Sans échéance")
```

- [ ] **Étape 4 : construire, tester, vérifier l'absence de changement visuel**

Run : `swift build && swift test --filter UrgenceTests --filter AvatarInitialsTests`
Attendu : 14 tests, 0 échec.

À l'écran : **l'écran doit être identique à celui de la fin de tâche 5.**
Comparer les deux, filtre par filtre et ligne par ligne. Tout écart visible est
un défaut d'extraction.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/DesignSystem/Components/SegmentedFilter.swift \
        OneToOne/Views/DesignSystem/Components/MetaValue.swift \
        OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): extrait SegmentedFilter et MetaValue de la vitrine"
```

---

## Vérification finale avant PR

```bash
swift build
swift test --skip CalendarImportEventTests
git diff --stat master...HEAD
```

Attendu :

- `swift build` réussi ;
- `UrgenceTests` (7) et `AvatarInitialsTests` (7) au vert ;
- les deux échecs préexistants de `MenuBarStatsTests` restent les seuls échecs :
  `test_badge_twelve_compact` (attente périmée, `" ⚠12"` contre `" ●12"`) et
  `test_todayStats_passedOnlyAndNoProject` (dépendant de l'heure, échoue entre
  minuit et 3 h) ;
- le diff ne contient que `OneToOne/Views/DesignSystem/**`,
  `OneToOne/Views/ActionsListView.swift`, `Tests/UrgenceTests.swift`,
  `Tests/AvatarInitialsTests.swift` et les deux documents `docs/`.

**Et le contrôle qui compte le plus** : reprendre les cinq modes de vue
(liste, eisenhower, kanban, calendrier, sticky), les quatre filtres, la recherche,
la création, la suppression et le dépliage — et confirmer qu'aucun n'a changé de
comportement. Le périmètre était l'habillage.
