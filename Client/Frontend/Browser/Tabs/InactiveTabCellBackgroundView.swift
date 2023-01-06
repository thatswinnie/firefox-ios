// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

class InactiveTabBackgroundLayoutAttributes: UICollectionViewLayoutAttributes {
    var backgroundColor: UIColor = .clear
}

class InactiveTabCellBackgroundView: UICollectionReusableView, ReusableCell {
    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius = 8
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)

        guard let attributes = layoutAttributes as? InactiveTabBackgroundLayoutAttributes else { return }
        backgroundColor = attributes.backgroundColor
    }
}
