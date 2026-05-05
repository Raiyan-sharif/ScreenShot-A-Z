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
    private let imageManager = PHImageManager.default()

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let previewImageView = UIImageView()
    private let categoryButton = UIButton(type: .system)
    private let textStatusLabel = UILabel()
    private let textView = UITextView()

    private var previewRequestID: PHImageRequestID?
    private var ocrCancelled = false
    private var ocrTask: Task<Void, Never>?

    init(asset: PHAsset, categoryStore: ScreenshotCategoryStore, onCategoriesDidChange: @escaping () -> Void) {
        self.asset = asset
        self.categoryStore = categoryStore
        self.onCategoriesDidChange = onCategoriesDidChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        ocrCancelled = true
        if let previewRequestID {
            imageManager.cancelImageRequest(previewRequestID)
        }
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

        previewImageView.contentMode = .scaleAspectFit
        previewImageView.backgroundColor = .secondarySystemFill
        previewImageView.layer.cornerRadius = 8
        previewImageView.clipsToBounds = true
        previewImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        categoryButton.addAction(UIAction { [weak self] _ in self?.presentCategoryPicker() }, for: .touchUpInside)
        refreshCategoryButtonTitle()

        textStatusLabel.font = .preferredFont(forTextStyle: .subheadline)
        textStatusLabel.textColor = .secondaryLabel
        textStatusLabel.text = "Recognizing text…"

        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        stack.addArrangedSubview(previewImageView)
        stack.addArrangedSubview(makeMetadataRows())
        stack.addArrangedSubview(categoryButton)
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

        loadPreviewAndRunOCR()
    }

    private func refreshCategoryButtonTitle() {
        let eff = categoryStore.effectiveCategory(for: asset)
        let auto = categoryStore.autoCategory(for: asset)
        if categoryStore.hasOverride(for: asset) {
            categoryButton.setTitle("Category: \(eff.title) (override, auto was \(auto.title)) — tap to change", for: .normal)
        } else {
            categoryButton.setTitle("Category: \(eff.title) (automatic) — tap to change", for: .normal)
        }
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
        let shortId = asset.localIdentifier.prefix(20) + (asset.localIdentifier.count > 20 ? "…" : "")
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
                self.refreshCategoryButtonTitle()
                self.onCategoriesDidChange()
            })
        }
        sheet.addAction(UIAlertAction(title: "Use automatic", style: .default) { [weak self] _ in
            guard let self else { return }
            self.categoryStore.setOverride(for: self.asset, category: nil)
            self.refreshCategoryButtonTitle()
            self.onCategoriesDidChange()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = categoryButton
            pop.sourceRect = categoryButton.bounds
        }
        present(sheet, animated: true)
    }

    private func loadPreviewAndRunOCR() {
        let maxSide: CGFloat = 1500
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
    }

    private func runOCR(on image: UIImage) {
        ocrTask = Task { @MainActor in
            let result = await ScreenshotTextRecognizer.recognizeText(in: image) { [weak self] in
                self?.ocrCancelled == true || Task.isCancelled
            }
            guard !Task.isCancelled, !ocrCancelled else { return }
            guard let result else {
                textStatusLabel.text = "Cancelled"
                return
            }
            if result.isEmpty {
                textStatusLabel.text = "No text detected"
                textView.text = ""
            } else {
                textStatusLabel.text = "Extracted text"
                textView.text = result
            }
        }
    }
}
