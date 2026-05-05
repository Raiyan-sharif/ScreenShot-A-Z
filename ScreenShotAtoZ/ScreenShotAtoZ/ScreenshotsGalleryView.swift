//
//  ScreenshotsGalleryView.swift
//  ScreenShotAtoZ
//

import SwiftUI
import UIKit

struct ScreenshotsGalleryView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let root = ScreenshotsGalleryViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
