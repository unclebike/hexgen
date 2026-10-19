// HighScoresTests.swift — Best score per mode, mirroring scoring.js saveHighScore

import Foundation
import XCTest
@testable import DialhexCore

final class HighScoresTests: XCTestCase {
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

    func testStartsAtZero() {
        let scores = HighScores(defaults: defaults)
        for mode in Mode.allCases {
            XCTAssertEqual(scores.best(for: mode), 0)
        }
    }

    func testRecordsOnlyStrictImprovements() {
        // JS: saveHighScore returns true only when score > the stored best
        let scores = HighScores(defaults: defaults)
        XCTAssertFalse(scores.record(0, for: .main))
        XCTAssertTrue(scores.record(1200, for: .main))
        XCTAssertEqual(scores.best(for: .main), 1200)
        XCTAssertFalse(scores.record(1200, for: .main))
        XCTAssertFalse(scores.record(800, for: .main))
        XCTAssertEqual(scores.best(for: .main), 1200)
        XCTAssertTrue(scores.record(1600, for: .main))
        XCTAssertEqual(scores.best(for: .main), 1600)
    }

    func testModesAreIndependent() {
        let scores = HighScores(defaults: defaults)
        XCTAssertTrue(scores.record(500, for: .sprint))
        XCTAssertTrue(scores.record(300, for: .endless))
        XCTAssertEqual(scores.best(for: .main), 0)
        XCTAssertEqual(scores.best(for: .sprint), 500)
        XCTAssertEqual(scores.best(for: .endless), 300)
        XCTAssertTrue(scores.record(100, for: .main))
        XCTAssertEqual(scores.best(for: .sprint), 500)
    }

    func testPersistsAcrossInstances() {
        HighScores(defaults: defaults).record(4200, for: .endless)
        let reloaded = HighScores(defaults: defaults)
        XCTAssertEqual(reloaded.best(for: .endless), 4200)
        XCTAssertFalse(reloaded.record(4000, for: .endless))
    }

    func testCorruptDataReadsAsEmpty() {
        defaults.set(Data("not json".utf8), forKey: "dialhex_highscores")
        let scores = HighScores(defaults: defaults)
        XCTAssertEqual(scores.best(for: .main), 0)
        XCTAssertTrue(scores.record(10, for: .main))
        XCTAssertEqual(scores.best(for: .main), 10)
    }
}
