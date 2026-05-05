//
//  ScreenshotCategoryStore.swift
//  ScreenShotAtoZ
//

import Foundation
import Photos

@MainActor
final class ScreenshotCategoryStore {
    private var overrides: [String: String] = [:]
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("category_overrides.json", isDirectory: false)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            overrides = [:]
            return
        }
        overrides = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func autoCategory(for asset: PHAsset) -> ScreenshotCategory {
        ScreenshotAutoClassifier.autoCategory(for: asset)
    }

    func effectiveCategory(for asset: PHAsset) -> ScreenshotCategory {
        if let raw = overrides[asset.localIdentifier],
           let c = ScreenshotCategory(rawValue: raw) {
            return c
        }
        if overrides[asset.localIdentifier] != nil {
            overrides.removeValue(forKey: asset.localIdentifier)
            save()
        }
        return autoCategory(for: asset)
    }

    func setOverride(for asset: PHAsset, category: ScreenshotCategory?) {
        if let category {
            overrides[asset.localIdentifier] = category.rawValue
        } else {
            overrides.removeValue(forKey: asset.localIdentifier)
        }
        save()
    }

    func hasOverride(for asset: PHAsset) -> Bool {
        guard let raw = overrides[asset.localIdentifier] else { return false }
        return ScreenshotCategory(rawValue: raw) != nil
    }

    func prune(toValidLocalIdentifiers valid: Set<String>) {
        let before = overrides.count
        overrides = overrides.filter { valid.contains($0.key) }
        if overrides.count != before { save() }
    }
}
