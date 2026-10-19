// SkinUnlocksTests.swift — Skin unlocks, mirroring skins.js unlockedCount/recordProgress

import Foundation
import XCTest
@testable import DialhexCore

final class SkinUnlocksTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DialhexCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func unlocks() -> SkinUnlocks {
        SkinUnlocks(skinCount: 6, milestones: [50, 150, 300, 600, 1000], defaults: defaults)
    }

    func testFirstSkinIsAlwaysOpen() {
        XCTAssertEqual(unlocks().unlockedCount, 1)
    }

    func testMilestonesOpenSkinsInOrder() {
        let u = unlocks()
        XCTAssertEqual(u.record(hexes: 49, mainWin: false), 1..<1)
        XCTAssertEqual(u.record(hexes: 1, mainWin: false), 1..<2)
        // One long game can pass two milestones at once
        XCTAssertEqual(u.record(hexes: 250, mainWin: false), 2..<4)
        XCTAssertEqual(u.progress.hexes, 300)
    }

    func testMainWinOpensASkin() {
        let u = unlocks()
        XCTAssertEqual(u.record(hexes: 48, mainWin: true), 1..<2)
        XCTAssertEqual(u.record(hexes: 48, mainWin: true), 2..<4) // second win and the 50-hex milestone
    }

    func testNeverOpensMoreThanThereAre() {
        let u = unlocks()
        u.record(hexes: 5000, mainWin: true)
        u.record(hexes: 0, mainWin: true)
        XCTAssertEqual(u.unlockedCount, 6)
        XCTAssertTrue(u.record(hexes: 10, mainWin: true).isEmpty)
    }

    func testPersistsAndSharesTheWebKey() throws {
        unlocks().record(hexes: 160, mainWin: true)
        XCTAssertEqual(unlocks().progress, SkinUnlocks.Progress(mainWins: 1, hexes: 160))
        let json = try XCTUnwrap(defaults.data(forKey: "dialhex_progress"))
        let decoded = try JSONSerialization.jsonObject(with: json) as? [String: Int]
        XCTAssertEqual(decoded, ["mainWins": 1, "hexes": 160])
    }

    func testUnlockAllOpensEverythingAndKeepsProgress() {
        let u = unlocks()
        u.record(hexes: 2000, mainWin: true)
        u.unlockAll()
        XCTAssertEqual(u.unlockedCount, 6)
        XCTAssertEqual(u.progress, SkinUnlocks.Progress(mainWins: 1, hexes: 2000))

        // More skins than milestones: the shortfall is made up with wins
        let more = SkinUnlocks(skinCount: 8, milestones: [50, 150], defaults: defaults)
        more.unlockAll()
        XCTAssertEqual(more.unlockedCount, 8)
    }

    func testCorruptDataStartsOver() {
        defaults.set(Data("nope".utf8), forKey: "dialhex_progress")
        XCTAssertEqual(unlocks().unlockedCount, 1)
    }
}
