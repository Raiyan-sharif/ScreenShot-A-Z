//
//  ScreenshotsGalleryViewController.swift
//  ScreenShotAtoZ
//

import Photos
import PhotosUI
import UIKit

private enum SortMode: String, CaseIterable {
    case newestFirst
    case oldestFirst
}

final class ScreenshotsGalleryViewController: UIViewController {
    private let store = ScreenshotCategoryStore()
    private let imageManager = PHCachingImageManager()
    nonisolated private let photoChangeHandler = PhotoLibraryChangeHandler()

    private var assetById: [String: PHAsset] = [:]
    private var allAssets: [PHAsset] = []
    private var filteredAssets: [PHAsset] = []

    private var searchQuery: String = ""
    private var sortMode: SortMode = .newestFirst
    private var filterFavoritesOnly = false
    private var filterHasText: Bool?
    private var filterCategory: ScreenshotCategory?

    private var isSelectionMode = false

    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var collectionView: UICollectionView!
    private var thumbnailPixelSize = CGSize(width: 200, height: 200)

    private let deniedStack = UIStackView()
    private let emptyLabel = UILabel()
    private var didRegisterLibraryObserver = false
    private var ocrIndexTask: Task<Void, Never>?
    private var ocrIndexingInProgress = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Screenshots"
        view.backgroundColor = .systemBackground

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeCompositionalLayout())
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.allowsMultipleSelection = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ScreenshotThumbnailCell.self, forCellWithReuseIdentifier: ScreenshotThumbnailCell.reuseIdentifier)
        collectionView.register(
            ScreenshotSectionHeaderView.self,
            forSupplementaryViewOfKind: ScreenshotSectionHeaderView.elementKind,
            withReuseIdentifier: ScreenshotSectionHeaderView.reuseIdentifier
        )

        configureDeniedAndEmptyUI()
        configureDataSource()
        configureSearch()
        configureNavButtons()

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

        collectionView.isHidden = true
        deniedStack.isHidden = true
        emptyLabel.isHidden = true

        photoChangeHandler.gallery = self
    }

    deinit {
        ocrIndexTask?.cancel()
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
        dataSource = UICollectionViewDiffableDataSource<String, String>(
            collectionView: collectionView,
            cellProvider: { [weak self] collectionView, indexPath, itemId in
                guard let self,
                      let asset = self.assetById[self.assetID(fromCompositeID: itemId)] else {
                    return collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotThumbnailCell.reuseIdentifier, for: indexPath) as! ScreenshotThumbnailCell
                }
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotThumbnailCell.reuseIdentifier, for: indexPath) as! ScreenshotThumbnailCell
                cell.configure(
                    asset: asset,
                    imageManager: self.imageManager,
                    targetSize: self.thumbnailPixelSize,
                    menu: self.makeItemMenu(for: asset),
                    isFavorite: self.store.isFavorite(asset),
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
            header.titleLabel.text = self.sectionTitle(for: sectionId)
            return header
        }
    }

    private func configureSearch() {
        let search = UISearchController(searchResultsController: nil)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "Search metadata or scanned text"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func configureNavButtons() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Manage library", style: .plain, target: self, action: #selector(manageLibraryTapped)),
            UIBarButtonItem(title: "Filter", style: .plain, target: self, action: #selector(showSortFilterSheet)),
        ]
        navigationItem.rightBarButtonItems?.first?.isHidden = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(toggleSelectionMode))
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

        emptyLabel.text = "No screenshots found with current filters."
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
            navigationItem.rightBarButtonItems?.first?.isHidden = status != .limited
            registerLibraryObserverIfNeeded()
            loadAssetsFromLibrary()
        case .denied, .restricted:
            deniedStack.isHidden = false
            collectionView.isHidden = true
            emptyLabel.isHidden = true
            navigationItem.rightBarButtonItems?.first?.isHidden = true
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
        allAssets = list
        assetById = Dictionary(uniqueKeysWithValues: list.map { ($0.localIdentifier, $0) })
        store.prune(toValidLocalIdentifiers: Set(list.map(\.localIdentifier)))
        applyQueryAndRefresh()
    }

    private func applyQueryAndRefresh() {
        if !searchQuery.isEmpty {
            scheduleOCRIndexingForSearch()
        }
        filteredAssets = allAssets.filter { asset in
            if filterFavoritesOnly, !store.isFavorite(asset) { return false }
            if let filterHasText, store.hasOCRText(asset) != filterHasText { return false }
            if let filterCategory, store.effectiveCategory(for: asset) != filterCategory { return false }
            if searchQuery.isEmpty { return true }
            let q = searchQuery.lowercased()
            let textMatch = store.ocrText(for: asset)?.lowercased().contains(q) ?? false
            let tagMatch = store.tags(for: asset).contains { $0.lowercased().contains(q) }
            let metadataMatch = metadataSearchText(for: asset).contains(q)
            return textMatch || tagMatch || metadataMatch
        }

        filteredAssets.sort { lhs, rhs in
            switch sortMode {
            case .newestFirst:
                return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
            case .oldestFirst:
                return (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
            }
        }
        rebuildAndApplySnapshot()
    }

    private func rebuildAndApplySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        let favorites = filteredAssets.filter { store.isFavorite($0) }
        let tagged = filteredAssets.filter { !store.tags(for: $0).isEmpty }
        let textDetected = filteredAssets.filter { store.hasOCRText($0) }

        if !favorites.isEmpty {
            snapshot.appendSections(["smart:favorites"])
            snapshot.appendItems(favorites.map { compositeID(section: "smart:favorites", asset: $0.localIdentifier) }, toSection: "smart:favorites")
        }
        if !tagged.isEmpty {
            snapshot.appendSections(["smart:tagged"])
            snapshot.appendItems(tagged.map { compositeID(section: "smart:tagged", asset: $0.localIdentifier) }, toSection: "smart:tagged")
        }
        if !textDetected.isEmpty {
            snapshot.appendSections(["smart:text"])
            snapshot.appendItems(textDetected.map { compositeID(section: "smart:text", asset: $0.localIdentifier) }, toSection: "smart:text")
        }

        for cat in ScreenshotCategory.orderedForDisplay {
            let ids = filteredAssets
                .filter { store.effectiveCategory(for: $0) == cat }
                .map(\.localIdentifier)
            guard !ids.isEmpty else { continue }
            let section = "cat:\(cat.rawValue)"
            snapshot.appendSections([section])
            snapshot.appendItems(ids.map { compositeID(section: section, asset: $0) }, toSection: section)
        }

        dataSource.apply(snapshot, animatingDifferences: true)
        let empty = snapshot.sectionIdentifiers.isEmpty
        emptyLabel.isHidden = !empty || collectionView.isHidden
    }

    private func makeItemMenu(for asset: PHAsset) -> UIMenu {
        let categoryMenu = makeCategoryMenu(for: asset)
        let favoriteTitle = store.isFavorite(asset) ? "Remove favorite" : "Add favorite"
        let favoriteAction = UIAction(title: favoriteTitle, image: UIImage(systemName: "star")) { [weak self] _ in
            guard let self else { return }
            self.store.toggleFavorite(for: asset)
            self.applyQueryAndRefresh()
        }
        let tagAction = UIAction(title: "Edit tags", image: UIImage(systemName: "tag")) { [weak self] _ in
            self?.showTagEditor(for: asset)
        }
        return UIMenu(title: "", children: [favoriteAction, tagAction, categoryMenu])
    }

    private func makeCategoryMenu(for asset: PHAsset) -> UIMenu {
        let current = store.effectiveCategory(for: asset)
        let pickActions: [UIAction] = ScreenshotCategory.orderedForDisplay.map { cat in
            UIAction(title: cat.title, state: current == cat ? .on : .off) { [weak self] _ in
                self?.store.setOverride(for: asset, category: cat)
                self?.applyQueryAndRefresh()
            }
        }
        let clear = UIAction(
            title: "Use automatic",
            attributes: store.hasOverride(for: asset) ? [] : .disabled
        ) { [weak self] _ in
            self?.store.setOverride(for: asset, category: nil)
            self?.applyQueryAndRefresh()
        }
        return UIMenu(title: "Category", children: pickActions + [clear])
    }

    private func pushDetails(for asset: PHAsset) {
        let vc = ScreenshotDetailsViewController(
            asset: asset,
            categoryStore: store,
            onCategoriesDidChange: { [weak self] in self?.applyQueryAndRefresh() },
            onOCRUpdated: { [weak self] asset, text in
                self?.store.setOCRText(text, for: asset)
                self?.applyQueryAndRefresh()
            }
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func manageLibraryTapped() {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
    }

    @objc private func showSortFilterSheet() {
        let sheet = UIAlertController(title: "Sort & filter", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Sort: newest first", style: .default) { [weak self] _ in
            self?.sortMode = .newestFirst
            self?.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Sort: oldest first", style: .default) { [weak self] _ in
            self?.sortMode = .oldestFirst
            self?.applyQueryAndRefresh()
        })
        let favTitle = filterFavoritesOnly ? "Favorites only: on" : "Favorites only: off"
        sheet.addAction(UIAlertAction(title: favTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            self.filterFavoritesOnly.toggle()
            self.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Filter: text detected", style: .default) { [weak self] _ in
            self?.filterHasText = true
            self?.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Filter: no text", style: .default) { [weak self] _ in
            self?.filterHasText = false
            self?.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Clear text filter", style: .default) { [weak self] _ in
            self?.filterHasText = nil
            self?.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Clear all filters", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.filterCategory = nil
            self.filterFavoritesOnly = false
            self.filterHasText = nil
            self.sortMode = .newestFirst
            self.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true)
    }

    @objc private func toggleSelectionMode() {
        isSelectionMode.toggle()
        collectionView.allowsMultipleSelection = isSelectionMode
        navigationItem.leftBarButtonItem?.title = isSelectionMode ? "Done" : "Select"
        if isSelectionMode {
            navigationController?.setToolbarHidden(false, animated: true)
            configureBulkToolbar()
        } else {
            navigationController?.setToolbarHidden(true, animated: true)
            collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false) }
        }
    }

    private func configureBulkToolbar() {
        let assignCategory = UIBarButtonItem(title: "Category", style: .plain, target: self, action: #selector(bulkAssignCategory))
        let tags = UIBarButtonItem(title: "Tags", style: .plain, target: self, action: #selector(bulkSetTag))
        let favorite = UIBarButtonItem(title: "Favorite", style: .plain, target: self, action: #selector(bulkToggleFavorite))
        let share = UIBarButtonItem(title: "Share", style: .plain, target: self, action: #selector(bulkShare))
        toolbarItems = [assignCategory, .flexibleSpace(), tags, .flexibleSpace(), favorite, .flexibleSpace(), share]
    }

    private func selectedAssets() -> [PHAsset] {
        let paths = collectionView.indexPathsForSelectedItems ?? []
        let ids = paths.compactMap { dataSource.itemIdentifier(for: $0) }
        return ids.compactMap { assetById[assetID(fromCompositeID: $0)] }
    }

    @objc private func bulkAssignCategory() {
        let selected = selectedAssets()
        guard !selected.isEmpty else { return }
        let sheet = UIAlertController(title: "Bulk category", message: nil, preferredStyle: .actionSheet)
        for cat in ScreenshotCategory.orderedForDisplay {
            sheet.addAction(UIAlertAction(title: cat.title, style: .default) { [weak self] _ in
                guard let self else { return }
                selected.forEach { self.store.setOverride(for: $0, category: cat) }
                self.applyQueryAndRefresh()
            })
        }
        sheet.addAction(UIAlertAction(title: "Use automatic", style: .default) { [weak self] _ in
            guard let self else { return }
            selected.forEach { self.store.setOverride(for: $0, category: nil) }
            self.applyQueryAndRefresh()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func bulkSetTag() {
        let selected = selectedAssets()
        guard !selected.isEmpty else { return }
        let alert = UIAlertController(title: "Set tag on selected", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Tag name" }
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self,
                  let tag = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tag.isEmpty else { return }
            selected.forEach { self.store.addTag(tag, for: $0) }
            self.applyQueryAndRefresh()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func bulkToggleFavorite() {
        let selected = selectedAssets()
        guard !selected.isEmpty else { return }
        selected.forEach { store.toggleFavorite(for: $0) }
        applyQueryAndRefresh()
    }

    @objc private func bulkShare() {
        let selected = selectedAssets()
        guard !selected.isEmpty else { return }
        let group = DispatchGroup()
        var images: [UIImage] = []
        for asset in selected {
            group.enter()
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = true
            let size = CGSize(width: 2000, height: 2000)
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: opts) { image, _ in
                if let image { images.append(image) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !images.isEmpty else { return }
            let vc = UIActivityViewController(activityItems: images, applicationActivities: nil)
            self.present(vc, animated: true)
        }
    }

    private func showTagEditor(for asset: PHAsset) {
        let alert = UIAlertController(
            title: "Tags",
            message: "Current: \(store.tags(for: asset).joined(separator: ", "))",
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "Comma-separated tags"
            $0.text = self.store.tags(for: asset).joined(separator: ", ")
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            let tags = raw.split(separator: ",").map { String($0) }
            self.store.setTags(tags, for: asset)
            self.applyQueryAndRefresh()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func sectionTitle(for section: String) -> String {
        switch section {
        case "smart:favorites": return "Favorites"
        case "smart:tagged": return "Tagged"
        case "smart:text": return "Text detected"
        default:
            if section.hasPrefix("cat:") {
                let raw = String(section.dropFirst(4))
                return ScreenshotCategory(rawValue: raw)?.title ?? "Category"
            }
            return "Section"
        }
    }

    private func metadataSearchText(for asset: PHAsset) -> String {
        let categoryTitle = store.effectiveCategory(for: asset).title
        let favoriteText = store.isFavorite(asset) ? "favorite" : "not favorite"
        let dimensions = "\(asset.pixelWidth)x\(asset.pixelHeight)"
        let dateText: String = {
            guard let date = asset.creationDate else { return "" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }()
        return [
            categoryTitle,
            favoriteText,
            dimensions,
            asset.localIdentifier,
            dateText,
        ].joined(separator: " ").lowercased()
    }

    private func compositeID(section: String, asset: String) -> String {
        "\(section)||\(asset)"
    }

    private func assetID(fromCompositeID id: String) -> String {
        guard let separator = id.range(of: "||", options: .backwards) else { return id }
        return String(id[separator.upperBound...])
    }

    private func scheduleOCRIndexingForSearch() {
        if ocrIndexingInProgress { return }
        let assetsToScan = allAssets.filter { !store.hasScannedOCR($0) }
        guard !assetsToScan.isEmpty else { return }
        ocrIndexingInProgress = true
        let manager = imageManager
        let localStore = self.store
        ocrIndexTask = Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.ocrIndexingInProgress = false
                }
            }
            for asset in assetsToScan.prefix(120) {
                if Task.isCancelled { return }
                let image = await Self.loadImageForOCR(manager: manager, asset: asset)
                guard let image else { continue }
                guard let result = await ScreenshotTextRecognizer.recognizeText(in: image, cancellation: { Task.isCancelled }) else { continue }
                await MainActor.run {
                    localStore.setOCRText(result.text, for: asset)
                }
            }
            await MainActor.run {
                self?.applyQueryAndRefresh()
            }
        }
    }

    private static func loadImageForOCR(manager: PHCachingImageManager, asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data, let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
}

extension ScreenshotsGalleryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applyQueryAndRefresh()
    }
}

extension ScreenshotsGalleryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isSelectionMode else { return }
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let asset = assetById[assetID(fromCompositeID: id)] else { return }
        let vc = ScreenshotFullScreenViewController(asset: asset)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension ScreenshotsGalleryViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let targets = indexPaths
            .compactMap { dataSource.itemIdentifier(for: $0) }
            .compactMap { assetById[assetID(fromCompositeID: $0)] }
        guard !targets.isEmpty else { return }
        imageManager.startCachingImages(
            for: targets,
            targetSize: thumbnailPixelSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let targets = indexPaths
            .compactMap { dataSource.itemIdentifier(for: $0) }
            .compactMap { assetById[assetID(fromCompositeID: $0)] }
        guard !targets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: targets,
            targetSize: thumbnailPixelSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}
