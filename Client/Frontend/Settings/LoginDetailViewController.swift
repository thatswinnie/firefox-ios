// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Storage
import Shared
import Common

enum InfoItem: Int {
    case breachItem = 0
    case websiteItem
    case usernameItem
    case passwordItem
    case lastModifiedSeparator
    case deleteItem

    var indexPath: IndexPath {
        return IndexPath(row: rawValue, section: 0)
    }
}

struct LoginDetailUX {
    static let InfoRowHeight: CGFloat = 58
    static let DeleteRowHeight: CGFloat = 44
    static let SeparatorHeight: CGFloat = 84
}

private class CenteredDetailCell: ThemedTableViewCell, ReusableCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        var f = detailTextLabel?.frame ?? CGRect()
        f.center = CGPoint(x: frame.center.x - safeAreaInsets.right, y: frame.center.y)
        detailTextLabel?.frame = f
    }

    override func applyTheme(theme: Theme) {
        super.applyTheme(theme: theme)
        backgroundColor = theme.colors.layer1
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class LoginDetailViewController: SensitiveViewController, Themeable {
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?
    var notificationCenter: NotificationProtocol

    private let profile: Profile

    private lazy var tableView: UITableView = .build { [weak self] tableView in
        guard let self = self else { return }
        tableView.accessibilityIdentifier = "Login Detail List"
        tableView.delegate = self
        tableView.dataSource = self

        // Add empty footer view to prevent separators from being drawn past the last item.
        tableView.tableFooterView = UIView()
    }

    private weak var websiteField: UITextField?
    private weak var usernameField: UITextField?
    private weak var passwordField: UITextField?
    private var deleteAlert: UIAlertController?
    weak var settingsDelegate: SettingsDelegate?
    private var breach: BreachRecord?
    private var login: LoginRecord {
        didSet {
            tableView.reloadData()
        }
    }
    var webpageNavigationHandler: ((_ url: URL?) -> Void)?

    private var isEditingFieldData: Bool = false {
        didSet {
            if isEditingFieldData != oldValue {
                tableView.reloadData()
            }
        }
    }

    init(profile: Profile,
         login: LoginRecord,
         webpageNavigationHandler: ((_ url: URL?) -> Void)?,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationCenter = NotificationCenter.default) {
        self.login = login
        self.profile = profile
        self.webpageNavigationHandler = webpageNavigationHandler
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(dismissAlertController), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func setBreachRecord(breach: BreachRecord?) {
        self.breach = breach
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit))

        tableView.register(cellType: LoginDetailTableViewCell.self)
        tableView.register(cellType: CenteredDetailCell.self)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.estimatedRowHeight = 44.0
        tableView.separatorInset = .zero

        applyTheme()
        listenForThemeChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Normally UITableViewControllers handle responding to content inset changes from keyboard events when editing
        // but since we don't use the tableView's editing flag for editing we handle this ourselves.
        KeyboardHelper.defaultHelper.addDelegate(self)
    }

    func applyTheme() {
        let theme = themeManager.currentTheme
        tableView.separatorColor = theme.colors.borderPrimary
        tableView.backgroundColor = theme.colors.layer1
    }
}

// MARK: - UITableViewDataSource
extension LoginDetailViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch InfoItem(rawValue: indexPath.row)! {
        case .breachItem:
            guard let breachCell = cell(tableView: tableView, forIndexPath: indexPath) else {
                return UITableViewCell()
            }
            guard let breach = breach else { return breachCell }
            breachCell.isHidden = false
            let breachDetailView = BreachAlertsDetailView()
            breachCell.contentView.addSubview(breachDetailView)

            NSLayoutConstraint.activate([
                breachDetailView.leadingAnchor.constraint(equalTo: breachCell.contentView.leadingAnchor, constant: LoginTableViewCellUX.HorizontalMargin),
                breachDetailView.topAnchor.constraint(equalTo: breachCell.contentView.topAnchor, constant: LoginTableViewCellUX.HorizontalMargin),
                breachDetailView.trailingAnchor.constraint(equalTo: breachCell.contentView.trailingAnchor, constant: LoginTableViewCellUX.HorizontalMargin),
                breachDetailView.bottomAnchor.constraint(equalTo: breachCell.contentView.bottomAnchor, constant: LoginTableViewCellUX.HorizontalMargin)
            ])
            breachDetailView.setup(breach)

            breachDetailView.learnMoreButton.addTarget(self, action: #selector(LoginDetailViewController.didTapBreachLearnMore), for: .touchUpInside)
            let breachLinkGesture = UITapGestureRecognizer(target: self, action: #selector(LoginDetailViewController
                .didTapBreachLink(_:)))
            breachDetailView.goToButton.addGestureRecognizer(breachLinkGesture)
            breachCell.isAccessibilityElement = false
            breachCell.contentView.accessibilityElementsHidden = true
            breachCell.accessibilityElements = [breachDetailView]
            breachCell.applyTheme(theme: themeManager.currentTheme)

            return breachCell

        case .usernameItem:
            guard let loginCell = cell(tableView: tableView, forIndexPath: indexPath) else {
                return UITableViewCell()
            }
            loginCell.highlightedLabelTitle = .LoginDetailUsername
            loginCell.descriptionLabel.text = login.decryptedUsername
            loginCell.descriptionLabel.keyboardType = .emailAddress
            loginCell.descriptionLabel.returnKeyType = .next
            loginCell.isEditingFieldData = isEditingFieldData
            usernameField = loginCell.descriptionLabel
            usernameField?.accessibilityIdentifier = "usernameField"
            loginCell.applyTheme(theme: themeManager.currentTheme)
            return loginCell

        case .passwordItem:
            guard let loginCell = cell(tableView: tableView, forIndexPath: indexPath) else {
                return UITableViewCell()
            }
            loginCell.highlightedLabelTitle = .LoginDetailPassword
            loginCell.descriptionLabel.text = login.decryptedPassword
            loginCell.descriptionLabel.returnKeyType = .default
            loginCell.displayDescriptionAsPassword = true
            loginCell.isEditingFieldData = isEditingFieldData
            setCellSeparatorHidden(loginCell)
            passwordField = loginCell.descriptionLabel
            passwordField?.accessibilityIdentifier = "passwordField"
            loginCell.applyTheme(theme: themeManager.currentTheme)
            return loginCell

        case .websiteItem:
            guard let loginCell = cell(tableView: tableView, forIndexPath: indexPath) else {
                return UITableViewCell()
            }
            loginCell.highlightedLabelTitle = .LoginDetailWebsite
            loginCell.descriptionLabel.text = login.hostname
            websiteField = loginCell.descriptionLabel
            websiteField?.accessibilityIdentifier = "websiteField"
            loginCell.isEditingFieldData = false
            if isEditingFieldData {
                loginCell.contentView.alpha = 0.5
            }
            loginCell.applyTheme(theme: themeManager.currentTheme)
            return loginCell

        case .lastModifiedSeparator:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: CenteredDetailCell.cellIdentifier,
                                                           for: indexPath) as? CenteredDetailCell else {
                return UITableViewCell()
            }

            let created: String = .LoginDetailCreatedAt
            let lastModified: String = .LoginDetailModifiedAt

            let lastModifiedFormatted = String(format: lastModified, Date.fromTimestamp(UInt64(login.timePasswordChanged)).toRelativeTimeString(dateStyle: .medium))
            let createdFormatted = String(format: created, Date.fromTimestamp(UInt64(login.timeCreated)).toRelativeTimeString(dateStyle: .medium, timeStyle: .none))
            // Setting only the detail text produces smaller text as desired, and it is centered.
            cell.detailTextLabel?.text = createdFormatted + "\n" + lastModifiedFormatted
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.textAlignment = .center
            setCellSeparatorHidden(cell)
            cell.applyTheme(theme: themeManager.currentTheme)
            return cell

        case .deleteItem:
            guard let deleteCell = cell(tableView: tableView, forIndexPath: indexPath) else {
                return UITableViewCell()
            }
            deleteCell.textLabel?.text = .LoginDetailDelete
            deleteCell.textLabel?.textAlignment = .center
            deleteCell.accessibilityTraits = UIAccessibilityTraits.button
            deleteCell.configure(type: .delete)
            deleteCell.applyTheme(theme: themeManager.currentTheme)

            setCellSeparatorFullWidth(deleteCell)
            return deleteCell
        }
    }

    private func cell(tableView: UITableView, forIndexPath indexPath: IndexPath) -> LoginDetailTableViewCell? {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: LoginDetailTableViewCell.cellIdentifier,
                                                       for: indexPath) as? LoginDetailTableViewCell else {
            return nil
        }
        cell.selectionStyle = .none
        cell.delegate = self
        return cell
    }

    private func setCellSeparatorHidden(_ cell: UITableViewCell) {
        // Prevent seperator from showing by pushing it off screen by the width of the cell
        cell.separatorInset = UIEdgeInsets(top: 0,
                                           left: 0,
                                           bottom: 0,
                                           right: view.frame.width)
    }

    private func setCellSeparatorFullWidth(_ cell: UITableViewCell) {
        cell.separatorInset = .zero
        cell.layoutMargins = .zero
        cell.preservesSuperviewLayoutMargins = false
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 6
    }
}

// MARK: - UITableViewDelegate
extension LoginDetailViewController: UITableViewDelegate {
    private func showMenuOnSingleTap(forIndexPath indexPath: IndexPath) {
        guard let item = InfoItem(rawValue: indexPath.row) else { return }
        if ![InfoItem.passwordItem, InfoItem.websiteItem, InfoItem.usernameItem].contains(item) {
            return
        }

        guard let cell = tableView.cellForRow(at: indexPath) as? LoginDetailTableViewCell else { return }

        cell.becomeFirstResponder()

        let menu = UIMenuController.shared
        menu.showMenu(from: tableView, rect: cell.frame)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath == InfoItem.deleteItem.indexPath {
            deleteLogin()
        } else if !isEditingFieldData {
            showMenuOnSingleTap(forIndexPath: indexPath)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch InfoItem(rawValue: indexPath.row)! {
        case .breachItem:
            guard breach != nil else { return 0 }
            return UITableView.automaticDimension
        case .usernameItem, .passwordItem, .websiteItem:
            return LoginDetailUX.InfoRowHeight
        case .lastModifiedSeparator:
            return LoginDetailUX.SeparatorHeight
        case .deleteItem:
            return LoginDetailUX.DeleteRowHeight
        }
    }
}

// MARK: - KeyboardHelperDelegate
extension LoginDetailViewController: KeyboardHelperDelegate {
    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

// MARK: - Selectors
extension LoginDetailViewController {
    @objc func dismissAlertController() {
        deleteAlert?.dismiss(animated: false, completion: nil)
    }

    @objc func didTapBreachLearnMore() {
        webpageNavigationHandler?(BreachAlertsManager.monitorAboutUrl)
    }

    @objc func didTapBreachLink(_ sender: UITapGestureRecognizer? = nil) {
        guard let domain = breach?.domain else { return }
        var urlComponents = URLComponents()
        urlComponents.host = domain
        urlComponents.scheme = "https"
        webpageNavigationHandler?(urlComponents.url)
    }

    func deleteLogin() {
        profile.hasSyncedLogins().uponQueue(.main) { yes in
            self.deleteAlert = UIAlertController.deleteLoginAlertWithDeleteCallback({ [unowned self] _ in
                self.profile.logins.deleteLogin(id: self.login.id).uponQueue(.main) { _ in
                    _ = self.navigationController?.popViewController(animated: true)
                }
            }, hasSyncedLogins: yes.successValue ?? true)

            self.present(self.deleteAlert!, animated: true, completion: nil)
        }
    }

    func onProfileDidFinishSyncing() {
        // Reload details after syncing.
        profile.logins.getLogin(id: login.id).uponQueue(.main) { result in
            if let successValue = result.successValue, let syncedLogin = successValue {
                self.login = syncedLogin
            }
        }
    }

    @objc func edit() {
        isEditingFieldData = true
        guard let cell = tableView.cellForRow(at: InfoItem.usernameItem.indexPath) as? LoginDetailTableViewCell else { return }
        cell.descriptionLabel.becomeFirstResponder()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneEditing))
    }

    @objc func doneEditing() {
        isEditingFieldData = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit))

        // Only update if user made changes
        guard let username = usernameField?.text, let password = passwordField?.text else { return }

        guard username != login.decryptedUsername || password != login.decryptedPassword else { return }

        let updatedLogin = LoginEntry(
            fromLoginEntryFlattened: LoginEntryFlattened(
                id: login.id,
                hostname: login.hostname,
                password: password,
                username: username,
                httpRealm: login.httpRealm,
                formSubmitUrl: login.formSubmitUrl,
                usernameField: login.usernameField,
                passwordField: login.passwordField
            )
        )

        if updatedLogin.isValid.isSuccess {
            profile.logins.updateLogin(id: login.id, login: updatedLogin).uponQueue(.main) { _ in
                self.onProfileDidFinishSyncing()
                // Required to get UI to reload with changed state
                self.tableView.reloadData()
            }
        }
    }
}

// MARK: - Cell Delegate
extension LoginDetailViewController: LoginDetailTableViewCellDelegate {
    func textFieldDidEndEditing(_ cell: LoginDetailTableViewCell) { }
    func textFieldDidChange(_ cell: LoginDetailTableViewCell) { }

    func canPerform(action: Selector, for cell: LoginDetailTableViewCell) -> Bool {
        guard let item = infoItemForCell(cell) else { return false }

        switch item {
        case .websiteItem:
            // Menu actions for Website
            return action == MenuHelper.SelectorCopy || action == MenuHelper.SelectorOpenAndFill
        case .usernameItem:
            // Menu actions for Username
            return action == MenuHelper.SelectorCopy
        case .passwordItem:
            // Menu actions for password
            let showRevealOption = cell.descriptionLabel.isSecureTextEntry ? (action == MenuHelper.SelectorReveal) : (action == MenuHelper.SelectorHide)
            return action == MenuHelper.SelectorCopy || showRevealOption
        default:
            return false
        }
    }

    private func cellForItem(_ item: InfoItem) -> LoginDetailTableViewCell? {
        return tableView.cellForRow(at: item.indexPath) as? LoginDetailTableViewCell
    }

    func didSelectOpenAndFillForCell(_ cell: LoginDetailTableViewCell) {
        guard let url = (login.formSubmitUrl?.asURL ?? login.hostname.asURL) else { return }

        navigationController?.dismiss(animated: true, completion: {
            self.settingsDelegate?.settingsOpenURLInNewTab(url)
        })
    }

    func shouldReturnAfterEditingDescription(_ cell: LoginDetailTableViewCell) -> Bool {
        let usernameCell = cellForItem(.usernameItem)
        let passwordCell = cellForItem(.passwordItem)

        if cell == usernameCell {
            passwordCell?.descriptionLabel.becomeFirstResponder()
        }

        return false
    }

    func infoItemForCell(_ cell: LoginDetailTableViewCell) -> InfoItem? {
        if let index = tableView.indexPath(for: cell),
            let item = InfoItem(rawValue: index.row) {
            return item
        }
        return nil
    }
}
