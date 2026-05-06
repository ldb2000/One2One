import Foundation
import SwiftData
import os

private let mgrLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// CRUD on `ManagerReportItem` plus archivage helpers and duplicate detection.
/// All methods are synchronous and run on the model context's actor (typically
/// the MainActor for SwiftUI).
enum ManagerReportService {

    /// Threshold (exclusive) above which two ranges on the same source are flagged
    /// as possible duplicates. Spec decision Q10-D.
    static let duplicateOverlapThreshold: Double = 0.5

    // MARK: - Add from selection

    /// Adds a new item issued from a text selection. Detects overlap against
    /// existing items on the same `(sourceMeeting, sourceField)` pair and, if
    /// > 50%, marks both items as possible duplicates of each other.
    @discardableResult
    static func add(
        snippet: String,
        sourceField: String,
        range: NSRange,
        sourceMeeting: Meeting?,
        contextBefore: String,
        contextAfter: String,
        category: String,
        tag: String,
        aiSuggestedCategory: String?,
        in context: ModelContext
    ) throws -> ManagerReportItem {
        let item = ManagerReportItem(
            rawSnippet: snippet,
            sourceField: sourceField,
            sourceRangeStart: range.location,
            sourceRangeLength: range.length,
            sourceMeeting: sourceMeeting
        )
        item.contextBefore = contextBefore
        item.contextAfter = contextAfter
        item.category = category
        item.tag = tag
        item.aiSuggestedCategory = aiSuggestedCategory
        context.insert(item)

        // Duplicate detection — only meaningful when we have a source meeting
        // and a non-zero range.
        if let sourceMeeting, range.length > 0 {
            let existing = try fetchItemsForSource(meeting: sourceMeeting, field: sourceField, in: context)
            for other in existing where other.stableID != item.stableID {
                if overlap(rangeA: range, rangeB: NSRange(location: other.sourceRangeStart, length: other.sourceRangeLength)) > duplicateOverlapThreshold {
                    item.duplicateOfStableID = other.stableID.uuidString
                    other.duplicateOfStableID = item.stableID.uuidString
                    mgrLog.info("add: duplicate detected with \(other.stableID.uuidString, privacy: .public)")
                    break
                }
            }
        }

        mgrLog.info("add: item created field=\(sourceField, privacy: .public) snippet=\"\(String(snippet.prefix(40)), privacy: .public)\"")
        return item
    }

    /// Adds a manual item (no source selection). Always non-failing.
    @discardableResult
    static func addManual(
        snippet: String,
        category: String,
        tag: String,
        in context: ModelContext
    ) -> ManagerReportItem {
        let item = ManagerReportItem(manualSnippet: snippet, category: category)
        item.tag = tag
        context.insert(item)
        mgrLog.info("addManual: \"\(String(snippet.prefix(40)), privacy: .public)\"")
        return item
    }

    // MARK: - Delete

    static func delete(item: ManagerReportItem, in context: ModelContext) {
        // If the item participated in a duplicate pair, clear the back-reference
        // so the surviving item no longer carries a stale link.
        if !item.duplicateOfStableID.isEmpty {
            if let other = try? fetchByStableID(item.duplicateOfStableID, in: context) {
                other.duplicateOfStableID = ""
            }
        }
        context.delete(item)
    }

    // MARK: - Archive

    /// Marks all checked, non-archived items as archived in the given meeting.
    /// Returns the items that were archived (for inclusion in the snapshot JSON).
    @discardableResult
    static func archiveCheckedItems(in meeting: Meeting, context: ModelContext) -> [ManagerReportItem] {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.isCompleted == true && $0.archivedAt == nil }
        )
        let toArchive = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        for item in toArchive {
            item.archivedAt = now
            item.archivedInMeeting = meeting
        }
        mgrLog.info("archiveCheckedItems: \(toArchive.count) item(s) archived in meeting \(meeting.title, privacy: .public)")
        return toArchive
    }

    // MARK: - Queries

    static func currentItems(in context: ModelContext) throws -> [ManagerReportItem] {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.manualOrder), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    static func archivedItems(in context: ModelContext) throws -> [ManagerReportItem] {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    static func itemsHighlightingSource(meeting: Meeting, field: String, in context: ModelContext) -> [ManagerReportItem] {
        let target = meeting.persistentModelID
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.sourceField == field && $0.archivedAt == nil }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { $0.sourceMeeting?.persistentModelID == target }
    }

    // MARK: - Helpers

    private static func fetchItemsForSource(meeting: Meeting, field: String, in context: ModelContext) throws -> [ManagerReportItem] {
        let target = meeting.persistentModelID
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.sourceField == field }
        )
        let all = try context.fetch(descriptor)
        return all.filter { $0.sourceMeeting?.persistentModelID == target }
    }

    private static func fetchByStableID(_ uuidString: String, in context: ModelContext) throws -> ManagerReportItem? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        return try context.fetch(descriptor).first
    }

    /// Returns overlap ratio in [0, 1] of two NSRanges, normalized by the
    /// smaller range's length. 0 if either range is empty.
    static func overlap(rangeA: NSRange, rangeB: NSRange) -> Double {
        guard rangeA.length > 0, rangeB.length > 0 else { return 0 }
        let aStart = rangeA.location
        let aEnd = rangeA.location + rangeA.length
        let bStart = rangeB.location
        let bEnd = rangeB.location + rangeB.length
        let overlapStart = max(aStart, bStart)
        let overlapEnd = min(aEnd, bEnd)
        let overlap = max(0, overlapEnd - overlapStart)
        let denom = max(1, min(rangeA.length, rangeB.length))
        return Double(overlap) / Double(denom)
    }
}
