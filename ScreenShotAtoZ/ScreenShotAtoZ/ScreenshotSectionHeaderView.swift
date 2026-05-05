//
//  ScreenshotSectionHeaderView.swift
//  ScreenShotAtoZ
//

import UIKit

final class ScreenshotSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "ScreenshotSectionHeaderView"
    static let elementKind = "ScreenshotSectionHeader"

    let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .title3)
        l.adjustsFontForContentSizeCategory = true
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
