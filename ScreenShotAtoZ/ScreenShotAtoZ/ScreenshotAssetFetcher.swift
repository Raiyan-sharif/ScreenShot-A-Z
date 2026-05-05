//
//  ScreenshotAssetFetcher.swift
//  ScreenShotAtoZ
//

import Foundation
import Photos

enum ScreenshotAssetFetcher {
    static func fetchAllScreenshotAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let smart = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        if let album = smart.firstObject {
            let result = PHAsset.fetchAssets(in: album, options: options)
            var list: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in list.append(asset) }
            if !list.isEmpty { return list }
        }

        let fallback = PHFetchOptions()
        fallback.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fallback.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let r = PHAsset.fetchAssets(with: .image, options: fallback)
        var list: [PHAsset] = []
        r.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }
}
