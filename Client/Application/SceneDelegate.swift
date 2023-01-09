// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import CoreSpotlight
import Storage
import Shared
import Sync
import UserNotifications
import Account
import MozillaAppServices
import Common

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// This is temporary. We don't want to continue treating App / Scene delegates as containers for certain session specific properties.
    /// TODO: When we begin to support multiple scenes, this is risky to keep. If we foregroundBVC, we should have a more specific
    /// way to foreground the BVC FOR the scene being actively interacted with.
    var browserViewController: BrowserViewController!

    let profile: Profile = AppContainer.shared.resolve()
    let tabManager: TabManager = AppContainer.shared.resolve()
    var sessionManager: AppSessionProvider = AppContainer.shared.resolve()
    var downloadQueue: DownloadQueue = AppContainer.shared.resolve()

    // MARK: - Connecting / Disconnecting Scenes

    /// Invoked when the app creates OR restores an instance of the UI.
    ///
    /// Use this method to respond to the addition of a new scene, and begin loading data that needs to display.
    /// Take advantage of what's given in `options`.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard !AppConstants.isRunningUnitTest else { return }

        let window = configureWindowFor(scene)
        let rootVC = configureRootViewController()

        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        self.window = window

        var themeManager: ThemeManager = AppContainer.shared.resolve()
        themeManager.window = window

        handleDeeplinkOrShortcutsAtLaunch(with: connectionOptions, on: scene)
    }

    // MARK: - Transitioning to Foreground

    /// Invoked when the interface is finished loading for your screen, but before that interface appears on screen.
    ///
    /// Use this method to refresh the contents of your scene's view (especially if it's a restored scene), or other activities that need
    /// to begin.
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !AppConstants.isRunningUnitTest else { return }

        /// Resume previously stopped downloads for, and on, THIS scene only.
        downloadQueue.resumeAll()
    }

    // MARK: - Transitioning to Background

    /// The scene's running in the background and not visible on screen.
    ///
    /// Use this method to reduce the scene's memory usage, clear claims to resources & dependencies / services.
    /// UIKit takes a snapshot of the scene for the app switcher after this method returns.
    func sceneDidEnterBackground(_ scene: UIScene) {
        downloadQueue.pauseAll()
    }

    // MARK: - Opening URLs

    /// Asks the delegate to open one or more URLs.
    ///
    /// This method is equivalent to AppDelegate's openURL method. We implement deep links this way.
    func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        guard let url = URLContexts.first?.url,
              let routerPath = NavigationPath(url: url) else { return }

        if profile.prefs.boolForKey(PrefsKeys.AppExtensionTelemetryOpenUrl) != nil {
            profile.prefs.removeObjectForKey(PrefsKeys.AppExtensionTelemetryOpenUrl)

            var object = TelemetryWrapper.EventObject.url
            if case .text = routerPath {
                object = .searchText
            }

            TelemetryWrapper.recordEvent(category: .appExtensionAction, method: .applicationOpenUrl, object: object)
        }

        DispatchQueue.main.async {
            NavigationPath.handle(nav: routerPath, with: self.browserViewController)
        }

        sessionManager.launchSessionProvider.openedFromExternalSource = true
    }

    // MARK: - Continuing User Activities

    /// Use this method to handle Handoff-related data or other activities.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if userActivity.activityType == SiriShortcuts.activityType.openURL.rawValue {
            browserViewController.openBlankNewTab(focusLocationField: false)
        }

        // If the `NSUserActivity` has a `webpageURL`, it is either a deep link or an old history item
        // reached via a "Spotlight" search before we began indexing visited pages via CoreSpotlight.
        if let url = userActivity.webpageURL {
            let query = url.getQuery()

            // Check for fxa sign-in code and launch the login screen directly
            if query["signin"] != nil {
                // bvc.launchFxAFromDeeplinkURL(url) // Was using Adjust. Consider hooking up again when replacement system in-place.
            }

            // Per Adjust documentation, https://docs.adjust.com/en/universal-links/#running-campaigns-through-universal-links,
            // it is recommended that links contain the `deep_link` query parameter. This link will also
            // be url encoded.
            if let deepLink = query["deep_link"]?.removingPercentEncoding, let url = URL(string: deepLink) {
                browserViewController.switchToTabForURLOrOpen(url)
            }

            browserViewController.switchToTabForURLOrOpen(url)
        }

        // Otherwise, check if the `NSUserActivity` is a CoreSpotlight item and switch to its tab or
        // open a new one.
        if userActivity.activityType == CSSearchableItemActionType {
            if let userInfo = userActivity.userInfo,
                let urlString = userInfo[CSSearchableItemActivityIdentifier] as? String,
                let url = URL(string: urlString) {
                browserViewController.switchToTabForURLOrOpen(url)
            }
        }
    }

    // MARK: - Performing Tasks

    /// Use this method to handle a selected shortcut action.
    ///
    /// Invoked when:
    /// - a user activates the application by selecting a shortcut item on the home screen AND
    /// - the window scene is already connected.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        QuickActionsImplementation().handleShortCutItem(
            shortcutItem,
            withBrowserViewController: browserViewController,
            completionHandler: completionHandler
        )
    }

    // MARK: - Misc. Helpers

    private func configureWindowFor(_ scene: UIScene) -> UIWindow {
        guard let windowScene = (scene as? UIWindowScene) else {
            return UIWindow(frame: UIScreen.main.bounds)
        }

        if #available(iOS 14, *) {
            windowScene.screenshotService?.delegate = self
        }

        let window = UIWindow(windowScene: windowScene)

        // Setting the initial theme correctly as we don't have a window attached yet to let ThemeManager set it
        let themeManager: ThemeManager = AppContainer.shared.resolve()
        window.overrideUserInterfaceStyle = themeManager.currentTheme.type.getInterfaceStyle()

        return window
    }

    private func configureRootViewController() -> UINavigationController {
        let browserViewController = BrowserViewController(profile: profile, tabManager: tabManager)

        // TODO: When we begin to support multiple scenes, remove this line and the reference to BVC in SceneDelegate.
        self.browserViewController = browserViewController

        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.isNavigationBarHidden = true
        navigationController.edgesForExtendedLayout = UIRectEdge(rawValue: 0)

        return navigationController
    }

    /// Handling either deeplinks or shortcuts at launch is slightly different than when the scene has been backgrounded.
    private func handleDeeplinkOrShortcutsAtLaunch(
        with connectionOptions: UIScene.ConnectionOptions,
        on scene: UIScene
    ) {
        if !connectionOptions.urlContexts.isEmpty {
            self.scene(scene, openURLContexts: connectionOptions.urlContexts)
        }

        if let shortcutItem = connectionOptions.shortcutItem {
            QuickActionsImplementation().handleShortCutItem(
                shortcutItem,
                withBrowserViewController: browserViewController,
                completionHandler: { _ in }
            )
        }
    }
}

@available(iOS 14, *)
extension SceneDelegate: UIScreenshotServiceDelegate {
    func screenshotService(_ screenshotService: UIScreenshotService,
                           generatePDFRepresentationWithCompletion completionHandler: @escaping (Data?, Int, CGRect) -> Void) {
        guard browserViewController.homepageViewController?.view.alpha != 1,
              browserViewController.presentedViewController == nil,
              let webView = tabManager.selectedTab?.currentWebView(),
              let url = webView.url,
              InternalURL(url) == nil else {
            completionHandler(nil, 0, .zero)
            return
        }

        var rect = webView.scrollView.frame
        rect.origin.x = webView.scrollView.contentOffset.x
        rect.origin.y = webView.scrollView.contentSize.height - rect.height - webView.scrollView.contentOffset.y

        webView.createPDF { result in
            switch result {
            case .success(let data):
                completionHandler(data, 0, rect)
            case .failure:
                completionHandler(nil, 0, .zero)
            }
        }
    }
}
