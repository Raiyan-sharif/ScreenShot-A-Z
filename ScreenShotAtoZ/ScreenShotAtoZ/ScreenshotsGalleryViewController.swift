//
//  ScreenshotsGalleryViewController.swift
//  ScreenShotAtoZ
//

import Photos
import PhotosUI
import UIKit

final class ScreenshotsGalleryViewController: UIViewController {
    private let store = ScreenshotCategoryStore()
    private let imageManager = PHCachingImageManager()
    nonisolated private let photoChangeHandler = PhotoLibraryChangeHandler()

    private var assetById: [String: PHAsset] = [:]
    private var assets: [PHAsset] = []

    private var dataSource: UICollectionViewDiffableDataSource<ScreenshotCategory, String>!
    private var collectionView: UICollectionView!
    private var thumbnailPixelSize = CGSize(width: 200, height: 200)

    private let deniedStack = UIStackView()
    private let emptyLabel = UILabel()
    private var didRegisterLibraryObserver = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Screenshots"
        view.backgroundColor = .systemBackground

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeCompositionalLayout())
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ScreenshotThumbnailCell.self, forCellWithReuseIdentifier: ScreenshotThumbnailCell.reuseIdentifier)
        collectionView.register(
            ScreenshotSectionHeaderView.self,
            forSupplementaryViewOfKind: ScreenshotSectionHeaderView.elementKind,
            withReuseIdentifier: ScreenshotSectionHeaderView.reuseIdentifier
        )

        configureDeniedAndEmptyUI()
        configureDataSource()

        view.addSubview(collectionView)
        view.addSubview(deniedStack)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            deniedStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            deniedStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            deniedStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            deniedStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Manage library",
            style: .plain,
            target: self,
            action: #selector(manageLibraryTapped)
        )
        navigationItem.rightBarButtonItem?.isHidden = true

        collectionView.isHidden = true
        deniedStack.isHidden = true
        emptyLabel.isHidden = true

        photoChangeHandler.gallery = self
    }

    deinit {
        if didRegisterLibraryObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(photoChangeHandler)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let columns: CGFloat = 3
        let gutter: CGFloat = 12
        let w = max(1, (view.bounds.width - gutter * 2) / columns)
        let s = w * view.traitCollection.displayScale
        thumbnailPixelSize = CGSize(width: s, height: s)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func makeCompositionalLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(40)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: ScreenshotSectionHeaderView.elementKind,
                alignment: .top
            )

            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / 3.0),
                heightDimension: .fractionalWidth(1.0 / 3.0)
            ))
            item.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)

            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalWidth(1.0 / 3.0)
                ),
                subitem: item,
                count: 3
            )

            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [header]
            section.interGroupSpacing = 4
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 16, trailing: 6)
            return section
        }
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<ScreenshotCategory, String>(
            collectionView: collectionView,
            cellProvider: { [weak self] collectionView, indexPath, itemId in
                guard let self,
                      let asset = self.assetById[itemId] else {
                    return collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotThumbnailCell.reuseIdentifier, for: indexPath) as! ScreenshotThumbnailCell
                }
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotThumbnailCell.reuseIdentifier, for: indexPath) as! ScreenshotThumbnailCell
                cell.configure(
                    asset: asset,
                    imageManager: self.imageManager,
                    targetSize: self.thumbnailPixelSize,
                    menu: self.makeCategoryMenu(for: asset),
                    onLongPress: { [weak self] in self?.pushDetails(for: asset) }
                )
                return cell
            }
        )
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self, kind == ScreenshotSectionHeaderView.elementKind else {
                return UICollectionReusableView()
            }
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: ScreenshotSectionHeaderView.reuseIdentifier,
                for: indexPath
            ) as! ScreenshotSectionHeaderView
            let sectionId = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            header.titleLabel.text = sectionId.title
            return header
        }
    }

    private func configureDeniedAndEmptyUI() {
        deniedStack.axis = .vertical
        deniedStack.spacing = 16
        deniedStack.alignment = .center
        deniedStack.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Photo access is off. Enable it in Settings to see your screenshots."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)

        let button = UIButton(type: .system)
        button.setTitle("Open Settings", for: .normal)
        button.addAction(UIAction { [weak self] _ in self?.openSettings() }, for: .touchUpInside)

        deniedStack.addArrangedSubview(label)
        deniedStack.addArrangedSubview(button)

        emptyLabel.text = "No screenshots in your library."
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applyAuthorizationStatus(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            deniedStack.isHidden = true
            collectionView.isHidden = false
            navigationItem.rightBarButtonItem?.isHidden = status != .limited
            registerLibraryObserverIfNeeded()
            loadAssetsFromLibrary()
        case .denied, .restricted:
            deniedStack.isHidden = false
            collectionView.isHidden = true
            emptyLabel.isHidden = true
            navigationItem.rightBarButtonItem?.isHidden = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    self.applyAuthorizationStatus(newStatus)
                }
            }
        @unknown default:
            break
        }
    }

    private func registerLibraryObserverIfNeeded() {
        guard !didRegisterLibraryObserver else { return }
        PHPhotoLibrary.shared().register(photoChangeHandler)
        didRegisterLibraryObserver = true
    }

    func loadAssetsFromLibrary() {
        let list = ScreenshotAssetFetcher.fetchAllScreenshotAssets()
        assets = list
        assetById = Dictionary(uniqueKeysWithValues: list.map { ($0.localIdentifier, $0) })
        store.prune(toValidLocalIdentifiers: Set(list.map(\.localIdentifier)))
        rebuildAndApplySnapshot()
    }

    func reloadAfterCategoryChange() {
        rebuildAndApplySnapshot()
    }

    private func rebuildAndApplySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<ScreenshotCategory, String>()
        for cat in ScreenshotCategory.orderedForDisplay {
            let ids = assets.filter { store.effectiveCategory(for: $0) == cat }.map(\.localIdentifier)
            guard !ids.isEmpty else { continue }
            snapshot.appendSections([cat])
            snapshot.appendItems(ids, toSection: cat)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
        let empty = snapshot.sectionIdentifiers.isEmpty
        emptyLabel.isHidden = !empty || collectionView.isHidden
    }

    private func makeCategoryMenu(for asset: PHAsset) -> UIMenu {
        let current = store.effectiveCategory(for: asset)
        let pickActions: [UIAction] = ScreenshotCategory.orderedForDisplay.map { cat in
            UIAction(title: cat.title, state: current == cat ? .on : .off) { [weak self] _ in
                self?.store.setOverride(for: asset, category: cat)
                self?.rebuildAndApplySnapshot()
            }
        }
        let clear = UIAction(
            title: "Use automatic",
            attributes: store.hasOverride(for: asset) ? [] : .disabled
        ) { [weak self] _ in
            self?.store.setOverride(for: asset, category: nil)
            self?.rebuildAndApplySnapshot()
        }
        return UIMenu(title: "Category", children: pickActions + [clear])
    }

    private func pushDetails(for asset: PHAsset) {
        let vc = ScreenshotDetailsViewController(asset: asset, categoryStore: store) { [weak self] in
            self?.rebuildAndApplySnapshot()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func manageLibraryTapped() {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension ScreenshotsGalleryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let asset = assetById[id] else { return }
        let vc = ScreenshotFullScreenViewController(asset: asset)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension ScreenshotsGalleryViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let targets = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }.compactMap { assetById[$0] }
        guard !targets.isEmpty else { return }
        imageManager.startCachingImages(
            for: targets,
            targetSize: thumbnailPixelSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let targets = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }.compactMap { assetById[$0] }
        guard !targets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: targets,
            targetSize: thumbnailPixelSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}

