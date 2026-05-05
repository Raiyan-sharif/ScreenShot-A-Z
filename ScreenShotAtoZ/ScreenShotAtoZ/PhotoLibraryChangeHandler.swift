//
//  PhotoLibraryChangeHandler.swift
//  ScreenShotAtoZ
//

import Photos
import UIKit

/// Bridges `PHPhotoLibraryChangeObserver` without MainActor `deinit` / isolation issues.
final class PhotoLibraryChangeHandler: NSObject, PHPhotoLibraryChangeObserver {
    weak var gallery: ScreenshotsGalleryViewController?

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.gallery?.loadAssetsFromLibrary()
        }
    }
}
