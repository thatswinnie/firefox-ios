// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

class GridTabViewControllerLayout: UICollectionViewCompositionalLayout {
    var inactiveSectionBackgroundColor: UIColor = .clear

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let attributes = super.layoutAttributesForElements(in: rect) else { return nil }
        var allAttributes = [UICollectionViewLayoutAttributes]()
        print("WT: \(attributes)")

        for attribute in attributes {
            if attribute.representedElementCategory == UICollectionView.ElementCategory.decorationView {
                let backgroundAttributes = InactiveTabBackgroundLayoutAttributes(
                    forDecorationViewOfKind: InactiveTabCellBackgroundView.cellIdentifier,
                    with: attribute.indexPath)
                backgroundAttributes.backgroundColor = inactiveSectionBackgroundColor
                backgroundAttributes.frame = attribute.frame
                backgroundAttributes.zIndex = attribute.zIndex
                allAttributes.append(backgroundAttributes)
            } else {
                allAttributes.append(attribute)
            }

        }

        return allAttributes
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return super.layoutAttributesForSupplementaryView(ofKind: elementKind, at: indexPath)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return super.layoutAttributesForItem(at: indexPath)
    }

    override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            let attributes = super.layoutAttributesForDecorationView(ofKind: elementKind, at: indexPath)

            if elementKind == InactiveTabCellBackgroundView.cellIdentifier {
                let backgroundAttributes = InactiveTabBackgroundLayoutAttributes(
                    forDecorationViewOfKind: InactiveTabCellBackgroundView.cellIdentifier,
                    with: indexPath)
                backgroundAttributes.backgroundColor = inactiveSectionBackgroundColor
                backgroundAttributes.frame = attributes?.frame ?? CGRect.zero
                return backgroundAttributes
            }
            return attributes
    }
}
