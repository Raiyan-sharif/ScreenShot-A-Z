//
//  ScreenshotDetailsViewController.swift
//  ScreenShotAtoZ
//

import Photos
import UIKit

final class ScreenshotDetailsViewController: UIViewController {
    private let asset: PHAsset
    private let categoryStore: ScreenshotCategoryStore
    private let onCategoriesDidChange: () -> Void
    private let onOCRUpdated: (PHAsset, String) -> Void
    private let imageManager = PHImageManager.default()

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let overlayView = UIView()
    private let categoryButton = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)
    private let tagsButton = UIButton(type: .system)
    private let copyAllButton = UIButton(type: .system)
    private let textStatusLabel = UILabel()
    private let textView = UITextView()

    private var previewRequestID: PHImageRequestID?
    private var imageDataRequestID: PHImageRequestID?
    private var ocrCancelled = false
    private var ocrTask: Task<Void, Never>?

    init(
        asset: PHAsset,
        categoryStore: ScreenshotCategoryStore,
        onCategoriesDidChange: @escaping () -> Void,
        onOCRUpdated: @escaping (PHAsset, String) -> Void
    ) {
        self.asset = asset
        self.categoryStore = categoryStore
        self.onCategoriesDidChange = onCategoriesDidChange
        self.onOCRUpdated = onOCRUpdated
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        ocrCancelled = true
        if let previewRequestID { imageManager.cancelImageRequest(previewRequestID) }
        if let imageDataRequestID { imageManager.cancelImageRequest(imageDataRequestID) }
        ocrTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Details"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        scrollView.alwaysBounceVertical = true
        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true

        previewContainer.backgroundColor = .secondarySystemFill
        previewContainer.layer.cornerRadius = 8
        previewContainer.clipsToBounds = true
        previewContainer.heightAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true

        previewImageView.contentMode = .scaleAspectFit
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = true

        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(overlayView)
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            overlayView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
        ])

        categoryButton.addAction(UIAction { [weak self] _ in self?.presentCategoryPicker() }, for: .touchUpInside)
        favoriteButton.addAction(UIAction { [weak self] _ in self?.toggleFavorite() }, for: .touchUpInside)
        tagsButton.addAction(UIAction { [weak self] _ in self?.showTagsEditor() }, for: .touchUpInside)
        copyAllButton.setTitle("Copy all text", for: .normal)
        copyAllButton.addAction(UIAction { [weak self] _ in self?.copyAllText() }, for: .touchUpInside)
        refreshMetadataButtons()

        textStatusLabel.font = .preferredFont(forTextStyle: .subheadline)
        textStatusLabel.textColor = .secondaryLabel
        textStatusLabel.text = "Recognizing text…"

        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        stack.addArrangedSubview(previewContainer)
        stack.addArrangedSubview(makeMetadataRows())
        stack.addArrangedSubview(categoryButton)
        stack.addArrangedSubview(favoriteButton)
        stack.addArrangedSubview(tagsButton)
        stack.addArrangedSubview(copyAllButton)
        stack.addArrangedSubview(textStatusLabel)
        stack.addArrangedSubview(textView)

        scrollView.addSubview(stack)
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        if let cached = categoryStore.ocrText(for: asset), !cached.isEmpty {
            textStatusLabel.text = "Extracted text (cached)"
            textView.text = cached
        }
        loadPreviewAndRunOCR()
    }

    private func refreshMetadataButtons() {
        let eff = categoryStore.effectiveCategory(for: asset)
        let auto = categoryStore.autoCategory(for: asset)
        if categoryStore.hasOverride(for: asset) {
            categoryButton.setTitle("Category: \(eff.title) (override, auto was \(auto.title)) — tap to change", for: .normal)
        } else {
            categoryButton.setTitle("Category: \(eff.title) (automatic) — tap to change", for: .normal)
        }
        let favoriteTitle = categoryStore.isFavorite(asset) ? "Favorite: yes — tap to remove" : "Favorite: no — tap to add"
        favoriteButton.setTitle(favoriteTitle, for: .normal)
        let tags = categoryStore.tags(for: asset)
        tagsButton.setTitle("Tags: \(tags.isEmpty ? "none" : tags.joined(separator: ", ")) — tap to edit", for: .normal)
    }

    private func makeMetadataRows() -> UIStackView {
        let v = UIStackView()
        v.axis = .vertical
        v.spacing = 8
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let dateStr = asset.creationDate.map { df.string(from: $0) } ?? "—"
        v.addArrangedSubview(row(title: "Date", value: dateStr))
        v.addArrangedSubview(row(title: "Dimensions", value: "\(asset.pixelWidth) × \(asset.pixelHeight)"))
        let shortId = asset.localIdentifier.prefix(24) + (asset.localIdentifier.count > 24 ? "…" : "")
        v.addArrangedSubview(row(title: "Asset ID", value: String(shortId)))
        return v
    }

    private func row(title: String, value: String) -> UIView {
        let h = UIStackView()
        h.axis = .horizontal
        h.alignment = .firstBaseline
        h.spacing = 8
        let t = UILabel()
        t.text = title
        t.font = .preferredFont(forTextStyle: .subheadline)
        t.textColor = .secondaryLabel
        t.setContentHuggingPriority(.required, for: .horizontal)
        let v = UILabel()
        v.text = value
        v.font = .preferredFont(forTextStyle: .body)
        v.numberOfLines = 0
        v.textAlignment = .natural
        h.addArrangedSubview(t)
        h.addArrangedSubview(v)
        return h
    }

    private func presentCategoryPicker() {
        let sheet = UIAlertController(title: "Category", message: nil, preferredStyle: .actionSheet)
        for cat in ScreenshotCategory.orderedForDisplay {
            sheet.addAction(UIAlertAction(title: cat.title, style: .default) { [weak self] _ in
                guard let self else { return }
                self.categoryStore.setOverride(for: self.asset, category: cat)
                self.refreshMetadataButtons()
                self.onCategoriesDidChange()
            })
        }
        sheet.addAction(UIAlertAction(title: "Use automatic", style: .default) { [weak self] _ in
            guard let self else { return }
            self.categoryStore.setOverride(for: self.asset, category: nil)
            self.refreshMetadataButtons()
            self.onCategoriesDidChange()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = categoryButton
            pop.sourceRect = categoryButton.bounds
        }
        present(sheet, animated: true)
    }

    private func toggleFavorite() {
        categoryStore.toggleFavorite(for: asset)
        refreshMetadataButtons()
        onCategoriesDidChange()
    }

    private func showTagsEditor() {
        let alert = UIAlertController(title: "Edit tags", message: "Comma-separated tags", preferredStyle: .alert)
        alert.addTextField { $0.text = self.categoryStore.tags(for: self.asset).joined(separator: ", ") }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            let tags = raw.split(separator: ",").map { String($0) }
            self.categoryStore.setTags(tags, for: self.asset)
            self.refreshMetadataButtons()
            self.onCategoriesDidChange()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func copyAllText() {
        let text = textView.text ?? ""
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        textStatusLabel.text = "Copied text"
    }

    private func loadPreviewAndRunOCR() {
        let maxSide: CGFloat = 1800
        let w = CGFloat(asset.pixelWidth)
        let h = CGFloat(asset.pixelHeight)
        let scale = min(1, maxSide / max(w, h, 1))
        let target = CGSize(width: max(w * scale, 1), height: max(h * scale, 1))
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast

        previewRequestID = imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: opts
        ) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else { return }
                self.previewImageView.image = image
                guard let image else {
                    self.textStatusLabel.text = "Could not load image for text recognition."
                    return
                }
                self.runOCR(on: image)
            }
        }

        let dataOptions = PHImageRequestOptions()
        dataOptions.deliveryMode = .highQualityFormat
        dataOptions.isNetworkAccessAllowed = true
        dataOptions.version = .current
        imageDataRequestID = imageManager.requestImageDataAndOrientation(for: asset, options: dataOptions) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let data, let fullImage = UIImage(data: data) else { return }
                self.runOCR(on: fullImage)
            }
        }
    }

    private func runOCR(on image: UIImage) {
        ocrTask?.cancel()
        ocrTask = Task { @MainActor in
            let result = await ScreenshotTextRecognizer.recognizeText(in: image) { [weak self] in
                self?.ocrCancelled == true || Task.isCancelled
            }
            guard !Task.isCancelled, !ocrCancelled else { return }
            guard let result else {
                textStatusLabel.text = "Cancelled"
                return
            }
            if result.text.isEmpty {
                textStatusLabel.text = "No text detected"
                textView.text = ""
                clearHighlightBoxes()
                categoryStore.setOCRText("", for: asset)
            } else {
                textStatusLabel.text = "Extracted text (full scan)"
                textView.text = result.text
                categoryStore.setOCRText(result.text, for: asset)
                onOCRUpdated(asset, result.text)
                drawHighlightBoxes(result.lines)
            }
        }
    }

    private func clearHighlightBoxes() {
        overlayView.subviews.forEach { $0.removeFromSuperview() }
    }

    private func drawHighlightBoxes(_ lines: [ScreenshotTextRecognizer.RecognizedLine]) {
        clearHighlightBoxes()
        guard let image = previewImageView.image else { return }
        let drawRect = aspectFitImageRect(imageSize: image.size, in: previewImageView.bounds)
        guard drawRect.width > 0, drawRect.height > 0 else { return }
        for line in lines {
            let rect = denormalizedRect(line.boundingBox, in: drawRect)
            guard rect.width > 0, rect.height > 0 else { continue }
            guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { continue }
            let button = UIButton(type: .custom)
            button.frame = rect
            button.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.22)
            button.layer.borderColor = UIColor.systemYellow.cgColor
            button.layer.borderWidth = 1
            button.layer.cornerRadius = 3
            button.addAction(UIAction { _ in
                UIPasteboard.general.string = line.text
            }, for: .touchUpInside)
            overlayView.addSubview(button)
        }
    }

    private func aspectFitImageRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = bounds.midX - width / 2
        let y = bounds.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func denormalizedRect(_ normalized: CGRect, in imageRect: CGRect) -> CGRect {
        let x = imageRect.origin.x + normalized.minX * imageRect.width
        let y = imageRect.origin.y + (1 - normalized.maxY) * imageRect.height
        let width = normalized.width * imageRect.width
        let height = normalized.height * imageRect.height
        if !x.isFinite || !y.isFinite || !width.isFinite || !height.isFinite {
            return .zero
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
