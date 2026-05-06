//
//  ScreenshotThumbnailCell.swift
//  ScreenShotAtoZ
//

import Photos
import UIKit

final class ScreenshotThumbnailCell: UICollectionViewCell {
    static let reuseIdentifier = "ScreenshotThumbnailCell"

    let photoImageView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.layer.cornerRadius = 4
        v.layer.cornerCurve = .continuous
        v.backgroundColor = .secondarySystemFill
        return v
    }()

    let menuButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        b.setImage(UIImage(systemName: "ellipsis.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        b.layer.cornerRadius = 14
        b.clipsToBounds = true
        b.showsMenuAsPrimaryAction = true
        return b
    }()

    private let favoriteBadge: UIImageView = {
        let image = UIImageView(image: UIImage(systemName: "star.fill"))
        image.tintColor = .systemYellow
        image.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        image.layer.cornerRadius = 12
        image.clipsToBounds = true
        image.contentMode = .center
        image.isHidden = true
        return image
    }()

    var onLongPress: (() -> Void)?
    private var longPress: UILongPressGestureRecognizer?
    private var requestID: PHImageRequestID?
    private weak var cachingManager: PHCachingImageManager?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(photoImageView)
        contentView.addSubview(menuButton)
        contentView.addSubview(favoriteBadge)
        photoImageView.translatesAutoresizingMaskIntoConstraints = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            photoImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            photoImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            photoImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            photoImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            menuButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            menuButton.widthAnchor.constraint(equalToConstant: 28),
            menuButton.heightAnchor.constraint(equalToConstant: 28),
            favoriteBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            favoriteBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            favoriteBadge.widthAnchor.constraint(equalToConstant: 24),
            favoriteBadge.heightAnchor.constraint(equalToConstant: 24),
        ])
        photoImageView.isUserInteractionEnabled = true
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.4
        photoImageView.addGestureRecognizer(lp)
        longPress = lp
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        asset: PHAsset,
        imageManager: PHCachingImageManager,
        targetSize: CGSize,
        menu: UIMenu?,
        isFavorite: Bool,
        onLongPress: @escaping () -> Void
    ) {
        if let requestID {
            imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }
        cachingManager = imageManager
        self.onLongPress = onLongPress
        menuButton.menu = menu
        menuButton.showsMenuAsPrimaryAction = true
        favoriteBadge.isHidden = !isFavorite

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast

        requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: opts
        ) { [weak self] image, _ in
            Task { @MainActor in
                self?.photoImageView.image = image
            }
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        onLongPress?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let requestID {
            cachingManager?.cancelImageRequest(requestID)
        }
        cachingManager = nil
        requestID = nil
        photoImageView.image = nil
        menuButton.menu = nil
        favoriteBadge.isHidden = true
        onLongPress = nil
    }
}
