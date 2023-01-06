// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

enum ExpandButtonState {
    case right
    case down

    var image: UIImage? {
        switch self {
        case .right:
            return UIImage(named: ImageIdentifiers.menuChevron)?.imageFlippedForRightToLeftLayoutDirection()
        case .down:
            return UIImage(named: ImageIdentifiers.findNext)
        }
    }
}

class InactiveTabHeader: UICollectionReusableView, NotificationThemeable, ReusableCell {
    struct UX {
        static let buttonSize = CGSize(width: 24, height: 24)
        static let font = DynamicFontHelper.defaultHelper.preferredFont(
            withTextStyle: .headline,
            size: 17)
    }

//    static var height: CGFloat {
//        let height = "Sample".boundingRectWithSize(CGSizeMake(CGFloat.max, UIScreen.mainScreen().bounds.size.width),
//                                                   options: .UsesLineFragmentOrigin,
//                                                   attributes: [NSFontAttributeName: UX.font],
//                                                   context: nil).size.height
//        return max(InactiveTabCell.UX.HeaderAndRowHeight, height)
//    }

    var state: ExpandButtonState? {
        willSet(state) {
            moreButton.setImage(state?.image, for: .normal)
        }
    }

    lazy var titleLabel: UILabel = .build { titleLabel in
        titleLabel.text = self.title
        titleLabel.textColor = UIColor.theme.homePanel.activityStreamHeaderText
        titleLabel.font = UX.font
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
    }

    lazy var moreButton: UIButton = .build { button in
        button.isHidden = true
        button.setImage(self.state?.image, for: .normal)
        button.contentHorizontalAlignment = .trailing
    }

    var title: String? {
        willSet(newTitle) {
            titleLabel.text = newTitle
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        applyTheme()
        moreButton.setTitle(nil, for: .normal)
        moreButton.accessibilityIdentifier = nil
        titleLabel.text = nil
        moreButton.removeTarget(nil, action: nil, for: .allEvents)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(titleLabel)
        addSubview(moreButton)
        moreButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = AccessibilityIdentifiers.TabTray.inactiveTabHeader

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 19),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -19),
            titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -16),

            moreButton.widthAnchor.constraint(equalToConstant: UX.buttonSize.width),
            moreButton.heightAnchor.constraint(equalToConstant: UX.buttonSize.height),
            moreButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -28),
        ])

        applyTheme()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        let theme = BuiltinThemeName(rawValue: LegacyThemeManager.instance.current.name) ?? .normal
        self.titleLabel.textColor = theme == .dark ? .white : .black
    }
}
