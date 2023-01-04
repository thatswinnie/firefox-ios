// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit
import Storage
import Shared
import Common

let LocalizedRootBookmarkFolderStrings = [
    BookmarkRoots.MenuFolderGUID: String.BookmarksFolderTitleMenu,
    BookmarkRoots.ToolbarFolderGUID: String.BookmarksFolderTitleToolbar,
    BookmarkRoots.UnfiledFolderGUID: String.BookmarksFolderTitleUnsorted,
    BookmarkRoots.MobileFolderGUID: String.BookmarksFolderTitleMobile,
    LocalDesktopFolder.localDesktopFolderGuid: String.Bookmarks.Menu.DesktopBookmarks
]

class BookmarksPanel: SiteTableViewController,
                      LibraryPanel,
                      CanRemoveQuickActionBookmark,
                      Loggable {
    struct UX {
        static let FolderIconSize = CGSize(width: 24, height: 24)
        static let RowFlashDelay: TimeInterval = 0.4
    }

    // MARK: - Properties
    var bookmarksHandler: BookmarksHandler
    var libraryPanelDelegate: LibraryPanelDelegate?
    var state: LibraryPanelMainState
    let viewModel: BookmarksPanelViewModel

    // MARK: - Toolbar items
    var bottomToolbarItems: [UIBarButtonItem] {
        // Return empty toolbar when bookmarks is in desktop folder node
        guard case .bookmarks = state,
              viewModel.bookmarkFolderGUID != LocalDesktopFolder.localDesktopFolderGuid
        else { return [UIBarButtonItem]() }

        return toolbarButtonItems
    }

    private var toolbarButtonItems: [UIBarButtonItem] {
        switch state {
        case .bookmarks(state: .mainView), .bookmarks(state: .inFolder):
            bottomRightButton.title = .BookmarksEdit
            return [flexibleSpace, bottomRightButton]
        case .bookmarks(state: .inFolderEditMode):
            bottomRightButton.title = String.AppSettingsDone
            return [bottomLeftButton, flexibleSpace, bottomRightButton]
        case .bookmarks(state: .itemEditMode):
            bottomRightButton.title = String.AppSettingsDone
            return [flexibleSpace, bottomRightButton]
        default:
            return [UIBarButtonItem]()
        }
    }

    private lazy var bottomLeftButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage.templateImageNamed(ImageIdentifiers.navAdd),
                                     style: .plain,
                                     target: self,
                                     action: #selector(bottomLeftButtonAction))
        button.accessibilityIdentifier = AccessibilityIdentifiers.LibraryPanels.bottomLeftButton
        return button
    }()

    private lazy var bottomRightButton: UIBarButtonItem = {
        let button = UIBarButtonItem(title: .BookmarksEdit, style: .plain, target: self, action: #selector(bottomRightButtonAction))
        button.accessibilityIdentifier = AccessibilityIdentifiers.LibraryPanels.bottomRightButton
        return button
    }()

    // MARK: - Init

    init(viewModel: BookmarksPanelViewModel) {
        self.viewModel = viewModel
        self.state = viewModel.bookmarkFolderGUID == BookmarkRoots.MobileFolderGUID ? .bookmarks(state: .mainView) : .bookmarks(state: .inFolder)
        self.bookmarksHandler = viewModel.profile.places
        super.init(profile: viewModel.profile)

        setupNotifications(forObserver: self, observing: [.FirefoxAccountChanged])

        tableView.register(cellType: OneLineTableViewCell.self)
        tableView.register(cellType: SeparatorTableViewCell.self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let tableViewLongPressRecognizer = UILongPressGestureRecognizer(target: self,
                                                                        action: #selector(didLongPressTableView))
        tableView.addGestureRecognizer(tableViewLongPressRecognizer)
        tableView.accessibilityIdentifier = AccessibilityIdentifiers.LibraryPanels.BookmarksPanel.tableView
        tableView.allowsSelectionDuringEditing = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if self.state == .bookmarks(state: .inFolderEditMode) {
            self.tableView.setEditing(true, animated: true)
        }
    }

    // MARK: - Data

    override func reloadData() {
        viewModel.reloadData { [weak self] in
            self?.tableView.reloadData()

            if self?.viewModel.shouldFlashRow ?? false {
                self?.flashRow()
            }
        }
    }

    // MARK: - Actions

    func presentInFolderActions() {
        let viewModel = PhotonActionSheetViewModel(actions: [[getNewBookmarkAction(),
                                                              getNewFolderAction(),
                                                              getNewSeparatorAction()]],
                                                   modalStyle: .overFullScreen)
        let sheet = PhotonActionSheet(viewModel: viewModel)
        sheet.modalTransitionStyle = .crossDissolve
        present(sheet, animated: true)
    }

    private func getNewBookmarkAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .BookmarksNewBookmark,
                                     iconString: ImageIdentifiers.actionAddBookmark,
                                     tapHandler: { _ in
            guard let bookmarkFolder = self.viewModel.bookmarkFolder else { return }

            self.updatePanelState(newState: .bookmarks(state: .itemEditMode))
            let detailController = BookmarkDetailPanel(profile: self.profile,
                                                       withNewBookmarkNodeType: .bookmark,
                                                       parentBookmarkFolder: bookmarkFolder)
            self.navigationController?.pushViewController(detailController, animated: true)
        }).items
    }

    private func getNewFolderAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .BookmarksNewFolder,
                                     iconString: ImageIdentifiers.bookmarkFolder,
                                     tapHandler: { _ in
            guard let bookmarkFolder = self.viewModel.bookmarkFolder else { return }

            self.updatePanelState(newState: .bookmarks(state: .itemEditMode))
            let detailController = BookmarkDetailPanel(profile: self.profile,
                                                       withNewBookmarkNodeType: .folder,
                                                       parentBookmarkFolder: bookmarkFolder)
            self.navigationController?.pushViewController(detailController, animated: true)
        }).items
    }

    private func getNewSeparatorAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .BookmarksNewSeparator,
                                     iconString: ImageIdentifiers.navMenu,
                                     tapHandler: { _ in
            let centerVisibleRow = self.centerVisibleRow()

            self.profile.places.createSeparator(parentGUID: self.viewModel.bookmarkFolderGUID,
                                                position: UInt32(centerVisibleRow)) >>== { guid in
                self.profile.places.getBookmark(guid: guid).uponQueue(.main) { result in
                    guard let bookmarkNode = result.successValue,
                          let bookmarkSeparator = bookmarkNode as? BookmarkSeparatorData
                    else { return }

                    let indexPath = IndexPath(row: centerVisibleRow,
                                              section: BookmarksPanelViewModel.BookmarksSection.bookmarks.rawValue)
                    self.tableView.beginUpdates()
                    self.viewModel.bookmarkNodes.insert(bookmarkSeparator, at: centerVisibleRow)
                    self.tableView.insertRows(at: [indexPath], with: .automatic)
                    self.tableView.endUpdates()

                    self.flashRow(at: indexPath)
                }
            }
        }).items
    }

    private func centerVisibleRow() -> Int {
        let visibleCells = tableView.visibleCells
        if let middleCell = visibleCells[safe: visibleCells.count / 2],
           let middleIndexPath = tableView.indexPath(for: middleCell) {
            return middleIndexPath.row
        }

        return viewModel.bookmarkNodes.count
    }

    private func deleteBookmarkNodeAtIndexPath(_ indexPath: IndexPath) {
        guard let bookmarkNode = viewModel.bookmarkNodes[safe: indexPath.row]else {
            return
        }

        // If this node is a folder and it is not empty, we need
        // to prompt the user before deleting.
        if bookmarkNode.isNonEmptyFolder {
            presentDeletingActionToUser(indexPath, bookmarkNode: bookmarkNode)
            return
        }

        deleteBookmarkNode(indexPath, bookmarkNode: bookmarkNode)
    }

    private func presentDeletingActionToUser(_ indexPath: IndexPath, bookmarkNode: FxBookmarkNode) {
        let alertController = UIAlertController(title: .BookmarksDeleteFolderWarningTitle,
                                                message: .BookmarksDeleteFolderWarningDescription,
                                                preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: .BookmarksDeleteFolderCancelButtonLabel,
                                                style: .cancel))
        alertController.addAction(UIAlertAction(title: .BookmarksDeleteFolderDeleteButtonLabel,
                                                style: .destructive) { [weak self] action in
            self?.deleteBookmarkNode(indexPath, bookmarkNode: bookmarkNode)
        })
        present(alertController, animated: true, completion: nil)
    }

    /// Performs the delete asynchronously even though we update the
    /// table view data source immediately for responsiveness.
    private func deleteBookmarkNode(_ indexPath: IndexPath, bookmarkNode: FxBookmarkNode) {
        profile.places.deleteBookmarkNode(guid: bookmarkNode.guid).uponQueue(.main) { _ in
            self.removeBookmarkShortcut()
        }

        tableView.beginUpdates()
        viewModel.bookmarkNodes.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .left)
        tableView.endUpdates()
    }

    // MARK: Button Actions helpers

    func enableEditMode() {
        updatePanelState(newState: .bookmarks(state: .inFolderEditMode))
        self.tableView.setEditing(true, animated: true)
        sendPanelChangeNotification()
    }

    func disableEditMode() {
        let substate: LibraryPanelSubState = viewModel.isRootNode ? .mainView : .inFolder
        updatePanelState(newState: .bookmarks(state: substate))
        self.tableView.setEditing(false, animated: true)
        sendPanelChangeNotification()
    }

    private func sendPanelChangeNotification() {
        let userInfo: [String: Any] = ["state": state]
        NotificationCenter.default.post(name: .LibraryPanelStateDidChange, object: nil, userInfo: userInfo)
    }

    // MARK: - Utility

    private func indexPathIsValid(_ indexPath: IndexPath) -> Bool {
        return indexPath.section < numberOfSections(in: tableView)
        && indexPath.row < tableView(tableView, numberOfRowsInSection: indexPath.section)
        && viewModel.bookmarkFolderGUID != BookmarkRoots.MobileFolderGUID
    }

    private func numberOfSections(in tableView: UITableView) -> Int {
        if let folder = viewModel.bookmarkFolder, folder.guid == BookmarkRoots.RootGUID {
            return 2
        }

        return 1
    }

    private func flashRow() {
        let lastIndexPath = IndexPath(row: viewModel.bookmarkNodes.count - 1,
                                      section: BookmarksPanelViewModel.BookmarksSection.bookmarks.rawValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + UX.RowFlashDelay) {
            self.flashRow(at: lastIndexPath)
        }
    }

    private func flashRow(at indexPath: IndexPath) {
        guard indexPathIsValid(indexPath) else {
            browserLog.debug("Flash row indexPath invalid")
            return
        }

        browserLog.debug("Flash row by selecting at \(indexPath)")
        tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)

        DispatchQueue.main.asyncAfter(deadline: .now() + UX.RowFlashDelay) {
            if self.indexPathIsValid(indexPath) {
                self.browserLog.debug("Flash row by deselecting row at \(indexPath)")
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    // MARK: - Long press

    @objc private func didLongPressTableView(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        let touchPoint = longPressGestureRecognizer.location(in: tableView)
        guard longPressGestureRecognizer.state == .began,
              let indexPath = tableView.indexPathForRow(at: touchPoint) else {
            return
        }

        presentContextMenu(for: indexPath)
    }

    @objc private func didLongPressBackButtonView(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        navigationController?.popToRootViewController(animated: true)
    }

    private func backButtonView() -> UIView? {
        let navigationBarContentView = navigationController?.navigationBar.subviews.find {
            $0.description.starts(with: "<_UINavigationBarContentView:")
        }

        return navigationBarContentView?.subviews.find {
            $0.description.starts(with: "<_UIButtonBarButton:")
        }
    }

    // MARK: - UITableViewDataSource | UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let node = viewModel.bookmarkNodes[safe: indexPath.row],
              let bookmarkCell = node as? BookmarksFolderCell
        else { return }

        guard !tableView.isEditing else {
            if let bookmarkFolder = self.viewModel.bookmarkFolder,
                !(node is BookmarkSeparatorData),
                isCurrentFolderEditable(at: indexPath) {
                // Only show detail controller for editable nodes
                showBookmarkDetailController(for: node, folder: bookmarkFolder)
            }
            return
        }

        updatePanelState(newState: .bookmarks(state: .inFolder))
        bookmarkCell.didSelect(profile: profile,
                               libraryPanelDelegate: libraryPanelDelegate,
                               navigationController: navigationController)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.bookmarkNodes.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let node = viewModel.bookmarkNodes[safe: indexPath.row] else {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        if let bookmarkCell = node as? BookmarksFolderCell,
            let cell = tableView.dequeueReusableCell(
                withIdentifier: OneLineTableViewCell.cellIdentifier,
                for: indexPath) as? OneLineTableViewCell {
            // Site is needed on BookmarkItemData to setup cell image
            var site: Site?
            if let node = node as? BookmarkItemData {
                site = Site(url: node.url,
                            title: node.title,
                            bookmarked: true,
                            guid: node.guid)
            }
            cell.tag = indexPath.item

            let viewModel = bookmarkCell.getViewModel(forSite: site,
                                                      profile: profile) { viewModel in
                guard cell.tag == indexPath.item else { return }

                // Configure again once image is loaded for BookmarkItemData
                cell.configure(viewModel: viewModel)
                cell.setNeedsLayout()
            }

            cell.configure(viewModel: viewModel)
            cell.applyTheme(theme: themeManager.currentTheme)
            return cell
        } else {
            if let cell = tableView.dequeueReusableCell(withIdentifier: SeparatorTableViewCell.cellIdentifier,
                                                        for: indexPath) as? SeparatorTableViewCell {
                cell.applyTheme(theme: themeManager.currentTheme)
                return cell
            } else {
                return UITableViewCell()
            }
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return isCurrentFolderEditable(at: indexPath)
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return isCurrentFolderEditable(at: indexPath)
    }

    private func showBookmarkDetailController(for node: FxBookmarkNode, folder: FxBookmarkNode) {
        TelemetryWrapper.recordEvent(category: .action, method: .change, object: .bookmark, value: .bookmarksPanel)
        let detailController = BookmarkDetailPanel(profile: profile,
                                                   bookmarkNode: node,
                                                   parentBookmarkFolder: folder)
        updatePanelState(newState: .bookmarks(state: .itemEditMode))
        navigationController?.pushViewController(detailController, animated: true)
    }

    /// Root folders and local desktop folder cannot be moved or edited
    private func isCurrentFolderEditable(at indexPath: IndexPath) -> Bool {
        guard let currentRowData = viewModel.bookmarkNodes[safe: indexPath.row] else {
            return false
        }

        var uneditableGuids = Array(BookmarkRoots.All)
        uneditableGuids.append(LocalDesktopFolder.localDesktopFolderGuid)
        return !uneditableGuids.contains(currentRowData.guid)
    }

    func tableView(_ tableView: UITableView,
                   moveRowAt sourceIndexPath: IndexPath,
                   to destinationIndexPath: IndexPath) {
        viewModel.moveRow(at: sourceIndexPath, to: destinationIndexPath)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive,
                                              title: .BookmarksPanelDeleteTableAction) { [weak self] (_, _, completion) in
            guard let strongSelf = self else { completion(false); return }

            strongSelf.deleteBookmarkNodeAtIndexPath(indexPath)
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .delete,
                                         object: .bookmark,
                                         value: .bookmarksPanel,
                                         extras: ["gesture": "swipe"])
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }
}

// MARK: - LibraryPanelContextMenu

extension BookmarksPanel: LibraryPanelContextMenu {
    func presentContextMenu(for site: Site,
                            with indexPath: IndexPath,
                            completionHandler: @escaping () -> PhotonActionSheet?) {
        guard let contextMenu = completionHandler() else {
            return
        }

        present(contextMenu, animated: true, completion: nil)
    }

    func getSiteDetails(for indexPath: IndexPath) -> Site? {
        guard let bookmarkNode = viewModel.bookmarkNodes[safe: indexPath.row],
              let bookmarkItem = bookmarkNode as? BookmarkItemData
        else {
            self.browserLog.debug("Could not get site details for indexPath \(indexPath)")
            return nil
        }

        return Site(url: bookmarkItem.url, title: bookmarkItem.title, bookmarked: true, guid: bookmarkItem.guid)
    }

    func getContextMenuActions(for site: Site, with indexPath: IndexPath) -> [PhotonRowActions]? {
        guard var actions = getDefaultContextMenuActions(for: site, libraryPanelDelegate: libraryPanelDelegate) else {
            return nil
        }

        let pinTopSite = SingleActionViewModel(title: .AddToShortcutsActionTitle,
                                               iconString: ImageIdentifiers.addShortcut,
                                               tapHandler: { _ in
            self.profile.history.addPinnedTopSite(site).uponQueue(.main) { result in
                if result.isSuccess {
                    SimpleToast().showAlertWithText(.AppMenu.AddPinToShortcutsConfirmMessage,
                                                    bottomContainer: self.view)
                } else {
                    self.browserLog.debug("Could not add pinned top site")
                }
            }
        }).items
        actions.append(pinTopSite)

        let removeAction = SingleActionViewModel(title: .RemoveBookmarkContextMenuTitle,
                                                 iconString: ImageIdentifiers.actionRemoveBookmark,
                                                 tapHandler: { _ in
            self.deleteBookmarkNodeAtIndexPath(indexPath)
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .delete,
                                         object: .bookmark,
                                         value: .bookmarksPanel,
                                         extras: ["gesture": "long-press"])
        }).items
        actions.append(removeAction)

        return actions
    }
}

// MARK: - Notifiable
extension BookmarksPanel: Notifiable {
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .FirefoxAccountChanged:
            reloadData()
        default:
            browserLog.warning("Received unexpected notification \(notification.name)")
            break
        }
    }
}

// MARK: - Toolbar button actions
extension BookmarksPanel {
    func bottomLeftButtonAction() {
        if state == .bookmarks(state: .inFolderEditMode) {
            presentInFolderActions()
        }
    }

    func handleLeftTopButton() {
        guard case .bookmarks(let subState) = state else { return }

        switch subState {
        case .inFolder:
            if viewModel.isRootNode {
                updatePanelState(newState: .bookmarks(state: .mainView))
            }
        case .inFolderEditMode:
            presentInFolderActions()

        case .itemEditMode:
            updatePanelState(newState: .bookmarks(state: .inFolderEditMode))

        default:
            return
        }
    }

    func handleRightTopButton() {
        if state == .bookmarks(state: .itemEditMode) {
            handleItemEditMode()
        }
    }

    func shouldDismissOnDone() -> Bool {
        guard state != .bookmarks(state: .itemEditMode) else { return false }

        return true
    }

    func bottomRightButtonAction() {
        guard case .bookmarks(let subState) = state else { return }

        switch subState {
        case .mainView, .inFolder:
            enableEditMode()
        case .inFolderEditMode:
            disableEditMode()
        case .itemEditMode:
            handleItemEditMode()
        default:
            return
        }
    }

    func handleItemEditMode() {
        guard let bookmarkEditView = navigationController?.viewControllers.last as? BookmarkDetailPanel else { return }

        updatePanelState(newState: .bookmarks(state: .inFolderEditMode))
        bookmarkEditView.save().uponQueue(.main) { _ in
            self.navigationController?.popViewController(animated: true)
            if bookmarkEditView.isNew {
                self.viewModel.didAddBookmarkNode()
            }
        }
    }
}
