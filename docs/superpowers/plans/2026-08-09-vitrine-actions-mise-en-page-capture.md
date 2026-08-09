# Vitrine `ActionsListView` — adopter la mise en page de la capture 3

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — `superpowers:subagent-driven-development`.
> Les étapes utilisent la syntaxe case à cocher (`- [ ]`).

**Origine** : correction de cap. Le plan précédent
(`2026-08-09-habillage-vitrine-actions.md`) a appliqué le *vocabulaire visuel* de la
capture aux informations existantes, sans adopter sa *mise en page*. L'auteur du dépôt,
en voyant l'écran, ne l'a pas reconnu — à juste titre : la barre d'outils n'avait rien à
voir avec sa maquette. Ce plan corrige cela.

**Objectif** : `ActionsListView` prend la mise en page de la capture 3. Aucun contrôle
n'est supprimé — ceux que la capture ne montre pas se déplacent.

**Architecture** : la barre principale devient celle de la capture (trois pilules
d'échéance à compteur + « Grouper par »). Tout le reste monte dans la barre d'outils de
la fenêtre. La ligne se réduit à cinq éléments, avec un menu `⋮` au survol.

**Pile technique** : SwiftUI, SwiftData, macOS 15+. Aucune dépendance nouvelle.

---

## Contraintes globales

- **Français** pour les commentaires et les libellés d'interface, anglais pour les
  symboles — sauf le module `DesignSystem`, en français par décision de l'auteur.
- **Zéro dépendance nouvelle. Aucun modèle SwiftData touché.**
- **Aucune fonction n'est supprimée.** Les contrôles absents de la capture se
  **déplacent** ; ils restent atteignables. Un contrôle devenu inatteignable est un
  défaut Critique.
- Réutiliser ce qui existe : `AppTheme`, `Urgence`, `Avatar`, `MetaValue`,
  `SegmentedFilter` sont déjà en place et sont exactement les briques de la capture.
- ⚠️ **34 entrées non commitées d'un autre chantier** dans l'arbre. Jamais `git add -A`,
  `git add .`, `git add -u`, `git commit -a`, `git stash`, `git checkout`, `git switch`,
  `git restore`, `git reset`, `git clean`. Ajout **nommément**, vérification par
  `git diff --cached --name-only`.
- Commits conventionnels, messages en français.

### La cible, décrite sans ambiguïté

**Barre principale** — et rien d'autre :

- trois pilules à compteur intégré : `En retard N`, `Cette semaine N`, `Toutes N` ;
  l'active est noire pleine, les autres en contour fin ;
- à droite, `Grouper par : échéance ▾`.

**Barre d'outils de la fenêtre** (`.toolbar`), tout ce que la capture ne montre pas :

- le sélecteur des cinq modes de vue (liste, eisenhower, kanban, calendrier, sticky) ;
- « Nouvelle action » ;
- le filtre de statut (`En cours` / `Terminées` / `Toutes`) ;
- les filtres projet/entité et collaborateur.

**Ligne au repos** : case à cocher · titre · code projet en chasse fixe · avatar ·
échéance colorée. Rien d'autre.

**Ligne au survol** : un menu `⋮` apparaît en fin de ligne, portant **Modifier**,
**Supprimer**, et **Commentaires** (qui déplie la ligne).

### Deux définitions que la capture ne donne pas

- **« Cette semaine »** : échéance comprise entre aujourd'hui inclus et J+7 inclus,
  donc non dépassée.
- **Les trois pilules filtrent parmi les actions non terminées.** L'accès aux terminées
  passe par le filtre de statut, en barre d'outils.

---

## Structure de fichiers

```text
OneToOne/Views/DesignSystem/
└── Portee.swift                    NOUVEAU : les trois portées d'échéance (tâche 1)

OneToOne/Views/ActionsListView.swift  barre, toolbar, ligne (tâches 1 à 3)

Tests/
└── PorteeTests.swift               NOUVEAU : la règle des trois portées (tâche 1)
```

`Portee` vit à côté d'`Urgence` : c'est la seconde règle de date du chantier, et la seule
autre chose qui se teste sans écran.

---

## Vue d'ensemble

| # | Tâche | Vérification |
|---|---|---|
| 1 | `Portee` (En retard / Cette semaine / Toutes) + les trois pilules | `swift test` |
| 2 | Barre d'outils : y déplacer les cinq contrôles chassés | à l'écran |
| 3 | Ligne réduite + menu `⋮` au survol | à l'écran |

---

## Task 1 : la règle des trois portées, et les pilules

**Files:**
- Create: `OneToOne/Views/DesignSystem/Portee.swift`
- Modify: `OneToOne/Views/ActionsListView.swift`
- Test: `Tests/PorteeTests.swift`

**Interfaces:**
- Consomme : rien.
- Produit :
  - `enum Portee: String, CaseIterable { case enRetard, cetteSemaine, toutes }`
  - `var Portee.libelle: String` → `"En retard"`, `"Cette semaine"`, `"Toutes"`
  - `static func Portee.contient(_ echeance: Date?, portee: Portee, maintenant: Date, calendrier: Calendar = .current) -> Bool`

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `Tests/PorteeTests.swift` :

```swift
import XCTest
@testable import OneToOne

/// Les trois portées d'échéance de la capture 3 : « En retard », « Cette semaine »,
/// « Toutes ». Ce sont des filtres, distincts de la règle de **couleur** (`Urgence`).
final class PorteeTests: XCTestCase {

    /// 9 août 2026, midi.
    private func maintenant() -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 9; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func jour(_ day: Int, _ month: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = month; c.day = day; c.hour = 9
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_enRetard_prendLesEcheancesDepassees() {
        XCTAssertTrue(Portee.contient(jour(27, 7), portee: .enRetard, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(8, 8), portee: .enRetard, maintenant: maintenant()))
    }

    /// Le jour même n'est pas en retard : la journée entière reste disponible.
    func test_enRetard_exclutAujourdHui() {
        XCTAssertFalse(Portee.contient(jour(9, 8), portee: .enRetard, maintenant: maintenant()))
    }

    func test_enRetard_exclutLAVenirEtLeSansEcheance() {
        XCTAssertFalse(Portee.contient(jour(15, 8), portee: .enRetard, maintenant: maintenant()))
        XCTAssertFalse(Portee.contient(nil, portee: .enRetard, maintenant: maintenant()))
    }

    /// « Cette semaine » = d'aujourd'hui inclus à J+7 inclus.
    func test_cetteSemaine_prendAujourdHuiEtLesSeptJoursSuivants() {
        XCTAssertTrue(Portee.contient(jour(9, 8), portee: .cetteSemaine, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(12, 8), portee: .cetteSemaine, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(16, 8), portee: .cetteSemaine, maintenant: maintenant()))
    }

    func test_cetteSemaine_exclutJPlusHuit() {
        XCTAssertFalse(Portee.contient(jour(17, 8), portee: .cetteSemaine, maintenant: maintenant()))
    }

    /// Une échéance dépassée n'est pas « cette semaine » : elle est « en retard ».
    func test_cetteSemaine_exclutLeRetard() {
        XCTAssertFalse(Portee.contient(jour(8, 8), portee: .cetteSemaine, maintenant: maintenant()))
    }

    func test_cetteSemaine_exclutLeSansEcheance() {
        XCTAssertFalse(Portee.contient(nil, portee: .cetteSemaine, maintenant: maintenant()))
    }

    /// « Toutes » ne filtre rien, pas même les actions sans échéance.
    func test_toutes_prendTout() {
        XCTAssertTrue(Portee.contient(jour(27, 7), portee: .toutes, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(9, 8), portee: .toutes, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(jour(31, 12), portee: .toutes, maintenant: maintenant()))
        XCTAssertTrue(Portee.contient(nil, portee: .toutes, maintenant: maintenant()))
    }

    /// Les trois portées sont exclusives sur les échéances datées, et « Toutes » les
    /// recouvre : une échéance datée tombe dans « En retard » ou « Cette semaine »
    /// ou ni l'une ni l'autre, jamais dans les deux.
    func test_enRetardEtCetteSemaine_neSeChevauchentJamais() {
        for jourDuMois in 1...31 {
            let date = jour(jourDuMois, 8)
            let retard = Portee.contient(date, portee: .enRetard, maintenant: maintenant())
            let semaine = Portee.contient(date, portee: .cetteSemaine, maintenant: maintenant())
            XCTAssertFalse(retard && semaine, "le \(jourDuMois)/08 tombe dans les deux portées")
        }
    }
}
```

- [ ] **Étape 2 : lancer le test pour le voir échouer**

Run : `swift test --filter PorteeTests`
Attendu : ÉCHEC de compilation — « cannot find 'Portee' in scope ».

- [ ] **Étape 3 : écrire `Portee`**

Créer `OneToOne/Views/DesignSystem/Portee.swift` :

```swift
import Foundation

/// Portée d'échéance : le filtre principal de la liste d'actions, tel que la capture 3
/// le présente en trois pilules.
///
/// À ne pas confondre avec `Urgence`, qui décide d'une **couleur**. `Portee` décide de
/// ce qui est **affiché**. Les deux se calculent à partir d'une échéance mais ne
/// partagent pas leurs seuils : une action en retard de trois jours est `.enRetard`
/// pour la portée, et `.moyenne` pour l'urgence.
public enum Portee: String, CaseIterable {
    case enRetard
    case cetteSemaine
    case toutes

    public var libelle: String {
        switch self {
        case .enRetard: return "En retard"
        case .cetteSemaine: return "Cette semaine"
        case .toutes: return "Toutes"
        }
    }

    /// Nombre de jours couverts par « Cette semaine », aujourd'hui inclus.
    static let joursDeLaSemaine = 7

    /// Une échéance tombe-t-elle dans cette portée ?
    ///
    /// Le calcul porte sur des **jours de calendrier**, comme `Urgence`.
    public static func contient(_ echeance: Date?,
                                portee: Portee,
                                maintenant: Date,
                                calendrier: Calendar = .current) -> Bool {
        if portee == .toutes { return true }
        guard let echeance else { return false }

        let jourEcheance = calendrier.startOfDay(for: echeance)
        let jourCourant = calendrier.startOfDay(for: maintenant)
        let ecart = calendrier.dateComponents([.day], from: jourCourant, to: jourEcheance).day ?? 0

        switch portee {
        case .enRetard: return ecart < 0
        case .cetteSemaine: return ecart >= 0 && ecart <= joursDeLaSemaine
        case .toutes: return true
        }
    }
}
```

- [ ] **Étape 4 : lancer le test pour le voir passer**

Run : `swift test --filter PorteeTests`
Attendu : 9 tests, 0 échec.

- [ ] **Étape 5 : brancher les pilules sur la portée**

Dans `ActionsListView` : ajouter `@State private var portee: Portee = .enRetard`, faire
appliquer la portée par `actionsFiltrees(statut:)` — la chaîne de filtres unique — et
remplacer le `SegmentedFilter` de statut par celui de portée :

```swift
SegmentedFilter(options: Portee.allCases,
                selection: $portee,
                libelle: { $0.libelle },
                compteur: { nombreDActions(pour: $0) })
```

`nombreDActions(pour:)` prend désormais une `Portee` et renvoie le nombre d'actions que
donnerait ce filtre, **les autres filtres restant appliqués** — c'est ce qu'on obtiendra
en cliquant, jamais un total abstrait.

- [ ] **Étape 6 : ajouter « Grouper par : échéance »**

À droite de la barre principale, un `Menu` intitulé `Grouper par : <valeur>` alimenté par
`ActionGrouping.allCases` (l'énumération existe déjà et sert au kanban), lié à
`kanbanGrouping`. En mode liste, il n'a pas d'effet sur le tri à ce stade : il expose le
réglage, comme la capture le montre. Documente-le en commentaire pour que ce ne soit pas
pris pour un oubli.

- [ ] **Étape 7 : construire et tester**

Run : `swift build && swift test --filter PorteeTests --filter UrgenceTests --filter AvatarInitialsTests`
Attendu : 24 tests, 0 échec.

- [ ] **Étape 8 : commit**

```bash
git add OneToOne/Views/DesignSystem/Portee.swift Tests/PorteeTests.swift OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): pilules de portée d'échéance et menu Grouper par"
```

---

## Task 2 : la barre d'outils accueille les contrôles chassés

**Files:**
- Modify: `OneToOne/Views/ActionsListView.swift`

**Interfaces:**
- Consomme : `Portee` (tâche 1).
- Produit : rien de réutilisable.

**Règle absolue** : rien n'est supprimé. Chacun des cinq contrôles reste atteignable et
fonctionnel après déplacement. Un contrôle devenu inatteignable est un défaut Critique.

- [ ] **Étape 1 : déplacer les cinq contrôles**

Retirer de la barre principale et poser dans un `.toolbar { }` sur la vue :

1. le sélecteur des cinq modes de vue (`viewMode`) ;
2. « Nouvelle action » (`addAction`) ;
3. le filtre de statut (`filterStatus`) — il quitte la barre principale, remplacé par la
   portée, mais reste le seul accès aux actions terminées ;
4. `projectFilterMenu` ;
5. le filtre collaborateur.

Regrouper 3, 4 et 5 sous un seul `Menu` intitulé « Filtres », pour ne pas charger la
barre d'outils : le sélecteur de vue et « Nouvelle action » restent des éléments de
premier niveau, les trois filtres secondaires vivent dans le menu.

- [ ] **Étape 2 : la barre principale ne garde que la capture**

Après déplacement, la barre principale ne doit plus contenir que le `SegmentedFilter` de
portée et le menu « Grouper par ». Vérifie qu'il n'y reste rien d'autre.

- [ ] **Étape 3 : construire et vérifier à l'écran**

Run : `swift build`, puis lancer l'application.

À l'écran, cocher :

1. la barre principale ne contient que les trois pilules et « Grouper par » ;
2. les cinq modes de vue sont dans la barre d'outils et **fonctionnent tous les cinq** ;
3. « Nouvelle action » est dans la barre d'outils et crée une action ;
4. le menu « Filtres » donne accès au statut, au projet et au collaborateur, et les trois
   filtrent comme avant ;
5. `Terminées` reste atteignable et affiche bien les actions terminées ;
6. la fenêtre reste utilisable à largeur réduite (la barre d'outils ne déborde pas).

- [ ] **Étape 4 : commit**

```bash
git add OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): déplace les contrôles secondaires en barre d'outils"
```

---

## Task 3 : la ligne de la capture, et son menu `⋮`

**Files:**
- Modify: `OneToOne/Views/ActionsListView.swift`

**Interfaces:**
- Consomme : `Avatar`, `MetaValue`, `AppTheme`, `Urgence`.
- Produit : rien de réutilisable.

**Règle absolue** : rien n'est supprimé. Modifier, Supprimer et les commentaires restent
atteignables — par le menu `⋮` au lieu de contrôles permanents.

- [ ] **Étape 1 : réduire la ligne au repos**

Dans `openTaskView`, retirer de la ligne : le sous-titre (`sousTitre`), le compteur de
commentaires, le chevron de dépliage et le bouton de suppression. La ligne au repos
devient : case à cocher · titre (+ badge `manager` s'il y a lieu) · `Spacer` · code
projet · avatar · échéance.

Le dépliage reste déclenché par le **clic sur la ligne**, comportement déjà en place —
il ne disparaît pas avec le chevron.

- [ ] **Étape 2 : ajouter le menu `⋮` au survol**

En fin de ligne, après l'échéance, un `Menu` dont le libellé est
`Image(systemName: "ellipsis")`, visible **uniquement quand `isHovering` est vrai** et
occupant sa place en permanence (largeur réservée) pour que les colonnes ne sautent pas
au survol. Trois entrées :

- **Modifier** — passe la ligne en édition de titre (`isEditingTitle = true`) ;
- **Commentaires** — déplie la ligne (`expanded = true`) ; ajouter le nombre entre
  parenthèses quand il y en a, par exemple « Commentaires (3) » ;
- **Supprimer** — appelle `onDelete()`.

Style : `.menuStyle(.borderlessButton)`, teinte `AppTheme.texteSecondaire`.

- [ ] **Étape 3 : construire et vérifier à l'écran**

Run : `swift build`, puis lancer l'application.

À l'écran, cocher :

1. au repos, la ligne ne montre que : case, titre, code, avatar, date ;
2. au survol, le menu `⋮` apparaît **sans décaler les colonnes** ;
3. « Modifier » passe le titre en édition et la saisie se sauvegarde ;
4. « Commentaires » déplie la ligne et le panneau fonctionne ;
5. « Supprimer » supprime bien la ligne ;
6. cliquer la ligne (hors menu) déplie et replie, comme avant ;
7. la case à cocher bascule toujours l'état ;
8. le badge `manager` reste visible sur les actions concernées.

- [ ] **Étape 4 : commit**

```bash
git add OneToOne/Views/ActionsListView.swift
git diff --cached --name-only
git commit -m "feat(design): ligne réduite à la capture, actions dans un menu au survol"
```

---

## Vérification finale

```bash
swift build
swift test --filter PorteeTests --filter UrgenceTests --filter AvatarInitialsTests
git diff --stat master...HEAD
```

Attendu : build réussi ; 24 tests, 0 échec ; le diff ne contient que
`OneToOne/Views/DesignSystem/**`, `OneToOne/Views/ActionsListView.swift`, `Tests/**` et
les documents `docs/`.

**Et le contrôle qui décide** : ouvrir l'écran à côté de la capture 3 et confirmer qu'on
reconnaît la maquette — trois pilules d'échéance, « Grouper par » à droite, lignes nues.
C'est ce contrôle qui a manqué la première fois.
