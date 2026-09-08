import Foundation
import os

private let waveformLog = Logger(subsystem: "com.onetoone.app", category: "waveform")

/// Cache des pics d'onde décimés, par fichier et par résolution.
///
/// `AudioWaveform.peaks(url:count:)` décode **tout** le WAV : sans cache, la
/// frise de 22 px le referait à chaque rendu de la colonne — c'est-à-dire à
/// chaque frappe dans le composeur de notes. Une réunion d'une heure, c'est
/// plusieurs centaines de mégaoctets relus pour rien.
///
/// La clé porte la résolution demandée : la même réunion peut être affichée
/// dans la frise (quelques centaines de pics) et dans l'éditeur audio (deux
/// mille), et mélanger les deux donnerait une onde étirée.
@MainActor
final class AudioWaveformCache {

    static let shared = AudioWaveformCache()

    private struct Cle: Hashable {
        let path: String
        let count: Int
    }

    private var cache: [Cle: [Float]] = [:]
    /// Décimations en vol, pour ne pas lancer deux fois le même décodage quand
    /// deux surfaces demandent la même onde dans le même rendu.
    private var enCours: [Cle: Task<[Float], Never>] = [:]

    /// Nombre d'entrées mémorisées. Pour les tests et le journal.
    var cachedCount: Int { cache.count }

    /// Non privé : la production passe par `.shared`, mais un test — et une
    /// prévisualisation — doit pouvoir tenir son propre cache. Deux tests
    /// parallèles qui comptent les entrées d'un singleton commun mesurent le
    /// travail de l'autre.
    init() {}

    /// Pics de `url` à la résolution `count`.
    ///
    /// Rend `[]` — et le mémorise — quand le fichier est illisible : la frise
    /// dessine alors une piste plate avec ses marqueurs, ce qui est exact, au
    /// lieu de retenter le décodage indéfiniment.
    func peaks(url: URL, count: Int) async -> [Float] {
        let cle = Cle(path: url.path, count: count)
        if let connus = cache[cle] { return connus }
        if let tache = enCours[cle] { return await tache.value }

        let tache = Task<[Float], Never> {
            do {
                return try await AudioWaveform.peaks(url: url, count: count)
            } catch {
                waveformLog.info("peaks failed: \(url.lastPathComponent, privacy: .public)")
                return []
            }
        }
        enCours[cle] = tache
        let pics = await tache.value
        enCours[cle] = nil
        cache[cle] = pics
        return pics
    }

    /// Oublie toutes les résolutions d'un fichier : l'édition audio le
    /// réécrit, l'onde mémorisée ne le décrit plus.
    func invalidate(url: URL) {
        let chemin = url.path
        for cle in cache.keys where cle.path == chemin {
            cache[cle] = nil
        }
        for cle in enCours.keys where cle.path == chemin {
            enCours[cle]?.cancel()
            enCours[cle] = nil
        }
    }
}
