// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@testable import Client

import WebKit
import Shared
import XCTest
import Common

class TabDisplayManagerTests: XCTestCase {
    var tabCellIdentifier: TabDisplayer.TabCellIdentifier = TopTabCell.cellIdentifier

    var mockDataStore: WeakListMock<Tab>!
    var dataStore: WeakList<Tab>!
    var collectionView: MockCollectionView!
    var profile: TabManagerMockProfile!
    var manager: TabManager!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        mockDataStore = WeakListMock<Tab>()
        dataStore = WeakList<Tab>()
        profile = TabManagerMockProfile()
        manager = TabManager(profile: profile, imageStore: nil)
        collectionView = MockCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    }

    override func tearDown() {
        super.tearDown()
        AppContainer.shared.reset()
        profile.shutdown()
        manager.testRemoveAll()
        manager.testClearArchive()
        profile = nil
        manager = nil
        collectionView = nil

        dataStore.removeAll()
        mockDataStore.removeAll()
        mockDataStore = nil
        dataStore = nil
    }

    // MARK: Index to place tab

    func testIndexToPlaceTab_countAtZero_placeAtZero() {
        mockDataStore.countToReturn = 0
        let tabDisplayManager = createTabDisplayManager()
        let index = tabDisplayManager.getIndexToPlaceTab(placeNextToParentTab: false)

        XCTAssertEqual(index, 0)
    }

    func testIndexToPlaceTab_countAtOne_placeAtOne() {
        mockDataStore.countToReturn = 1
        let tabDisplayManager = createTabDisplayManager()
        let index = tabDisplayManager.getIndexToPlaceTab(placeNextToParentTab: false)

        XCTAssertEqual(index, 1)
    }

    func testIndexToPlaceTab_countAtTwo_placeAtTwo() {
        mockDataStore.countToReturn = 2
        let tabDisplayManager = createTabDisplayManager()
        let index = tabDisplayManager.getIndexToPlaceTab(placeNextToParentTab: false)

        XCTAssertEqual(index, 2)
    }

    func testIndexToPlaceTab_countAtMinusOne_placeAtZero() {
        mockDataStore.countToReturn = -1
        let tabDisplayManager = createTabDisplayManager()
        let index = tabDisplayManager.getIndexToPlaceTab(placeNextToParentTab: false)

        XCTAssertEqual(index, 0)
    }

    func testIndexToPlaceTab_hasOneTab_newTabAtIndex1() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add one tab
        let selectedTab = manager.addTab()
        manager.selectTab(selectedTab)
        XCTAssertEqual(tabDisplayManager.dataStore.count, 1)

        // Add new tab
        let newTab = manager.addTab()

        XCTAssertEqual(tabDisplayManager.dataStore.count, 2)
        XCTAssertEqual(manager.tabs[1].tabUUID, newTab.tabUUID, "New tab should be placed at last position, at index 1")
        XCTAssertEqual(tabDisplayManager.dataStore.at(1)?.tabUUID, newTab.tabUUID, "New tab should be placed at last position, at index 1")
    }

    func testIndexToPlaceTab_hasThreeTabsLastSelected_newTabAtIndex3() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add three tab
        manager.addTab()
        manager.addTab()
        let selectedTab = manager.addTab()
        manager.selectTab(selectedTab)
        XCTAssertEqual(tabDisplayManager.dataStore.count, 3)

        // Add new tab
        let newTab = manager.addTab()

        XCTAssertEqual(tabDisplayManager.dataStore.count, 4)
        XCTAssertEqual(manager.tabs[3].tabUUID, newTab.tabUUID, "New tab should be placed at last position, at index 3")
        XCTAssertEqual(tabDisplayManager.dataStore.at(3)?.tabUUID, newTab.tabUUID, "New tab should be placed at last position, at index 3")
    }

    func testIndexToPlaceTab_hasThreeTabsFirstSelected_newTabAtIndex3() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add three tab
        manager.addTab()
        manager.addTab()
        let selectedTab = manager.addTab()
        manager.selectTab(selectedTab)
        XCTAssertEqual(tabDisplayManager.dataStore.count, 3)

        // Add new tab
        let newTab = manager.addTab()

        XCTAssertEqual(tabDisplayManager.dataStore.count, 4)
        XCTAssertEqual(manager.tabs[3].tabUUID, newTab.tabUUID, "New tab should be placed at last position, at index 3")
        XCTAssertEqual(tabDisplayManager.dataStore.at(3)?.tabUUID, newTab.tabUUID, "New tab should be placed at last position, at index 3")
    }

    // MARK: Place tab next to parent tab

    func testPlaceNextToParentTab_parentWasLastTab_newTabPlaceIsLast() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add three tabs with parent at last position
        manager.addTab()
        manager.addTab()
        let parentTab = manager.addTab()
        manager.selectTab(parentTab)
        XCTAssertEqual(tabDisplayManager.dataStore.count, 3)

        // Add child tab after parent
        let childTab = manager.addTab(afterTab: parentTab)

        XCTAssertEqual(tabDisplayManager.dataStore.count, 4)
        XCTAssertEqual(manager.tabs[3].tabUUID, childTab.tabUUID, "Child tab should be placed after the parent tab, at index 3")
        XCTAssertEqual(tabDisplayManager.dataStore.at(3)?.tabUUID, childTab.tabUUID, "Child tab should be placed after the parent tab, at index 3")
    }

    func testPlaceNextToParentTab_parentWasNotLastTab_newTabPlaceIsAfterParent() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add three tabs with parent at second position, not last
        manager.addTab()
        let parentTab = manager.addTab()
        manager.addTab()
        manager.selectTab(parentTab)
        XCTAssertEqual(tabDisplayManager.dataStore.count, 3)

        // Add child tab after parent
        let childTab = manager.addTab(afterTab: parentTab)

        XCTAssertEqual(tabDisplayManager.dataStore.count, 4)
        XCTAssertEqual(manager.tabs[2].tabUUID, childTab.tabUUID, "Child tab should be placed after the parent tab, at index 2")
        XCTAssertEqual(tabDisplayManager.dataStore.at(2)?.tabUUID, childTab.tabUUID, "Child tab should be placed after the parent tab, at index 2")
    }

    func testPlaceNextToParentTab_parentWasFirstTab_newTabPlaceIsAfterParent() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add three tabs with parent at first position
        let parentTab = manager.addTab()
        manager.addTab()
        manager.addTab()
        manager.selectTab(parentTab)
        XCTAssertEqual(tabDisplayManager.dataStore.count, 3)

        // Add child tab after parent
        let childTab = manager.addTab(afterTab: parentTab)

        XCTAssertEqual(tabDisplayManager.dataStore.count, 4)
        XCTAssertEqual(manager.tabs[1].tabUUID, childTab.tabUUID, "Child tab should be placed after the parent tab, at index 1")
        XCTAssertEqual(tabDisplayManager.dataStore.at(1)?.tabUUID, childTab.tabUUID, "Child tab should be placed after the parent tab, at index 1")
    }

    // MARK: Selected cell

    func testSelectedCell_lastTabSelectedAndRemoved() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add four tabs with selected at last position
        manager.addTab()
        manager.addTab()
        manager.addTab()
        let selectedTab = manager.addTab()
        manager.selectTab(selectedTab)

        removeTabAndAssert(tab: selectedTab) {
            // Should be selected tab is index 2, and no other one is selected
            self.testSelectedCells(tabDisplayManager: tabDisplayManager, numberOfCells: 3, selectedIndex: 2)
        }
    }

    func testSelectedCell_secondToLastTabSelectedAndRemoved() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add four tabs with selected at second to last position
        manager.addTab()
        manager.addTab()
        let selectedTab = manager.addTab()
        manager.addTab()
        manager.selectTab(selectedTab)

        // Remove selected
        removeTabAndAssert(tab: selectedTab) {
            // Should be selected tab is index 1, and no other one is selected
            self.testSelectedCells(tabDisplayManager: tabDisplayManager, numberOfCells: 3, selectedIndex: 2)
        }
    }

    func testSelectedCell_secondToLastTabSelectedAndTabBeforeRemoved() {
        let tabDisplayManager = createTabDisplayManager(useMockDataStore: false)

        // Add four tabs with selected at second to last position
        manager.addTab()
        let tabToRemove = manager.addTab()
        let selectedTab = manager.addTab()
        manager.addTab()
        manager.selectTab(selectedTab)

        // Remove second tab
        removeTabAndAssert(tab: tabToRemove) {
            // Should be selected tab is index 1, and no other one is selected
            self.testSelectedCells(tabDisplayManager: tabDisplayManager, numberOfCells: 3, selectedIndex: 1)
        }
    }
}

// Helper methods
extension TabDisplayManagerTests {
    func removeTabAndAssert(tab: Tab, completion: @escaping () -> Void) {
        let expectation = self.expectation(description: "Tab is removed")
        manager.removeTab(tab) {
            completion()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func createTabDisplayManager(useMockDataStore: Bool = true) -> TabDisplayManager {
        let tabDisplayManager = TabDisplayManager(collectionView: collectionView,
                                                  tabManager: manager,
                                                  tabDisplayer: self,
                                                  reuseID: TopTabCell.cellIdentifier,
                                                  tabDisplayType: .TopTabTray,
                                                  profile: profile,
                                                  theme: LightTheme())
        collectionView.dataSource = tabDisplayManager
        tabDisplayManager.dataStore = useMockDataStore ? mockDataStore : dataStore
        return tabDisplayManager
    }

    func testSelectedCells(tabDisplayManager: TabDisplayManager, numberOfCells: Int, selectedIndex: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tabDisplayManager.dataStore.count, numberOfCells, file: file, line: line)
        for index in 0..<numberOfCells {
            let cell = tabDisplayManager.collectionView(collectionView, cellForItemAt: IndexPath(row: index, section: 0)) as! TabTrayCell
            if index == selectedIndex {
                XCTAssertTrue(cell.isSelectedTab, file: file, line: line)
            } else {
                XCTAssertFalse(cell.isSelectedTab, file: file, line: line)
            }
        }
    }
}

extension TabDisplayManagerTests: TabDisplayer {
    func focusSelectedTab() {}

    func cellFactory(for cell: UICollectionViewCell, using tab: Tab) -> UICollectionViewCell {
        guard let tabCell = cell as? TabTrayCell else { return UICollectionViewCell() }
        let isSelected = (tab == manager.selectedTab)
        tabCell.configureWith(tab: tab, isSelected: isSelected, theme: LightTheme())
        return tabCell
    }
}

class WeakListMock<T: AnyObject>: WeakList<T> {
    var countToReturn: Int = 0
    override var count: Int {
        return countToReturn
    }

    override var isEmpty: Bool {
        return countToReturn <= 0
    }
}

class MockCollectionView: UICollectionView {
    override init(frame: CGRect, collectionViewLayout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: collectionViewLayout)

        register(TopTabCell.self, forCellWithReuseIdentifier: TopTabCell.cellIdentifier)
        register(InactiveTabCell.self, forCellWithReuseIdentifier: InactiveTabCell.cellIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        updates?()
        completion?(true)
    }

    /// Due to the usage of MockCollectionView with the overridden performBatchUpdates in prod code for those tests, deleteItems needs an extra check.
    /// No check was added for prod code so it would crash in case of concurrency (which would be abnormal and need to be detected)
    override func deleteItems(at indexPaths: [IndexPath]) {
        guard indexPaths[0].row <= numberOfItems(inSection: 0) - 1 else { return }
        super.deleteItems(at: indexPaths)
    }
}
