import TimeTugCore
import XCTest
@testable import TimeTug

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaultsWhenEmpty() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.takeover, TakeoverSettings())
        XCTAssertEqual(store.menuBarMode, .iconOnly)
        XCTAssertEqual(store.appearanceMode, .auto)
    }

    func testPersistsChanges() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.takeover.leadTime = 300
        store.takeover.takeoverCalendarKeys = ["eventkit/work"]
        store.menuBarMode = .countdown
        store.appearanceMode = .dark

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.takeover.leadTime, 300)
        XCTAssertEqual(reloaded.takeover.takeoverCalendarKeys, ["eventkit/work"])
        XCTAssertEqual(reloaded.menuBarMode, .countdown)
        XCTAssertEqual(reloaded.appearanceMode, .dark)
    }

    func testEventKitEnabledDefaultsToTrueAndPersists() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.eventKitEnabled)
        store.eventKitEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).eventKitEnabled)
    }

    func testPopupCardStyleDefault() {
        XCTAssertEqual(SettingsStore(defaults: freshDefaults()).popupCardStyle, PopupCardStyle.defaultStyle)
    }

    func testPopupCardStylePersists() {
        let defaults = freshDefaults()
        SettingsStore(defaults: defaults).popupCardStyle = .solid
        XCTAssertEqual(SettingsStore(defaults: defaults).popupCardStyle, .solid)
        XCTAssertEqual(defaults.string(forKey: "popupCardStyle.v1"), "solid")
    }

    func testPopupCardStyleInvalidFallsBackToDefault() {
        let defaults = freshDefaults()
        defaults.set("bogus", forKey: "popupCardStyle.v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).popupCardStyle, PopupCardStyle.defaultStyle)
    }

    func testPopupCardStyleUnavailableFallsBackToDefault() {
        // Glass is stored but not available before macOS 26.
        let defaults = freshDefaults()
        defaults.set("glass", forKey: "popupCardStyle.v1")
        let style = SettingsStore(defaults: defaults).popupCardStyle
        if PopupCardStyle.available.contains(.glass) { XCTAssertEqual(style, .glass) }
        else { XCTAssertEqual(style, PopupCardStyle.defaultStyle) }
    }

    func testInferenceIsOffByDefaultAndPersists() {
        let defaults = freshDefaults()
        XCTAssertFalse(SettingsStore(defaults: defaults).inferenceEnabled)
        SettingsStore(defaults: defaults).inferenceEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).inferenceEnabled)
        XCTAssertEqual(defaults.object(forKey: "dedupInference.v1") as? Bool, true)
    }

    func testInitSeedsSharedSuiteFromLegacyValues() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "dedupInference.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.inferenceEnabled)
        XCTAssertEqual(store.shared.bool(.useIntelligence), true)
        XCTAssertEqual(store.shared.bool(.skipAllDay), true)
        XCTAssertEqual(store.shared.bool(.enableTug), true)
    }

    func testSharedValuesWinOverSavedValuesOnInit() {
        let defaults = freshDefaults()
        let shared = SharedSettings(defaults: defaults)
        shared.set(false, for: .enableTug)
        shared.set(false, for: .skipAllDay)
        shared.set(true, for: .useIntelligence)
        let store = SettingsStore(defaults: defaults, shared: shared)
        XCTAssertFalse(store.takeover.enabled)
        XCTAssertFalse(store.takeover.skipAllDayEvents)
        XCTAssertTrue(store.inferenceEnabled)
    }

    func testChangesMirrorIntoSharedSuite() {
        let store = SettingsStore(defaults: freshDefaults())
        store.takeover.enabled = false
        store.takeover.skipAllDayEvents = false
        store.inferenceEnabled = true
        XCTAssertEqual(store.shared.bool(.enableTug), false)
        XCTAssertEqual(store.shared.bool(.skipAllDay), false)
        XCTAssertEqual(store.shared.bool(.useIntelligence), true)
    }

    func testReloadFromSharedAppliesExternalChanges() {
        let store = SettingsStore(defaults: freshDefaults())
        store.shared.set(false, for: .enableTug)
        store.shared.set(false, for: .skipAllDay)
        store.shared.set(true, for: .useIntelligence)
        store.reloadFromShared()
        XCTAssertFalse(store.takeover.enabled)
        XCTAssertFalse(store.takeover.skipAllDayEvents)
        XCTAssertTrue(store.inferenceEnabled)
    }

    func testTugIsOnByDefaultAndSeedsTheSharedSuite() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertTrue(store.takeover.enabled)
        XCTAssertEqual(store.shared.bool(.enableTug), true)
        XCTAssertFalse(store.takeover.requireConferenceLink)
        XCTAssertFalse(store.takeover.requireOtherAttendees)
    }

    func testTugOffPersistsAcrossReload() {
        let defaults = freshDefaults()
        SettingsStore(defaults: defaults).takeover.enabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).takeover.enabled)
    }

    func testSavedDisabledFlagFromAnOlderVersionTurnsTugOffAndSeedsTheSuite() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"disabled":true,"skipSoloEvents":true}"#.utf8), forKey: "takeoverSettings.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.takeover.enabled)
        XCTAssertTrue(store.takeover.requireOtherAttendees)
        XCTAssertEqual(store.shared.bool(.enableTug), false)
    }

    func testUnrelatedTakeoverEditDoesNotOverwritePendingExternalTugOff() {
        let store = SettingsStore(defaults: freshDefaults())
        store.shared.set(false, for: .enableTug)
        store.takeover.leadTime = 300
        XCTAssertEqual(store.shared.bool(.enableTug), false)
        store.reloadFromShared()
        XCTAssertFalse(store.takeover.enabled)
    }

    func testUnrelatedTakeoverEditDoesNotOverwritePendingExternalSkipAllDay() {
        let store = SettingsStore(defaults: freshDefaults())
        store.shared.set(false, for: .skipAllDay)
        store.takeover.leadTime = 300
        XCTAssertEqual(store.shared.bool(.skipAllDay), false)
        store.reloadFromShared()
        XCTAssertFalse(store.takeover.skipAllDayEvents)
    }

    func testSameValueInferenceAssignmentDoesNotOverwritePendingExternalChange() {
        let store = SettingsStore(defaults: freshDefaults())
        store.shared.set(true, for: .useIntelligence)
        store.inferenceEnabled = false
        XCTAssertEqual(store.shared.bool(.useIntelligence), true)
        store.reloadFromShared()
        XCTAssertTrue(store.inferenceEnabled)
    }

    func testReloadFromSharedDoesNotWriteBackToSharedSuite() {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = RecordingDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.shared.set(false, for: .enableTug)
        store.shared.set(false, for: .skipAllDay)
        store.shared.set(true, for: .useIntelligence)

        defaults.recorded = []
        defaults.isRecording = true
        store.reloadFromShared()
        defaults.isRecording = false

        XCTAssertFalse(store.takeover.enabled)
        XCTAssertFalse(store.takeover.skipAllDayEvents)
        XCTAssertTrue(store.inferenceEnabled)
        let shared: Set<String> = [
            SharedSettings.Key.enableTug.rawValue,
            SharedSettings.Key.skipAllDay.rawValue,
            SharedSettings.Key.useIntelligence.rawValue,
        ]
        XCTAssertEqual(defaults.recorded.filter { shared.contains($0) }, [])
    }
}

/// Records the keys written after `isRecording` is switched on.
private final class RecordingDefaults: UserDefaults {
    var isRecording = false
    var recorded: [String] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        if isRecording { recorded.append(defaultName) }
        super.set(value, forKey: defaultName)
    }
    override func set(_ value: Bool, forKey defaultName: String) {
        if isRecording { recorded.append(defaultName) }
        super.set(value, forKey: defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        if isRecording { recorded.append(defaultName) }
        super.removeObject(forKey: defaultName)
    }
}
