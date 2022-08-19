// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@testable import Client

import Glean
import XCTest

class TelemetryWrapperTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Glean.shared.resetGlean(clearStores: true)
    }

    override func tearDown() {
        super.tearDown()
        Glean.shared.resetGlean(clearStores: true)
    }

    // MARK: - Top Site

    func test_topSiteTileWithExtras_GleanIsCalled() {
        let topSitePositionKey = TelemetryWrapper.EventExtraKey.topSitePosition.rawValue
        let topSiteTileTypeKey = TelemetryWrapper.EventExtraKey.topSiteTileType.rawValue
        let extras = [topSitePositionKey: "\(1)", topSiteTileTypeKey: "history-based"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .topSiteTile, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.TopSites.tilePressed)
    }

    func test_topSiteTileWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .topSiteTile, value: nil)
        XCTAssertNil(GleanMetrics.TopSites.tilePressed.testGetValue())
    }

    func test_topSiteContextualMenu_GleanIsCalled() {
        let extras = [TelemetryWrapper.EventExtraKey.contextualMenuType.rawValue: HomepageContextMenuHelper.ContextualActionType.settings.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .topSiteContextualMenu, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.TopSites.contextualMenu)
    }

    func test_topSiteContextualMenuWithoutExtra_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .topSiteContextualMenu, value: nil, extras: nil)
        XCTAssertNil(GleanMetrics.TopSites.contextualMenu.testGetValue())
    }

    // MARK: - Preferences

    func test_preferencesWithExtras_GleanIsCalled() {
        let extras: [String: Any] = [TelemetryWrapper.EventExtraKey.preference.rawValue: "ETP-strength",
                                      TelemetryWrapper.EventExtraKey.preferenceChanged.rawValue: BlockingStrength.strict.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .change, object: .setting, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Preferences.changed)
    }

    func test_preferencesWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .change, object: .setting)
        XCTAssertNil(GleanMetrics.Preferences.changed.testGetValue())
    }

    // MARK: - Firefox Home Page

    func test_recentlySavedBookmarkViewWithExtras_GleanIsCalled() {
        let extras: [String: Any] = [TelemetryWrapper.EventObject.recentlySavedBookmarkImpressions.rawValue: "\([].count)"]
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .firefoxHomepage, value: .recentlySavedBookmarkItemView, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.FirefoxHomePage.recentlySavedBookmarkView)
    }

    func test_recentlySavedBookmarkViewWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .firefoxHomepage, value: .recentlySavedBookmarkItemView)
        XCTAssertNil(GleanMetrics.FirefoxHomePage.recentlySavedBookmarkView.testGetValue())
    }

    func test_recentlySavedReadingListViewViewWithExtras_GleanIsCalled() {
        let extras: [String: Any] = [TelemetryWrapper.EventObject.recentlySavedReadingItemImpressions.rawValue: "\([].count)"]
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .firefoxHomepage, value: .recentlySavedReadingListView, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.FirefoxHomePage.readingListView)
    }

    func test_recentlySavedReadingListViewWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .firefoxHomepage, value: .recentlySavedReadingListView)
        XCTAssertNil(GleanMetrics.FirefoxHomePage.readingListView.testGetValue())
    }

    func test_firefoxHomePageAddView_GleanIsCalled() {
        let extras = [TelemetryWrapper.EventExtraKey.fxHomepageOrigin.rawValue: TelemetryWrapper.EventValue.fxHomepageOriginZeroSearch.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .firefoxHomepage, value: .fxHomepageOrigin, extras: extras)

        testLabeledMetricSuccess(metric: GleanMetrics.FirefoxHomePage.firefoxHomepageOrigin)
    }

    // MARK: - CFR Analytics

    func test_contextualHintDismissButton_GleanIsCalled() {
        let extra = [TelemetryWrapper.EventExtraKey.cfrType.rawValue: ContextualHintType.toolbarLocation.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .contextualHint, value: .dismissCFRFromButton, extras: extra)

        testEventMetricRecordingSuccess(metric: GleanMetrics.CfrAnalytics.dismissCfrFromButton)
    }

    func test_contextualHintDismissButtonWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .contextualHint, value: .dismissCFRFromButton)
        XCTAssertNil(GleanMetrics.CfrAnalytics.dismissCfrFromButton.testGetValue())
    }

    func test_contextualHintDismissOutsideTap_GleanIsCalled() {
        let extra = [TelemetryWrapper.EventExtraKey.cfrType.rawValue: ContextualHintType.toolbarLocation.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .contextualHint, value: .dismissCFRFromOutsideTap, extras: extra)

        testEventMetricRecordingSuccess(metric: GleanMetrics.CfrAnalytics.dismissCfrFromOutsideTap)
    }

    func test_contextualHintDismissOutsideTapWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .contextualHint, value: .dismissCFRFromOutsideTap)
        XCTAssertNil(GleanMetrics.CfrAnalytics.dismissCfrFromOutsideTap.testGetValue())
    }

    func test_contextualHintPressAction_GleanIsCalled() {
        let extra = [TelemetryWrapper.EventExtraKey.cfrType.rawValue: ContextualHintType.toolbarLocation.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .contextualHint, value: .pressCFRActionButton, extras: extra)

        testEventMetricRecordingSuccess(metric: GleanMetrics.CfrAnalytics.pressCfrActionButton)
    }

    func test_contextualHintPressActionWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .contextualHint, value: .pressCFRActionButton)
        XCTAssertNil(GleanMetrics.CfrAnalytics.pressCfrActionButton.testGetValue())
    }

    // MARK: - Tabs quantity

    func test_tabsNormalQuantity_GleanIsCalled() {
        let expectTabCount: Int64 = 80
        let extra = [TelemetryWrapper.EventExtraKey.tabsQuantity.rawValue: expectTabCount]
        TelemetryWrapper.recordEvent(category: .information, method: .background, object: .tabNormalQuantity, value: nil, extras: extra)

        testQuantityMetricSuccess(metric: GleanMetrics.Tabs.normalTabsQuantity,
                                  expectedValue: expectTabCount,
                                  failureMessage: "Should have \(expectTabCount) tabs for normal tabs")
    }

    func test_tabsPrivateQuantity_GleanIsCalled() {
        let expectTabCount: Int64 = 60
        let extra = [TelemetryWrapper.EventExtraKey.tabsQuantity.rawValue: expectTabCount]
        TelemetryWrapper.recordEvent(category: .information, method: .background, object: .tabPrivateQuantity, value: nil, extras: extra)

        testQuantityMetricSuccess(metric: GleanMetrics.Tabs.privateTabsQuantity,
                                  expectedValue: expectTabCount,
                                  failureMessage: "Should have \(expectTabCount) tabs for private tabs")
    }

    func test_tabsNormalQuantityWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .information, method: .background, object: .tabNormalQuantity, value: nil, extras: nil)
        XCTAssertNil(GleanMetrics.Tabs.normalTabsQuantity.testGetValue())
    }

    func test_tabsPrivateQuantityWithoutExtras_GleanIsNotCalled() {
        TelemetryWrapper.recordEvent(category: .information, method: .background, object: .tabPrivateQuantity, value: nil, extras: nil)
        XCTAssertNil(GleanMetrics.Tabs.privateTabsQuantity.testGetValue())
    }

    // MARK: - Onboarding

    func test_onboardingCardViewWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.welcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .onboardingCardView, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Onboarding.cardView)
    }

    func test_onboardingPrimaryButtonWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.welcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .onboardingPrimaryButton, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Onboarding.primaryButtonTap)
    }

    func test_onboardingSecondaryButtonWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.welcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .onboardingSecondaryButton, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Onboarding.secondaryButtonTap)
    }

    func test_onboardingSelectWallpaperWithExtras_GleanIsCalled() {
        let wallpaperNameKey = TelemetryWrapper.EventExtraKey.wallpaperName.rawValue
        let wallpaperTypeKey = TelemetryWrapper.EventExtraKey.wallpaperType.rawValue
        let extras = [wallpaperNameKey: "defaultBackground",
                      wallpaperTypeKey: "default"]
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .onboardingSelectWallpaper,
                                     value: .wallpaperSelected,
                                     extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Onboarding.wallpaperSelected)
    }

    func test_onboardingCloseWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.welcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .onboardingClose, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Onboarding.closeTap)
    }

    // MARK: - Upgrade onboarding
    func test_upgradeCardViewWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.updateWelcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .view, object: .upgradeOnboardingCardView, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Upgrade.cardView)
    }

    func test_upgradePrimaryButtonWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.updateWelcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .upgradeOnboardingPrimaryButton, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Upgrade.primaryButtonTap)
    }

    func test_upgradeSecondaryButtonWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.updateWelcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .upgradeOnboardingSecondaryButton, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Upgrade.secondaryButtonTap)
    }

    func test_upgradeCloseWithExtras_GleanIsCalled() {
        let cardTypeKey = TelemetryWrapper.EventExtraKey.cardType.rawValue
        let extras = [cardTypeKey: "\(IntroViewModel.InformationCards.updateWelcome.telemetryValue)"]
        TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .upgradeOnboardingClose, value: nil, extras: extras)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Upgrade.closeTap)
    }

    // MARK: - Migration

    func test_SDWebImageDiskCacheClear_GleanIsCalled() {
        TelemetryWrapper.recordEvent(category: .information, method: .delete, object: .clearSDWebImageCache)
        testCounterMetricRecordingSuccess(metric: GleanMetrics.Migration.imageSdCacheCleanup)
    }

    // MARK: Wallpapers

    func test_backgroundWallpaperMetric_defaultBackgroundIsNotSent() {
        let profile = MockProfile()
        let wrapper = TelemetryWrapper(profile: profile)

        LegacyWallpaperManager().updateSelectedWallpaperIndex(to: 0)
        XCTAssertEqual(LegacyWallpaperManager().currentWallpaper.type, .defaultBackground)

        let fakeNotif = NSNotification(name: UIApplication.didEnterBackgroundNotification, object: nil)
        wrapper.recordEnteredBackgroundPreferenceMetrics(notification: fakeNotif)

        testLabeledMetricSuccess(metric: GleanMetrics.WallpaperAnalytics.themedWallpaper)
        let wallpaperName = LegacyWallpaperManager().currentWallpaper.name.lowercased()
        XCTAssertNil(GleanMetrics.WallpaperAnalytics.themedWallpaper[wallpaperName].testGetValue())
    }

    func test_backgroundWallpaperMetric_themedWallpaperIsSent() {
        let profile = MockProfile()
        let wrapper = TelemetryWrapper(profile: profile)

        LegacyWallpaperManager().updateSelectedWallpaperIndex(to: 1)
        XCTAssertNotEqual(LegacyWallpaperManager().currentWallpaper.type, .defaultBackground)

        let fakeNotif = NSNotification(name: UIApplication.didEnterBackgroundNotification, object: nil)
        wrapper.recordEnteredBackgroundPreferenceMetrics(notification: fakeNotif)

        testLabeledMetricSuccess(metric: GleanMetrics.WallpaperAnalytics.themedWallpaper)
        let wallpaperName = LegacyWallpaperManager().currentWallpaper.name.lowercased()
        XCTAssertEqual(GleanMetrics.WallpaperAnalytics.themedWallpaper[wallpaperName].testGetValue(), 1)
    }

    // MARK: - Awesomebar result tap
    func test_AwesomebarResults_GleanIsCalledForSearchSuggestion() {
        let extra = [TelemetryWrapper.EventExtraKey.awesomebarSearchTapType.rawValue: TelemetryWrapper.EventValue.searchSuggestion.rawValue]
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .awesomebarResults,
                                     extras: extra)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Awesomebar.searchResultTap)
    }

    func test_AwesomebarResults_GleanIsCalledRemoteTabs() {
        let extra = [TelemetryWrapper.EventExtraKey.awesomebarSearchTapType.rawValue: TelemetryWrapper.EventValue.remoteTab.rawValue]
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .awesomebarResults,
                                     extras: extra)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Awesomebar.searchResultTap)
    }

    func test_AwesomebarResults_GleanIsCalledHighlights() {
        let extra = [TelemetryWrapper.EventExtraKey.awesomebarSearchTapType.rawValue: TelemetryWrapper.EventValue.searchHighlights.rawValue]
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .awesomebarResults,
                                     extras: extra)

        testEventMetricRecordingSuccess(metric: GleanMetrics.Awesomebar.searchResultTap)
    }
}

// MARK: - Helper functions to test telemetry
extension XCTestCase {

    func testEventMetricRecordingSuccess<Keys: EventExtraKey, Extras: EventExtras>(metric: EventMetricType<Keys, Extras>,
                                                                               file: StaticString = #file,
                                                                               line: UInt = #line) {
        XCTAssertNotNil(metric.testGetValue(), file: file, line: line)
        XCTAssertEqual(metric.testGetValue()!.count, 1, file: file, line: line)

        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidLabel), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidOverflow), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidState), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidValue), 0, file: file, line: line)
    }

    func testCounterMetricRecordingSuccess(metric: CounterMetricType,
                                           file: StaticString = #file,
                                           line: UInt = #line) {
        XCTAssertNotNil(metric.testGetValue(), file: file, line: line)
        XCTAssertEqual(metric.testGetValue(), 1, file: file, line: line)

        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidLabel), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidOverflow), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidState), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidValue), 0, file: file, line: line)
    }

    func testLabeledMetricSuccess(metric: LabeledMetricType<CounterMetricType>,
                                  file: StaticString = #file,
                                  line: UInt = #line) {
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidLabel), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidOverflow), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidState), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidValue), 0, file: file, line: line)
    }

    func testQuantityMetricSuccess(metric: QuantityMetricType,
                                   expectedValue: Int64,
                                   failureMessage: String,
                                   file: StaticString = #file,
                                   line: UInt = #line) {
        XCTAssertNotNil(metric.testGetValue(), "Should have value on quantity metric", file: file, line: line)
        XCTAssertEqual(metric.testGetValue(), expectedValue, failureMessage, file: file, line: line)

        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidLabel), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidOverflow), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidState), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidValue), 0, file: file, line: line)
    }

    func testStringMetricSuccess(metric: StringMetricType,
                                 expectedValue: String,
                                 failureMessage: String,
                                 file: StaticString = #file,
                                 line: UInt = #line) {
        XCTAssertNotNil(metric.testGetValue(), "Should have value on string metric", file: file, line: line)
        XCTAssertEqual(metric.testGetValue(), expectedValue, failureMessage, file: file, line: line)

        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidLabel), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidOverflow), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidState), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidValue), 0, file: file, line: line)
    }

    func testUrlMetricSuccess(metric: UrlMetricType,
                              expectedValue: String,
                              failureMessage: String,
                              file: StaticString = #file,
                              line: UInt = #line) {
        XCTAssertNotNil(metric.testGetValue(), "Should have value on url metric", file: file, line: line)
        XCTAssertEqual(metric.testGetValue(), expectedValue, failureMessage, file: file, line: line)

        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidLabel), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidOverflow), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidState), 0, file: file, line: line)
        XCTAssertEqual(metric.testGetNumRecordedErrors(ErrorType.invalidValue), 0, file: file, line: line)
    }

    func testUuidMetricSuccess(metric: UuidMetricType,
                               expectedValue: UUID,
                               failureMessage: String,
                               file: StaticString = #file,
                               line: UInt = #line) {
        XCTAssertNotNil(metric.testGetValue(), "Should have value on uuid metric", file: file, line: line)
        XCTAssertEqual(metric.testGetValue(), expectedValue, failureMessage, file: file, line: line)
    }
}