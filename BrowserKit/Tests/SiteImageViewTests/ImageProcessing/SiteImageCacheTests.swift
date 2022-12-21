// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Kingfisher
import XCTest
@testable import SiteImageView

final class SiteImageCacheTests: XCTestCase {
    private var imageCache: MockDefaultImageCache!

    override func setUp() {
        super.setUp()
        self.imageCache = MockDefaultImageCache()
    }

    override func tearDown() {
        super.tearDown()
        self.imageCache = nil
    }

    // MARK: - Get from cache

    func testGetFromCache_whenError_returnsError() async {
        imageCache.retrievalError = KingfisherError.requestError(reason: .emptyRequest)
        let subject = DefaultSiteImageCache(imageCache: imageCache)
        let domain = ImageDomain(baseDomain: "www.example.com", bundleDomains: [])

        do {
            _ = try await subject.getImageFromCache(domain: domain, type: .favicon)
        } catch let error as SiteImageError {
            XCTAssertEqual(imageCache.capturedRetrievalKey, "www.example.com-favicon")
            XCTAssertEqual("Unable to retrieve image from cache with reason: The request is empty or `nil`.",
                           error.description)
        } catch {
            XCTFail("Should have failed with SiteImageError type")
        }
    }

    func testGetFromCache_whenEmptyImage_returnsError() async {
        let subject = DefaultSiteImageCache(imageCache: imageCache)
        let domain = ImageDomain(baseDomain: "www.example.com", bundleDomains: [])

        do {
            _ = try await subject.getImageFromCache(domain: domain, type: .heroImage)
        } catch let error as SiteImageError {
            XCTAssertEqual(imageCache.capturedRetrievalKey, "www.example.com-heroImage")
            XCTAssertEqual("Unable to retrieve image from cache with reason: Image was nil",
                           error.description)
        } catch {
            XCTFail("Should have failed with SiteImageError type")
        }
    }

    func testGetFromCache_whenImage_returnsSuccess() async {
        let expectedImage = UIImage()
        imageCache.image = expectedImage
        let subject = DefaultSiteImageCache(imageCache: imageCache)
        let domain = ImageDomain(baseDomain: "www.example2.com", bundleDomains: [])

        do {
            let result = try await subject.getImageFromCache(domain: domain, type: .favicon)
            XCTAssertEqual(imageCache.capturedRetrievalKey, "www.example2.com-favicon")
            XCTAssertEqual(expectedImage, result)
        } catch {
            XCTFail("Should have succeeded with image")
        }
    }

    // MARK: - Cache image

    func testCacheImage_whenSuccess_returnsSuccess() async {
        let expectedImage = UIImage()
        let subject = DefaultSiteImageCache(imageCache: imageCache)
        let domain = ImageDomain(baseDomain: "www.firefox.com", bundleDomains: [])

        _ = await subject.cacheImage(image: expectedImage, domain: domain, type: .favicon)
        XCTAssertEqual(imageCache.capturedStorageKey, "www.firefox.com-favicon")
        XCTAssertEqual(imageCache.capturedImage, expectedImage)
    }
}

private class MockDefaultImageCache: DefaultImageCache {
    var image: UIImage?
    var retrievalError: KingfisherError?
    var capturedRetrievalKey: String?
    func retrieveImage(forKey key: String) async throws -> UIImage? {
        capturedRetrievalKey = key
        if let error = retrievalError {
            throw error
        } else {
            return image
        }
    }

    var capturedImage: UIImage?
    var capturedStorageKey: String?
    func store(image: UIImage, forKey key: String) {
        capturedImage = image
        capturedStorageKey = key
    }
}
