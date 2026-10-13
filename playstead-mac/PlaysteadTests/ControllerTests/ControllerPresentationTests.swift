import XCTest
import AppKit
import SwiftUI
@testable import Playstead

@MainActor
final class ControllerPresentationTests: XCTestCase {
    func testKnownProfilesUsePhysicalLabelsAndUnknownProfilesStayGeneric() {
        let faceInputs = ["buttonA", "buttonB", "buttonX", "buttonY"]
        for style in [ControllerButtonStyle.dualSense, .dualShock] {
            XCTAssertEqual(faceInputs.map { ControllerInputLabel.displayName(for: $0, style: style) },
                           ["Cross ×", "Circle ○", "Square □", "Triangle △"])
        }
        XCTAssertEqual(faceInputs.map { ControllerInputLabel.displayName(for: $0, style: .xbox) }, ["A", "B", "X", "Y"])
        XCTAssertEqual(faceInputs.map { ControllerInputLabel.displayName(for: $0) },
                       ["Lower face button", "Right face button", "Left face button", "Upper face button"])
        XCTAssertEqual(ControllerInputLabel.displayName(for: "buttonOptions", style: .dualSense), "Create")
        XCTAssertEqual(ControllerInputLabel.displayName(for: "buttonOptions", style: .dualShock), "Share")
        XCTAssertEqual(ControllerInputLabel.displayName(for: "buttonOptions", style: .xbox), "View")
        XCTAssertEqual(ControllerInputLabel.displayName(for: "futureInput", style: .dualSense), "futureInput")
    }

    func testDescriptorPresentationRoundTripsAndLegacyMappingsRemainIdentical() throws {
        let legacy = Data(#"{"id":"pad","name":"DualSense Wireless Controller","availableInputs":["buttonA","buttonB"]}"#.utf8)
        let decoded = try JSONDecoder().decode(ControllerDescriptor.self, from: legacy)
        XCTAssertNil(decoded.buttonStyle, "A display name alone must never select branded presentation")
        let mapping = ControllerMapping.defaultMapping(controllerProductID: "pad")
        let before = try JSONEncoder().encode(mapping)
        let descriptor = ControllerDescriptor(id: "pad", name: "Pad", availableInputs: ControllerDescriptor.extendedInputs, buttonStyle: .dualSense)
        XCTAssertEqual(try JSONDecoder().decode(ControllerDescriptor.self, from: JSONEncoder().encode(descriptor)), descriptor)
        XCTAssertEqual(ControllerMapping.defaultControllerInputs, ControllerDescriptor.defaultInputs)
        XCTAssertEqual(ControllerMapping.defaultControllerInputs.count, 10)
        XCTAssertFalse(ControllerMapping.defaultControllerInputs.contains("buttonX"))
        XCTAssertEqual(try JSONEncoder().encode(mapping), before)
    }

    func testAllFourFaceButtonsUseAssignedLiveStateAndDetachClearsIt() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)
        let pad = ControllerDescriptor(id: "pad", name: "Pad", availableInputs: ControllerDescriptor.extendedInputs, buttonStyle: .dualSense)
        let other = ControllerDescriptor(id: "other", name: "Other", availableInputs: ControllerDescriptor.defaultInputs)
        source.simulateConnect(pad)
        source.simulateConnect(other)
        for input in ["buttonA", "buttonB", "buttonX", "buttonY"] {
            source.simulateInput(controllerID: pad.id, name: input, active: true)
            XCTAssertTrue(host.liveInputs.contains(input))
            source.simulateInput(controllerID: pad.id, name: input, active: false)
            XCTAssertFalse(host.liveInputs.contains(input))
        }
        source.simulateInput(controllerID: other.id, name: "buttonX", active: true)
        source.simulateInput(controllerID: pad.id, name: "unknown", active: true)
        XCTAssertTrue(host.liveInputs.isEmpty)
        source.simulateInput(controllerID: pad.id, name: "buttonY", active: true)
        source.simulateDisconnect(pad)
        XCTAssertTrue(host.liveInputs.isEmpty)
    }

    func testVectorAndTextPresentationRenderBothThemesAndReactToPresses() throws {
        let output = ProcessInfo.processInfo.environment["PLAYSTEAD_CONTROLLER_CAPTURE_ROOT"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for style in [ControllerButtonStyle.dualSense, .xbox, .generic] {
            for scheme in [ColorScheme.light, .dark] {
                let resting = try render(style: style, scheme: scheme, pressed: [])
                let pressed = try render(style: style, scheme: scheme, pressed: ["buttonA", "buttonX", "dpadUp"])
                XCTAssertGreaterThan(resting.count, 1000)
                XCTAssertNotEqual(resting, pressed, "Real view output must change for live input")
                let captureName = "\(style.rawValue)-\(scheme == .dark ? "dark" : "light")"
                for (state, bytes) in [("resting", resting), ("pressed", pressed)] {
                    let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.png")
                    attachment.name = "\(captureName)-\(state)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                if let output {
                    let name = "\(style.rawValue)-\(scheme == .dark ? "dark" : "light")"
                    try resting.write(to: output.appendingPathComponent("\(name)-resting.png"))
                    try pressed.write(to: output.appendingPathComponent("\(name)-pressed.png"))
                }
            }
        }
    }

    private func render(style: ControllerButtonStyle, scheme: ColorScheme, pressed: Set<String>) throws -> Data {
        let view = ControllerTestView(controllerName: "Controller", availableInputs: ControllerDescriptor.extendedInputs, liveInputs: pressed, buttonStyle: style)
            .frame(width: 440, height: 600, alignment: .topLeading)
            .background(DesignTokens.background)
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 600)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
