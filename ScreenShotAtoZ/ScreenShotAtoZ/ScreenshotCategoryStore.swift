//
//  ScreenshotCategoryStore.swift
//  ScreenShotAtoZ
//

import Foundation
import Photos

@MainActor
final class ScreenshotCategoryStore {
    private struct Metadata: Codable {
        var version: Int
        var categoryOverrides: [String: String]
        var favorites: Set<String>
        var tagsByAsset: [String: [String]]
        var ocrTextByAsset: [String: String]
        var ocrScannedAssetIDs: Set<String>

        static let currentVersion = 1

        static let empty = Metadata(
            version: currentVersion,
            categoryOverrides: [:],
            favorites: [],
            tagsByAsset: [:],
            ocrTextByAsset: [:],
            ocrScannedAssetIDs: []
        )
    }

    private var metadata: Metadata = .empty
    private let fileURL: URL
    private let legacyOverridesURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("screenshot_metadata.json", isDirectory: false)
        legacyOverridesURL = dir.appendingPathComponent("category_overrides.json", isDirectory: false)
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Metadata.self, from: data) {
            metadata = decoded
            normalizeAndSaveIfNeeded()
            return
        }

        // Migration from old overrides-only file.
        if let data = try? Data(contentsOf: legacyOverridesURL),
           let overrides = try? JSONDecoder().decode([String: String].self, from: data) {
            metadata = Metadata(
                version: Metadata.currentVersion,
                categoryOverrides: overrides,
                favorites: [],
                tagsByAsset: [:],
                ocrTextByAsset: [:],
                ocrScannedAssetIDs: []
            )
            save()
            return
        }

        metadata = .empty
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func autoCategory(for asset: PHAsset) -> ScreenshotCategory {
        ScreenshotAutoClassifier.autoCategory(for: asset)
    }

    func effectiveCategory(for asset: PHAsset) -> ScreenshotCategory {
        if let raw = metadata.categoryOverrides[asset.localIdentifier],
           let c = ScreenshotCategory(rawValue: raw) {
            return c
        }
        if metadata.categoryOverrides[asset.localIdentifier] != nil {
            metadata.categoryOverrides.removeValue(forKey: asset.localIdentifier)
            save()
        }
        return autoCategory(for: asset)
    }

    func setOverride(for asset: PHAsset, category: ScreenshotCategory?) {
        if let category {
            metadata.categoryOverrides[asset.localIdentifier] = category.rawValue
        } else {
            metadata.categoryOverrides.removeValue(forKey: asset.localIdentifier)
        }
        save()
    }

    func hasOverride(for asset: PHAsset) -> Bool {
        guard let raw = metadata.categoryOverrides[asset.localIdentifier] else { return false }
        return ScreenshotCategory(rawValue: raw) != nil
    }

    func isFavorite(_ asset: PHAsset) -> Bool {
        metadata.favorites.contains(asset.localIdentifier)
    }

    func setFavorite(_ isFavorite: Bool, for asset: PHAsset) {
        if isFavorite {
            metadata.favorites.insert(asset.localIdentifier)
        } else {
            metadata.favorites.remove(asset.localIdentifier)
        }
        save()
    }

    func toggleFavorite(for asset: PHAsset) {
        setFavorite(!isFavorite(asset), for: asset)
    }

    func tags(for asset: PHAsset) -> [String] {
        metadata.tagsByAsset[asset.localIdentifier] ?? []
    }

    func setTags(_ tags: [String], for asset: PHAsset) {
        let normalized = normalizedTags(tags)
        if normalized.isEmpty {
            metadata.tagsByAsset.removeValue(forKey: asset.localIdentifier)
        } else {
            metadata.tagsByAsset[asset.localIdentifier] = normalized
        }
        save()
    }

    func addTag(_ tag: String, for asset: PHAsset) {
        var tags = self.tags(for: asset)
        tags.append(tag)
        setTags(tags, for: asset)
    }

    func removeTag(_ tag: String, for asset: PHAsset) {
        let tags = self.tags(for: asset).filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        setTags(tags, for: asset)
    }

    func allKnownTags() -> [String] {
        let set = Set(metadata.tagsByAsset.values.flatMap { $0 })
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func ocrText(for asset: PHAsset) -> String? {
        metadata.ocrTextByAsset[asset.localIdentifier]
    }

    func setOCRText(_ text: String, for asset: PHAsset) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.ocrScannedAssetIDs.insert(asset.localIdentifier)
        if trimmed.isEmpty {
            metadata.ocrTextByAsset.removeValue(forKey: asset.localIdentifier)
        } else {
            metadata.ocrTextByAsset[asset.localIdentifier] = trimmed
        }
        save()
    }

    func hasScannedOCR(_ asset: PHAsset) -> Bool {
        metadata.ocrScannedAssetIDs.contains(asset.localIdentifier)
    }

    func hasOCRText(_ asset: PHAsset) -> Bool {
        guard let text = ocrText(for: asset) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prune(toValidLocalIdentifiers valid: Set<String>) {
        let beforeOverrides = metadata.categoryOverrides.count
        let beforeFavorites = metadata.favorites.count
        let beforeTags = metadata.tagsByAsset.count
        let beforeOCR = metadata.ocrTextByAsset.count
        let beforeScanned = metadata.ocrScannedAssetIDs.count

        metadata.categoryOverrides = metadata.categoryOverrides.filter { valid.contains($0.key) }
        metadata.favorites = Set(metadata.favorites.filter { valid.contains($0) })
        metadata.tagsByAsset = metadata.tagsByAsset.filter { valid.contains($0.key) }
        metadata.ocrTextByAsset = metadata.ocrTextByAsset.filter { valid.contains($0.key) }
        metadata.ocrScannedAssetIDs = Set(metadata.ocrScannedAssetIDs.filter { valid.contains($0) })

        if beforeOverrides != metadata.categoryOverrides.count ||
            beforeFavorites != metadata.favorites.count ||
            beforeTags != metadata.tagsByAsset.count ||
            beforeOCR != metadata.ocrTextByAsset.count ||
            beforeScanned != metadata.ocrScannedAssetIDs.count {
            save()
        }
    }

    private func normalizeAndSaveIfNeeded() {
        var changed = false
        if metadata.version != Metadata.currentVersion {
            metadata.version = Metadata.currentVersion
            changed = true
        }
        let validOverrides = metadata.categoryOverrides.filter { ScreenshotCategory(rawValue: $0.value) != nil }
        if validOverrides.count != metadata.categoryOverrides.count {
            metadata.categoryOverrides = validOverrides
            changed = true
        }
        let normalizedTagsMap = metadata.tagsByAsset.mapValues { normalizedTags($0) }.filter { !$0.value.isEmpty }
        if normalizedTagsMap != metadata.tagsByAsset {
            metadata.tagsByAsset = normalizedTagsMap
            changed = true
        }
        let validScanned = Set(metadata.ocrScannedAssetIDs.filter { !($0.isEmpty) })
        if validScanned != metadata.ocrScannedAssetIDs {
            metadata.ocrScannedAssetIDs = validScanned
            changed = true
        }
        if changed { save() }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
