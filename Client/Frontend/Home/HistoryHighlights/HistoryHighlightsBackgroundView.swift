// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

// class HistoryHighlightsBackgroundLayoutAttributes: UICollectionViewLayoutAttributes {
//    var backgroundColor: UIColor = .clear
// }

class HistoryHighlightsBackgroundView: UICollectionReusableView, ReusableCell {
    static let elementKind = "history-highlights-element-kind"
    private let roundedView: UIView = .build { view in
        view.layer.cornerRadius = 15
        view.backgroundColor = .white
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        addSubview(roundedView)

        NSLayoutConstraint.activate([
            roundedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            roundedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            roundedView.topAnchor.constraint(equalTo: topAnchor),
            roundedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)

//        guard let attributes = layoutAttributes as? HistoryHighlightsBackgroundLayoutAttributes else { return }
//        backgroundColor = attributes.backgroundColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        roundedView.layer.cornerRadius = HomepageViewModel.UX.generalCornerRadius
        roundedView.layer.shadowPath = UIBezierPath(roundedRect: roundedView.bounds,
                                                    cornerRadius: HomepageViewModel.UX.generalCornerRadius).cgPath
        roundedView.layer.shadowColor = UIColor(rgb: 0x3a3944).withAlphaComponent(0.16).cgColor // theme.colors.shadowDefault.cgColor
        roundedView.layer.shadowOpacity = HomepageViewModel.UX.shadowOpacity
        roundedView.layer.shadowOffset = HomepageViewModel.UX.shadowOffset
        roundedView.layer.shadowRadius = HomepageViewModel.UX.shadowRadius
    }
}
