import Testing
import Foundation
@testable import OneToOne

/// Les objets annotés `question` / `risque` de la section `SUR CETTE PLANCHE`
/// (spec §7.2 : « liste des éléments annotés comme question/risque (puce
/// colorée) »).
///
/// L'annotation vit dans `customData` de l'élément Excalidraw : c'est le seul
/// champ que le moteur transporte sans y toucher, donc elle survit à l'export,
/// à la duplication et à la sauvegarde. La lecture est pure — un test n'a pas
/// besoin du moteur pour vérifier un aller-retour.
@Suite("Annotations question / risque d'une planche")
@MainActor
struct BoardAnnotationTests {

    @Test("Deux natures, avec libellé et entrée de menu en français")
    func twoKinds() {
        #expect(BoardAnnotation.Kind.allCases.map(\.rawValue) == ["question", "risk"])
        #expect(BoardAnnotation.Kind.question.label == "Question")
        #expect(BoardAnnotation.Kind.risk.label == "Risque")
        for nature in BoardAnnotation.Kind.allCases {
            #expect(nature.menuLabel.hasPrefix("Marquer comme "))
        }
    }

    @Test("Une scène annotée se relit : l'aller-retour conserve nature et texte")
    func roundTrip() {
        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60,
                  text: "Jenkins à décommissionner — dépend de la bascule runners",
                  annotation: .risk),
            .init(x: 0, y: 100, width: 200, height: 60,
                  text: "Qui porte la bascule ? question ouverte",
                  annotation: .question),
            .init(x: 0, y: 200, width: 200, height: 60, text: "Nexus"),
        ])

        let annotations = BoardAnnotation.list(in: scene)
        #expect(annotations.count == 2)
        // Dans l'ordre de la scène, comme le dock les affiche.
        #expect(annotations[0].kind == .risk)
        #expect(annotations[0].text.hasPrefix("Jenkins à décommissionner"))
        #expect(annotations[1].kind == .question)
        #expect(annotations[1].text == "Qui porte la bascule ? question ouverte")
        // L'identifiant est celui de l'objet : c'est lui qu'on resélectionne.
        #expect(!annotations[0].id.isEmpty)
        #expect(annotations[0].id != annotations[1].id)
    }

    @Test("Le texte d'une boîte est retrouvé même quand il vit dans l'objet lié")
    func textComesFromBoundElement() {
        // `BoardScene` sérialise une boîte en deux éléments : le rectangle
        // annoté, et le texte qui lui est lié par `containerId`. La liste doit
        // remonter le texte, pas une ligne vide.
        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60, text: "Risque réseau", annotation: .risk),
        ])
        let annotations = BoardAnnotation.list(in: scene)
        #expect(annotations.count == 1)
        #expect(annotations[0].text == "Risque réseau")
    }

    @Test("Une scène sans annotation n'en rend aucune")
    func noAnnotations() {
        #expect(BoardAnnotation.list(in: BoardScene.empty).isEmpty)
        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 100, height: 40, text: "Nexus"),
        ])
        #expect(BoardAnnotation.list(in: scene).isEmpty)
    }

    @Test("Une nature inconnue est ignorée, pas rangée dans un fourre-tout")
    func unknownKindIsIgnored() {
        let json = """
        {"type":"excalidraw","version":2,"elements":[
        {"id":"x","type":"rectangle","x":0,"y":0,"width":10,"height":10,
         "isDeleted":false,"text":"bof","customData":{"one2oneKind":"peut-être"}}
        ],"appState":{},"files":{}}
        """
        #expect(BoardAnnotation.list(in: json).isEmpty)
        #expect(BoardAnnotation.list(in: "pas du json").isEmpty)
    }

    @Test("Un objet supprimé ne reste pas dans la liste")
    func deletedElementsAreDropped() {
        let json = """
        {"type":"excalidraw","version":2,"elements":[
        {"id":"x","type":"rectangle","x":0,"y":0,"width":10,"height":10,
         "isDeleted":true,"text":"effacé","customData":{"one2oneKind":"risk"}}
        ],"appState":{},"files":{}}
        """
        #expect(BoardAnnotation.list(in: json).isEmpty)
    }

    @Test("Les connecteurs demandés sont liés aux deux boîtes qu'ils joignent")
    func connectorsAreBound() throws {
        let scene = BoardScene.scene(
            boxes: [
                .init(x: 0, y: 0, width: 120, height: 60, text: "DMZ"),
                .init(x: 300, y: 0, width: 120, height: 60, text: "Applicatif"),
            ],
            connectors: [.init(from: 0, to: 1)])

        let data = try #require(scene.data(using: .utf8))
        let objet = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(objet["elements"] as? [[String: Any]])
        let fleche = try #require(elements.first { ($0["type"] as? String) == "arrow" })

        let depart = try #require(fleche["startBinding"] as? [String: Any])
        let arrivee = try #require(fleche["endBinding"] as? [String: Any])
        let ids = Set(elements.compactMap { $0["id"] as? String })
        let departID = try #require(depart["elementId"] as? String)
        let arriveeID = try #require(arrivee["elementId"] as? String)
        #expect(ids.contains(departID))
        #expect(ids.contains(arriveeID))
        // Les deux boîtes reconnaissent la flèche, sinon la déplacer la
        // laisserait sur place.
        let flecheID = try #require(fleche["id"] as? String)
        let lies = elements.flatMap { element in
            (element["boundElements"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        }
        #expect(lies.filter { $0 == flecheID }.count == 2)
    }
}
