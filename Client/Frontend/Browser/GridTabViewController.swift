// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit
import Storage
import Shared
import Common

protocol TabTrayDelegate: AnyObject {
    func tabTrayDidDismiss(_ tabTray: GridTabViewController)
    func tabTrayDidAddTab(_ tabTray: GridTabViewController, tab: Tab)
    func tabTrayDidAddBookmark(_ tab: Tab)
    func tabTrayDidAddToReadingList(_ tab: Tab) -> ReadingListItem?
    func tabTrayOpenRecentlyClosedTab(_ url: URL)
    func tabTrayDidRequestTabsSettings()
}

class GridTabViewController: UIViewController, TabTrayViewDelegate, Themeable {
    struct UX {
        static let cornerRadius: CGFloat = 6.0
        static let margin: CGFloat = 15.0
        static let compactNumberOfColumnsThin: Int = 2
        static let numberOfColumnsWide: Int = 3
        static let textBoxHeight: CGFloat = 32.0
    }

    let tabManager: TabManager
    let profile: Profile
    weak var delegate: TabTrayDelegate?
    var tabDisplayManager: TabDisplayManager!
    var tabCellIdentifier: TabDisplayer.TabCellIdentifier = TabCell.cellIdentifier
    static let independentTabsHeaderIdentifier = "IndependentTabs"
    var otherBrowsingModeOffset = CGPoint.zero
    // Backdrop used for displaying greyed background for private tabs
    var collectionView: UICollectionView!
    var backgroundPrivacyOverlay: UIView = .build { _ in }
    var recentlyClosedTabsPanel: RecentlyClosedTabsPanel?
    var notificationCenter: NotificationProtocol
    var contextualHintViewController: ContextualHintViewController
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?

    // This is an optional variable used if we wish to focus a tab that is not the
    // currently selected tab. This allows us to force the scroll behaviour to move
    // wherever we need to focus the user's attention.
    var tabToFocus: Tab?

    override var canBecomeFirstResponder: Bool {
        return true
    }

    private lazy var emptyPrivateTabsView: EmptyPrivateTabsView = .build { view in
        view.learnMoreButton.addTarget(self, action: #selector(self.didTapLearnMore), for: .touchUpInside)
    }

    private lazy var tabLayoutDelegate: TabLayoutDelegate = {
        let delegate = TabLayoutDelegate(tabDisplayManager: self.tabDisplayManager,
                                         traitCollection: self.traitCollection,
                                         scrollView: self.collectionView)
        delegate.tabSelectionDelegate = self
        delegate.tabPeekDelegate = self
        return delegate
    }()

    var numberOfColumns: Int {
        return tabLayoutDelegate.numberOfColumns
    }

    // MARK: - Inits
    init(tabManager: TabManager,
         profile: Profile,
         tabTrayDelegate: TabTrayDelegate? = nil,
         tabToFocus: Tab? = nil,
         notificationCenter: NotificationProtocol = NotificationCenter.default,
         themeManager: ThemeManager = AppContainer.shared.resolve()
    ) {
        self.tabManager = tabManager
        self.profile = profile
        self.delegate = tabTrayDelegate
        self.tabToFocus = tabToFocus
        self.notificationCenter = notificationCenter

        let contextualViewModel = ContextualHintViewModel(forHintType: .inactiveTabs,
                                                          with: profile)
        self.contextualHintViewController = ContextualHintViewController(with: contextualViewModel)
        self.themeManager = themeManager

        super.init(nibName: nil, bundle: nil)
        collectionViewSetup()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabManager.addDelegate(self)
        view.accessibilityLabel = .TabTrayViewAccessibilityLabel

        backgroundPrivacyOverlay.alpha = 0

        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag

        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = tabDisplayManager
        collectionView.dropDelegate = tabDisplayManager

        setupLayout()

        if let tab = tabManager.selectedTab, tab.isPrivate {
            tabDisplayManager.togglePrivateMode(isOn: true, createTabOnEmptyPrivateMode: false)
        }

        emptyPrivateTabsView.isHidden = !privateTabsAreEmpty()

        listenForThemeChange()
        applyTheme()

        setupNotifications(forObserver: self, observing: [
            UIApplication.willResignActiveNotification,
            UIApplication.didBecomeActiveNotification
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.layoutIfNeeded()
        focusItem()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // When the app enters split screen mode we refresh the collection view layout to show the proper grid
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        collectionView.collectionViewLayout.invalidateLayout()
    }

    deinit {
        tabManagerTeardown()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private
    private func setupLayout() {
        view.addSubview(backgroundPrivacyOverlay)
        view.addSubview(collectionView)
        view.addSubview(emptyPrivateTabsView)

        NSLayoutConstraint.activate([
            backgroundPrivacyOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundPrivacyOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundPrivacyOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundPrivacyOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyPrivateTabsView.topAnchor.constraint(equalTo: collectionView.topAnchor),
            emptyPrivateTabsView.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
            emptyPrivateTabsView.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            emptyPrivateTabsView.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
        ])
    }

    private func collectionViewSetup() {
        collectionView = UICollectionView(frame: .zero,
                                          collectionViewLayout: getCompositionalLayout())
        collectionView.register(cellType: TabCell.self)
        collectionView.register(cellType: GroupedTabCell.self)
        collectionView.register(cellType: InactiveTabItemCell.self)
        collectionView.register(
            LabelButtonHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: GridTabViewController.independentTabsHeaderIdentifier)
        collectionView.register(
            InactiveTabHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: InactiveTabHeader.cellIdentifier)
        collectionView.register(
            CellWithRoundedButton.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: CellWithRoundedButton.cellIdentifier)
        collectionView.register(
            UICollectionReusableView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: "default") // cell used if anything goes wrong so we don't crash

        tabDisplayManager = TabDisplayManager(collectionView: self.collectionView,
                                              tabManager: self.tabManager,
                                              tabDisplayer: self,
                                              reuseID: TabCell.cellIdentifier,
                                              tabDisplayType: .TabGrid,
                                              profile: profile,
                                              cfrDelegate: self,
                                              theme: themeManager.currentTheme)
        collectionView.dataSource = tabDisplayManager
        collectionView.delegate = tabLayoutDelegate
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        tabDisplayManager.tabDisplayCompletionDelegate = self
    }

    private func getCompositionalLayout() -> UICollectionViewCompositionalLayout {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .vertical

        let layout = GridTabViewControllerLayout(sectionProvider: { sectionIndex, environment in
            switch TabDisplaySection(rawValue: sectionIndex) {
            case .inactiveTabs:
                return self.inactiveTabSectionLayout(availableWidth: environment.container.contentSize.width)
            case .groupedTabs:
                return self.groupedTabSectionLayout()
            case .regularTabs, .none:
                return self.regularTabSectionLayout()
            }
        }, configuration: config)

        layout.register(InactiveTabCellBackgroundView.self,
                        forDecorationViewOfKind: InactiveTabCellBackgroundView.cellIdentifier)

        return layout
    }

    private func inactiveTabSectionLayout(availableWidth: CGFloat) -> NSCollectionLayoutSection {
        let frameWidth = collectionView.frame.size.width
        let margin = UX.margin
        var cellWidth = (frameWidth - margin * 2) > 0 ? frameWidth - margin * 2 : 0
        let estimatedHeight = tabLayoutDelegate.calculateInactiveTabSizeHelper(collectionView).height

        if UIDevice.current.userInterfaceIdiom == .pad {
            cellWidth = frameWidth/1.5
        }

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(cellWidth),
            heightDimension: .estimated(InactiveTabCell.UX.HeaderAndRowHeight))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .estimated(estimatedHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitems: [item])
        let section = NSCollectionLayoutSection(group: group)

        var verticalContentInset: CGFloat = 0
        var horizontalContentInset: CGFloat = 0
        if !tabDisplayManager.isPrivate,
           tabDisplayManager.inactiveViewModel?.inactiveTabs.count ?? 0 > 0 {
            let inset = (availableWidth - cellWidth) / 2.0
            horizontalContentInset = inset > margin ? inset : margin
            verticalContentInset = margin
        }
        section.contentInsets = NSDirectionalEdgeInsets(top: verticalContentInset,
                                                        leading: horizontalContentInset,
                                                        bottom: verticalContentInset,
                                                        trailing: horizontalContentInset)

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(55)
        )
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        sectionHeader.contentInsets = NSDirectionalEdgeInsets(top: verticalContentInset,
                                                              leading: 0,
                                                              bottom: 0,
                                                              trailing: 0)

        guard tabDisplayManager.hasInactiveTabs else {
            return section
        }

        let footerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(InactiveTabCell.UX.HeaderAndRowHeight)
        )
        let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: footerSize,
            elementKind: UICollectionView.elementKindSectionFooter,
            alignment: .bottom
        )

        section.boundarySupplementaryItems = tabDisplayManager.isInactiveViewExpanded ?
            [sectionHeader, sectionFooter] : [sectionHeader]

        let backgroundItem = NSCollectionLayoutDecorationItem.background(
            elementKind: InactiveTabCellBackgroundView.cellIdentifier)
        backgroundItem.contentInsets = section.contentInsets
        section.decorationItems = [backgroundItem]

        return section
    }

    private func groupedTabSectionLayout() -> NSCollectionLayoutSection {
        let frameWidth = collectionView.frame.size.width
        let margin = UX.margin
        let cellWidth = frameWidth > 0 ? frameWidth : 0
        var cellHeight: CGFloat = 0

        if let groupCount = tabDisplayManager.tabGroups?.count, groupCount > 0 {
            cellHeight = GroupedTabCellProperties.CellUX.defaultCellHeight * CGFloat(groupCount)
        }

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(cellWidth),
            heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(cellHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        var bottomContentInset: CGFloat = 0

        if tabDisplayManager.shouldEnableGroupedTabs,
           tabDisplayManager.tabGroups?.count ?? 0 > 0 {
            bottomContentInset = margin
        }
        section.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                        leading: 0,
                                                        bottom: bottomContentInset,
                                                        trailing: 0)
        return section
    }

    private func regularTabSectionLayout() -> NSCollectionLayoutSection {
        let margin = UX.margin * CGFloat(numberOfColumns + 1)
        let calculatedWidth = collectionView.bounds.width - collectionView.safeAreaInsets.left - collectionView.safeAreaInsets.right - margin
        let cellWidth = floor(calculatedWidth / CGFloat(numberOfColumns))
        let cellHeight = tabLayoutDelegate.cellHeightForCurrentDevice()

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(cellWidth),
            heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(cellHeight))
        let subitemsCount = numberOfColumns
        let subItems: [NSCollectionLayoutItem] = Array(repeating: item, count: Int(subitemsCount))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitems: subItems)
        group.interItemSpacing = .fixed(UX.margin)

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(40)
        )
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )

        let section = NSCollectionLayoutSection(group: group)

        if tabDisplayManager.tabGroups != nil {
            section.boundarySupplementaryItems = [sectionHeader]
        }

        section.contentInsets = NSDirectionalEdgeInsets(
            top: UX.margin,
            leading: UX.margin + collectionView.safeAreaInsets.left,
            bottom: UX.margin,
            trailing: UX.margin + collectionView.safeAreaInsets.right)
        section.interGroupSpacing = UX.margin
        return section
    }

    private func tabManagerTeardown() {
        tabManager.removeDelegate(self.tabDisplayManager)
        tabManager.removeDelegate(self)
        tabDisplayManager = nil
        contextualHintViewController.stopTimer()
        notificationCenter.removeObserver(self)
    }

    // MARK: - Scrolling helper methods
    /// The main interface for scrolling to an item, whether that is a group or an individual tab
    ///
    /// This method checks for the existence of a tab to focus on other than the selected tab,
    /// and then, focuses on that tab. The byproduct is that if the tab is in a group, the
    /// user would then be looking at the group. Generally, if focusing on a group and
    /// NOT the selected tab, it is advised to pass in the first tab of that group as
    /// the `tabToFocus` in the initializer
    func focusItem() {
        guard let selectedTab = tabManager.selectedTab else { return }
        if tabToFocus == nil { tabToFocus = selectedTab }
        guard let tabToFocus = tabToFocus else { return }

        if let tabGroups = tabDisplayManager.tabGroups,
           !tabGroups.isEmpty,
           tabGroups.contains(where: { $0.groupedItems.contains(where: { $0 == tabToFocus }) }) {
            focusGroup(from: tabGroups, with: tabToFocus)
        } else {
            focusTab(tabToFocus)
        }
    }

    func focusGroup(from tabGroups: [ASGroup<Tab>], with tabToFocus: Tab) {
        if let tabIndex = tabDisplayManager.indexOfGroupTab(tab: tabToFocus) {
            let groupName = tabIndex.groupName
            let groupIndex: Int = tabGroups.firstIndex(where: { $0.searchTerm == groupName }) ?? 0
            let offSet = Int(GroupedTabCellProperties.CellUX.defaultCellHeight) * groupIndex
            let rect = CGRect(origin: CGPoint(x: 0, y: offSet), size: CGSize(width: self.collectionView.frame.width, height: self.collectionView.frame.height))
            DispatchQueue.main.async {
                self.collectionView.scrollRectToVisible(rect, animated: false)
            }
        }
    }

    func focusTab(_ selectedTab: Tab) {
        if let indexOfRegularTab = tabDisplayManager.indexOfRegularTab(tab: selectedTab) {
            let indexPath = IndexPath(item: indexOfRegularTab, section: TabDisplaySection.regularTabs.rawValue)
            guard var rect = self.collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
            if indexOfRegularTab >= self.tabDisplayManager.dataStore.count - 2 {
                DispatchQueue.main.async {
                    rect.origin.y += 10
                    self.collectionView.scrollRectToVisible(rect, animated: false)
                }
            } else {
                self.collectionView.scrollToItem(at: indexPath, at: [.centeredVertically, .centeredHorizontally], animated: false)
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Update the trait collection we reference in our layout delegate
        tabLayoutDelegate.traitCollection = traitCollection
    }

    @objc func didTogglePrivateMode() {
        tabManager.willSwitchTabMode(leavingPBM: tabDisplayManager.isPrivate)

        tabDisplayManager.togglePrivateMode(isOn: !tabDisplayManager.isPrivate, createTabOnEmptyPrivateMode: false)

        emptyPrivateTabsView.isHidden = !privateTabsAreEmpty()
    }

    fileprivate func privateTabsAreEmpty() -> Bool {
        return tabDisplayManager.isPrivate && tabManager.privateTabs.isEmpty
    }

    func openNewTab(_ request: URLRequest? = nil, isPrivate: Bool) {
        if tabDisplayManager.isDragging {
            return
        }

        // Ensure Firefox home page is refreshed if privacy mode was changed
        if tabManager.selectedTab?.isPrivate != isPrivate {
            let notificationObject = [Tab.privateModeKey: isPrivate]
            NotificationCenter.default.post(name: .TabsPrivacyModeChanged, object: notificationObject)
        }

        tabManager.selectTab(tabManager.addTab(request, isPrivate: isPrivate))
    }

    func applyTheme() {
        tabDisplayManager.theme = themeManager.currentTheme
        emptyPrivateTabsView.applyTheme(themeManager.currentTheme)
        backgroundPrivacyOverlay.backgroundColor = themeManager.currentTheme.colors.layerScrim
        collectionView.backgroundColor = themeManager.currentTheme.colors.layer3
        (collectionView.collectionViewLayout as? GridTabViewControllerLayout)?.inactiveSectionBackgroundColor = themeManager.currentTheme.colors.layer5
        collectionView.reloadData()
    }
}

extension GridTabViewController: TabManagerDelegate {
    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Tab?, previous: Tab?, isRestoring: Bool) {}
    func tabManager(_ tabManager: TabManager, didAddTab tab: Tab, placeNextToParentTab: Bool, isRestoring: Bool) {}
    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Tab, isRestoring: Bool) {
        NotificationCenter.default.post(name: .UpdateLabelOnTabClosed, object: nil)
    }
    func tabManagerDidAddTabs(_ tabManager: TabManager) {}

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {
        self.emptyPrivateTabsView.isHidden = !self.privateTabsAreEmpty()
    }

    func tabManagerDidRemoveAllTabs(_ tabManager: TabManager, toast: ButtonToast?) {
        // No need to handle removeAll toast in TabTray.
        // When closing all normal tabs we automatically focus a tab and show the BVC. Which will handle the Toast.
        // We don't show the removeAll toast in PBM
    }
}

extension GridTabViewController: TabDisplayer {
    func focusSelectedTab() {
        self.focusItem()
    }

    func cellFactory(for cell: UICollectionViewCell, using tab: Tab) -> UICollectionViewCell {
        guard let tabCell = cell as? TabCell else { return cell }
        tabCell.animator?.delegate = self
        tabCell.delegate = self
        let selected = tab == tabManager.selectedTab
        tabCell.configureWith(tab: tab, isSelected: selected, theme: themeManager.currentTheme)
        return tabCell
    }
}

extension GridTabViewController {
    @objc func didTapLearnMore() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let langID = Locale.preferredLanguages.first {
            let learnMoreRequest = URLRequest(url: "https://support.mozilla.org/1/mobile/\(appVersion ?? "0.0")/iOS/\(langID)/private-browsing-ios".asURL!)
            openNewTab(learnMoreRequest, isPrivate: tabDisplayManager.isPrivate)
        }
    }

    func closeTabsTrayBackground() {
        tabDisplayManager.removeAllTabsFromView()

        tabManager.backgroundRemoveAllTabs(isPrivate: tabDisplayManager.isPrivate) {
            recentlyClosedTabs, isPrivateState, previousTabUUID in

            DispatchQueue.main.async { [unowned self] in
                if isPrivateState {
                    let previousTab = self.tabManager.tabs.filter { $0.tabUUID == previousTabUUID }.first
                    self.tabManager.cleanupClosedTabs(recentlyClosedTabs,
                                                      previous: previousTab,
                                                      isPrivate: isPrivateState)
                } else {
                    self.tabManager.makeToastFromRecentlyClosedUrls(recentlyClosedTabs,
                                                                    isPrivate: isPrivateState,
                                                                    previousTabUUID: previousTabUUID)
                }
                closeTabsTrayHelper()
            }
        }
    }

    func closeTabsTrayHelper() {
        if tabDisplayManager.isPrivate {
            emptyPrivateTabsView.isHidden = !self.privateTabsAreEmpty()
            if !emptyPrivateTabsView.isHidden {
                // Fade in the empty private tabs message. This slow fade allows time for the closing tab animations to complete.
                emptyPrivateTabsView.alpha = 0
                UIView.animate(
                    withDuration: 0.5,
                    animations: {
                        self.emptyPrivateTabsView.alpha = 1
                    })
            }
        } else if self.tabManager.normalTabs.count == 1, let tab = self.tabManager.normalTabs.first {
            self.tabManager.selectTab(tab)
            self.dismissTabTray()
            notificationCenter.post(name: .TabsTrayDidClose)
        }
    }

    func didTogglePrivateMode(_ togglePrivateModeOn: Bool) {
        if togglePrivateModeOn != tabDisplayManager.isPrivate {
            didTogglePrivateMode()
        }
    }

    func dismissTabTray() {
        self.navigationController?.dismiss(animated: true, completion: nil)
        TelemetryWrapper.recordEvent(category: .action, method: .close, object: .tabTray)
    }
}

// MARK: - App Notifications
extension GridTabViewController {
    @objc func appWillResignActiveNotification() {
        if tabDisplayManager.isPrivate {
            backgroundPrivacyOverlay.alpha = 1
            view.bringSubviewToFront(backgroundPrivacyOverlay)
            collectionView.alpha = 0
            emptyPrivateTabsView.alpha = 0
        }
    }

    @objc func appDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.collectionView.alpha = 1
                self.emptyPrivateTabsView.alpha = 1
            }) { _ in
                self.backgroundPrivacyOverlay.alpha = 0
                self.view.sendSubviewToBack(self.backgroundPrivacyOverlay)
            }
    }
}

extension GridTabViewController: TabSelectionDelegate {
    func didSelectTabAtIndex(_ index: Int) {
        if let tab = tabDisplayManager.dataStore.at(index) {
            if tab.isFxHomeTab {
                notificationCenter.post(name: .TabsTrayDidSelectHomeTab)
            }
            tabManager.selectTab(tab)
            dismissTabTray()
        }
    }
}

// MARK: UIScrollViewAccessibilityDelegate
extension GridTabViewController: UIScrollViewAccessibilityDelegate {
    func accessibilityScrollStatus(for scrollView: UIScrollView) -> String? {
        guard var visibleCells = collectionView.visibleCells as? [TabCell] else { return nil }
        var bounds = collectionView.bounds
        bounds = bounds.offsetBy(dx: collectionView.contentInset.left, dy: collectionView.contentInset.top)
        bounds.size.width -= collectionView.contentInset.left + collectionView.contentInset.right
        bounds.size.height -= collectionView.contentInset.top + collectionView.contentInset.bottom
        // visible cells do sometimes return also not visible cells when attempting to go past the last cell with VoiceOver right-flick gesture; so make sure we have only visible cells (yeah...)
        visibleCells = visibleCells.filter { !$0.frame.intersection(bounds).isEmpty }

        let cells = visibleCells.map { self.collectionView.indexPath(for: $0)! }
        let indexPaths = cells.sorted { (first: IndexPath, second: IndexPath) -> Bool in
            return first.section < second.section || (first.section == second.section && first.row < second.row)
        }

        guard !indexPaths.isEmpty else {
            return .TabTrayNoTabsAccessibilityHint
        }

        let firstTab = indexPaths.first!.row + 1
        let lastTab = indexPaths.last!.row + 1
        let tabCount = collectionView.numberOfItems(inSection: 1)

        if firstTab == lastTab {
            let format: String = .TabTrayVisibleTabRangeAccessibilityHint
            return String(format: format, NSNumber(value: firstTab as Int), NSNumber(value: tabCount as Int))
        } else {
            let format: String = .TabTrayVisiblePartialRangeAccessibilityHint
            return String(format: format, NSNumber(value: firstTab as Int), NSNumber(value: lastTab as Int), NSNumber(value: tabCount as Int))
        }
    }
}

// MARK: - SwipeAnimatorDelegate
extension GridTabViewController: SwipeAnimatorDelegate {
    func swipeAnimator(_ animator: SwipeAnimator, viewWillExitContainerBounds: UIView) {
        guard let tabCell = animator.animatingView as? TabCell, let indexPath = collectionView.indexPath(for: tabCell) else { return }
        if let tab = tabDisplayManager.dataStore.at(indexPath.item) {
            self.removeByButtonOrSwipe(tab: tab, cell: tabCell)
            UIAccessibility.post(notification: UIAccessibility.Notification.announcement, argument: String.TabTrayClosingTabAccessibilityMessage)
        }
    }

    // Disable swipe delete while drag reordering
    func swipeAnimatorIsAnimateAwayEnabled(_ animator: SwipeAnimator) -> Bool {
        return !tabDisplayManager.isDragging
    }
}

extension GridTabViewController: TabCellDelegate {
    func tabCellDidClose(_ cell: TabCell) {
        if let indexPath = collectionView.indexPath(for: cell), let tab = tabDisplayManager.dataStore.at(indexPath.item) {
            removeByButtonOrSwipe(tab: tab, cell: cell)
        }
    }
}

extension GridTabViewController: TabPeekDelegate {
    func tabPeekDidAddBookmark(_ tab: Tab) {
        delegate?.tabTrayDidAddBookmark(tab)
    }

    func tabPeekDidAddToReadingList(_ tab: Tab) -> ReadingListItem? {
        return delegate?.tabTrayDidAddToReadingList(tab)
    }

    func tabPeekDidCloseTab(_ tab: Tab) {
        // Tab peek is only available on regular tabs
        if let index = tabDisplayManager.dataStore.index(of: tab),
           let cell = self.collectionView?.cellForItem(at: IndexPath(item: index, section: TabDisplaySection.regularTabs.rawValue)) as? TabCell {
            cell.close()
            NotificationCenter.default.post(name: .UpdateLabelOnTabClosed, object: nil)
        }
    }

    func tabPeekRequestsPresentationOf(_ viewController: UIViewController) {
        present(viewController, animated: true, completion: nil)
    }

    func tabPeekDidCopyUrl() {
        SimpleToast().showAlertWithText(.AppMenu.AppMenuCopyURLConfirmMessage,
                                        bottomContainer: view,
                                        theme: themeManager.currentTheme)
    }
}

// MARK: - TabDisplayCompletionDelegate & RecentlyClosedPanelDelegate
extension GridTabViewController: TabDisplayCompletionDelegate, RecentlyClosedPanelDelegate {
    // RecentlyClosedPanelDelegate
    func openRecentlyClosedSiteInSameTab(_ url: URL) {
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .inactiveTabTray, value: .openRecentlyClosedTab, extras: nil)
        delegate?.tabTrayOpenRecentlyClosedTab(url)
        dismissTabTray()
    }

    func openRecentlyClosedSiteInNewTab(_ url: URL, isPrivate: Bool) {
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .inactiveTabTray, value: .openRecentlyClosedTab, extras: nil)
        openNewTab(URLRequest(url: url), isPrivate: isPrivate)
        dismissTabTray()
    }

    // TabDisplayCompletionDelegate
    func completedAnimation(for type: TabAnimationType) {
        emptyPrivateTabsView.isHidden = !privateTabsAreEmpty()

        switch type {
        case .addTab:
            dismissTabTray()
        case .removedLastTab:
            // when removing the last tab (only in normal mode) we will automatically open a new tab.
            // When that happens focus it by dismissing the tab tray
            notificationCenter.post(name: .TabsTrayDidClose)
            if !tabDisplayManager.isPrivate {
                self.dismissTabTray()
            }
        case .removedNonLastTab, .updateTab, .moveTab:
            break
        }
    }
}

extension GridTabViewController {
    func removeByButtonOrSwipe(tab: Tab, cell: TabCell) {
        tabDisplayManager.tabDisplayCompletionDelegate = self
        tabDisplayManager.closeActionPerformed(forCell: cell)
    }
}

// MARK: - Toolbar Actions
extension GridTabViewController {
    func performToolbarAction(_ action: TabTrayViewAction, sender: UIBarButtonItem) {
        switch action {
        case .addTab:
            didTapToolbarAddTab()
        case .deleteTab:
            didTapToolbarDelete(sender)
        }
    }

    func didTapToolbarAddTab() {
        if tabDisplayManager.isDragging {
            return
        }
        openNewTab(isPrivate: tabDisplayManager.isPrivate)
    }

    func didTapToolbarDelete(_ sender: UIBarButtonItem) {
        if tabDisplayManager.isDragging {
            return
        }

        let controller = AlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: .AppMenu.AppMenuCloseAllTabsTitleString,
                                           style: .default,
                                           handler: { _ in self.closeTabsTrayBackground() }),
                             accessibilityIdentifier: AccessibilityIdentifiers.TabTray.deleteCloseAllButton)
        controller.addAction(UIAlertAction(title: .TabTrayCloseAllTabsPromptCancel,
                                           style: .cancel,
                                           handler: nil),
                             accessibilityIdentifier: AccessibilityIdentifiers.TabTray.deleteCancelButton)
        controller.popoverPresentationController?.barButtonItem = sender
        present(controller, animated: true, completion: nil)
    }
}

// MARK: TabLayoutDelegate
private class TabLayoutDelegate: NSObject, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
    weak var tabSelectionDelegate: TabSelectionDelegate?
    weak var tabPeekDelegate: TabPeekDelegate?
    let scrollView: UIScrollView
    var lastYOffset: CGFloat = 0
    var tabDisplayManager: TabDisplayManager

    enum ScrollDirection {
        case up
        case down
    }

    fileprivate var scrollDirection: ScrollDirection = .down
    fileprivate var traitCollection: UITraitCollection
    fileprivate var numberOfColumns: Int {
        // iPhone 4-6+ portrait
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .regular {
            return GridTabViewController.UX.compactNumberOfColumnsThin
        } else {
            return GridTabViewController.UX.numberOfColumnsWide
        }
    }

    init(tabDisplayManager: TabDisplayManager, traitCollection: UITraitCollection, scrollView: UIScrollView) {
        self.tabDisplayManager = tabDisplayManager
        self.scrollView = scrollView
        self.traitCollection = traitCollection
        super.init()
    }

    fileprivate func cellHeightForCurrentDevice() -> CGFloat {
        let shortHeight = GridTabViewController.UX.textBoxHeight * 6

        if self.traitCollection.verticalSizeClass == .compact {
            return shortHeight
        } else if self.traitCollection.horizontalSizeClass == .compact {
            return shortHeight
        } else {
            return GridTabViewController.UX.textBoxHeight * 8
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    fileprivate func calculateInactiveTabSizeHelper(_ collectionView: UICollectionView) -> CGSize {
        guard !tabDisplayManager.isPrivate,
              let inactiveTabViewModel = tabDisplayManager.inactiveViewModel,
              !inactiveTabViewModel.activeTabs.isEmpty
        else {
            return CGSize(width: 0, height: 0)
        }

        let closeAllButtonHeight = InactiveTabCell.UX.CloseAllTabRowHeight
        let headerHeightWithRoundedCorner = InactiveTabCell.UX.HeaderAndRowHeight + InactiveTabCell.UX.RoundedContainerPaddingClosed
        var totalHeight = headerHeightWithRoundedCorner
        let width: CGFloat = collectionView.frame.size.width - InactiveTabCell.UX.InactiveTabTrayWidthPadding
        let inactiveTabs = inactiveTabViewModel.inactiveTabs

        // Calculate height based on number of tabs in the inactive tab section section
        let calculatedInactiveTabsTotalHeight = (InactiveTabCell.UX.HeaderAndRowHeight * CGFloat(inactiveTabs.count)) +
        InactiveTabCell.UX.RoundedContainerPaddingClosed +
        InactiveTabCell.UX.RoundedContainerAdditionalPaddingOpened + closeAllButtonHeight

        totalHeight = tabDisplayManager.isInactiveViewExpanded ? calculatedInactiveTabsTotalHeight : headerHeightWithRoundedCorner

        if UIDevice.current.userInterfaceIdiom == .pad {
            return CGSize(width: collectionView.frame.size.width/1.5, height: totalHeight)
        } else {
            return CGSize(width: width >= 0 ? width : 0, height: totalHeight)
        }
    }

    @objc func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        tabSelectionDelegate?.didSelectTabAtIndex(indexPath.row)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard TabDisplaySection(rawValue: indexPath.section) == .regularTabs,
              let tab = tabDisplayManager.dataStore.at(indexPath.row)
        else { return nil }

        let tabVC = TabPeekViewController(tab: tab, delegate: tabPeekDelegate)
        if let browserProfile = tabDisplayManager.profile as? BrowserProfile,
           let pickerDelegate = tabPeekDelegate as? DevicePickerViewControllerDelegate {
            tabVC.setState(withProfile: browserProfile, clientPickerDelegate: pickerDelegate)
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: { return tabVC }, actionProvider: tabVC.contextActions(defaultActions:))
    }
}

// MARK: - DevicePickerViewControllerDelegate
extension GridTabViewController: DevicePickerViewControllerDelegate {
    func devicePickerViewController(_ devicePickerViewController: DevicePickerViewController, didPickDevices devices: [RemoteDevice]) {
        if let item = devicePickerViewController.shareItem {
            _ = self.profile.sendItem(item, toDevices: devices)
        }
        devicePickerViewController.dismiss(animated: true, completion: nil)
    }

    func devicePickerViewControllerDidCancel(_ devicePickerViewController: DevicePickerViewController) {
        devicePickerViewController.dismiss(animated: true, completion: nil)
    }
}

// MARK: - Presentation Delegates
extension GridTabViewController: UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
    // Returning None here makes sure that the Popover is actually presented as a Popover and
    // not as a full-screen modal, which is the default on compact device classes.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

extension GridTabViewController: PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(_ modalViewController: UIViewController, animated: Bool) {
        dismiss(animated: animated, completion: { self.collectionView.reloadData() })
    }
}

protocol TabCellDelegate: AnyObject {
    func tabCellDidClose(_ cell: TabCell)
}

// MARK: - Notifiable
extension GridTabViewController: Notifiable {
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case UIApplication.willResignActiveNotification:
            appWillResignActiveNotification()
        case UIApplication.didBecomeActiveNotification:
            appDidBecomeActiveNotification()
        default: break
        }
    }
}

protocol InactiveTabsCFRProtocol {
    func setupCFR(with view: UILabel)
    func presentCFR()
}

// MARK: - Contextual Hint
extension GridTabViewController: InactiveTabsCFRProtocol {
    func setupCFR(with view: UILabel) {
        prepareJumpBackInContextualHint(on: view)
    }

    func presentCFR() {
        contextualHintViewController.startTimer()
    }

    func presentCFROnView() {
        present(contextualHintViewController, animated: true, completion: nil)

        UIAccessibility.post(notification: .layoutChanged, argument: contextualHintViewController)
    }

    private func prepareJumpBackInContextualHint(on title: UILabel) {
        guard contextualHintViewController.shouldPresentHint() else { return }

        contextualHintViewController.configure(
            anchor: title,
            withArrowDirection: .up,
            andDelegate: self,
            presentedUsing: { self.presentCFROnView() },
            andActionForButton: {
                self.dismissTabTray()
                self.delegate?.tabTrayDidRequestTabsSettings()
            }, andShouldStartTimerRightAway: false
        )
    }
}
