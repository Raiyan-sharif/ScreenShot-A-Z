//
//  ScreenshotFullScreenViewController.swift
//  ScreenShotAtoZ
//

import Photos
import UIKit

final class ScreenshotFullScreenViewController: UIViewController {
    private let asset: PHAsset
    private let imageManager = PHImageManager.default()
    private let imageView = UIImageView()
    private var imageRequestID: PHImageRequestID?

    init(asset: PHAsset) {
        self.asset = asset
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let imageRequestID {
            imageManager.cancelImageRequest(imageRequestID)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        loadImage()
    }

    private func loadImage() {
        let w = CGFloat(asset.pixelWidth)
        let h = CGFloat(asset.pixelHeight)
        let maxSide: CGFloat = 4096
        let scale = min(1, maxSide / max(w, h, 1))
        let target = CGSize(width: max(w * scale, 1), height: max(h * scale, 1))

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        imageRequestID = imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            Task { @MainActor in
                self?.imageView.image = image
            }
        }
    }
}
