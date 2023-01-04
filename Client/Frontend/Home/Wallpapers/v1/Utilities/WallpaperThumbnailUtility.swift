// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
import Common

class WallpaperThumbnailUtility: Loggable {
    // MARK: - Properties

    /// The mininmum number of thumbnails we require to show the onboarding or
    /// the wallpaper settings. Includes the default wallpaper.
    private let requiredThumbs = 4

    public var areThumbnailsAvailable: Bool {
        return userDefaults.bool(forKey: prefsKey)
    }

    private var userDefaults: UserDefaultsInterface
    private var networkingModule: WallpaperNetworking
    private let prefsKey = PrefsKeys.Wallpapers.ThumbnailsAvailable

    // MARK: - Initializers
    init(
        with networkingModule: WallpaperNetworking,
        and userDefaults: UserDefaultsInterface = UserDefaults.standard
    ) {
        self.networkingModule = networkingModule
        self.userDefaults = userDefaults
    }

    // MARK: - Public interface
    public func getListOfMissingTumbnails(from collections: [WallpaperCollection]) -> [String: String] {
        var missingThumbnails: [String: String] = [:]

        collections.forEach { collection in
            collection.wallpapers.forEach { wallpaper in
                if wallpaper.type != .defaultWallpaper && wallpaper.thumbnail == nil {
                    missingThumbnails[wallpaper.id] = wallpaper.thumbnailID
                }
            }
        }

        return missingThumbnails
    }

    public func fetchAndVerifyThumbnails(for collections: [WallpaperCollection]) async {
        do {
            userDefaults.set(false, forKey: prefsKey)
            try await fetchMissingThumbnails(from: collections)
            verifyThumbnailsFor(collections)
        } catch {
            browserLog.error("Wallpaper thumbnail update error: \(error.localizedDescription)")
        }
    }

    private func fetchMissingThumbnails(from collections: [WallpaperCollection]) async throws {
        let dataService = WallpaperDataService(with: networkingModule)
        let storageUtility = WallpaperStorageUtility()

        let missingThumbnails = getListOfMissingTumbnails(from: collections)
        if !missingThumbnails.isEmpty {
            for (key, fileName) in missingThumbnails {
                guard let thumbnail = try? await dataService.getImage(
                    named: fileName,
                    withFolderName: key)
                else { break }

                try storageUtility.store(thumbnail, withName: fileName, andKey: key)
            }
        }
    }

    private func verifyThumbnailsFor(_ collections: [WallpaperCollection]) {
        var numberOfAvailableThumbs = 0

        collections.forEach { collection in
            collection.wallpapers.forEach { wallpaper in
                if wallpaper.type == .defaultWallpaper || wallpaper.thumbnail != nil {
                    numberOfAvailableThumbs += 1
                }
            }
        }

        if numberOfAvailableThumbs >= requiredThumbs {
            userDefaults.set(true, forKey: prefsKey)
        }
    }
}
