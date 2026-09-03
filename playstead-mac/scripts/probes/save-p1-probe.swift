#!/usr/bin/env swift
//
// save-p1-probe.swift — Probe SAVE-P1 (D-02): converts four inferences about
// APFS/mmap save-file behaviour into recorded measurements.
//
// Runs entirely inside a temporary directory it creates and removes. Never
// touches the Playstead Application Support root. Never writes a real `.sav`.
//
// Usage:
//   swift save-p1-probe.swift [--mgba-artifact <path>]
//   swift save-p1-probe.swift --writer-child <sav-path>   (internal, do not call directly)
//
// See .planning/phases/04-persistent-save-continuity/discussion-research/A-capture-trigger-and-loss-window.md
// for the full rationale behind each measurement.

import Foundation
import CoreServices
import CryptoKit

// MARK: - Constants

let artifactBytes = 32768
let mutationRounds = 5
let eventWaitMillisecondsPerRound = 2000
let postDeathPollSeconds = 10.0

// MARK: - Argument parsing

struct Args {
    var mgbaArtifactPath: String? = nil
    var writerChildPath: String? = nil
}

func parseArgs() -> Args {
    var result = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        switch argv[i] {
        case "--mgba-artifact":
            if i + 1 < argv.count {
                result.mgbaArtifactPath = argv[i + 1]
                i += 2
            } else {
                i += 1
            }
        case "--writer-child":
            if i + 1 < argv.count {
                result.writerChildPath = argv[i + 1]
                i += 2
            } else {
                i += 1
            }
        default:
            i += 1
        }
    }
    return result
}

// MARK: - Small helpers

func die(_ message: String) -> Never {
    FileHandle.standardError.write(("save-p1-probe: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func readWholeFile(_ path: String) throws -> Data {
    return try Data(contentsOf: URL(fileURLWithPath: path))
}

func fstatOf(_ fd: Int32) -> stat {
    var st = stat()
    let rc = fstat(fd, &st)
    if rc != 0 {
        die("fstat failed: \(String(cString: strerror(errno)))")
    }
    return st
}

func mtimeNanos(_ st: stat) -> Double {
    #if os(macOS)
    return Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
    #else
    return Double(st.st_mtim.tv_sec) + Double(st.st_mtim.tv_nsec) / 1_000_000_000.0
    #endif
}

// MARK: - Writer-child mode (internal, spawned by the post_death_writeback stage)
//
// Maps the given file MAP_SHARED, mutates it repeatedly WITHOUT calling
// msync, and blocks until killed by the parent (SIGKILL). This deliberately
// leaves dirty pages in the mapping for the kernel pager to (maybe) write
// back after the process dies.

func runWriterChild(path: String) -> Never {
    let fd = open(path, O_RDWR)
    if fd < 0 {
        // Signal failure via a distinct, non-zero exit code the parent can see.
        exit(2)
    }
    guard let mapped = mmap(nil, artifactBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
          mapped != MAP_FAILED else {
        exit(3)
    }
    let buffer = mapped.assumingMemoryBound(to: UInt8.self)

    // Announce readiness to the parent by touching a sentinel byte pattern,
    // then mutate on a short loop without msync until killed.
    var counter: UInt8 = 1
    while true {
        for i in 0..<artifactBytes {
            buffer[i] = counter
        }
        counter = counter &+ 1
        usleep(50_000) // 50ms between mutation rounds
    }
}

// MARK: - Stage 1 + 2: inode_stability + mtime_fidelity (combined rounds)

struct RoundObservation {
    var round: Int
    var stDev: Int64
    var stIno: UInt64
    var mtime: Double
    var digest: String
}

struct InodeStabilityResult {
    var stable: Bool
    var observedPairs: [[String: AnyEncodable]]
}

struct MtimeFidelityResult {
    var mtimeAdvancedOnEveryContentChange: Bool
    var contentChangedWithoutMtimeAdvanceCount: Int
    var mtimeAdvancedWithoutContentChangeCount: Int
}

// A tiny type-erased JSON-encodable wrapper so heterogeneous dictionaries
// (mixing Int64/UInt64/String) can be serialized with JSONSerialization.
struct AnyEncodable {
    let value: Any
    init(_ value: Any) { self.value = value }
}

func runInodeAndMtimeStages(savPath: String) throws -> (InodeStabilityResult, MtimeFidelityResult, [RoundObservation]) {
    let fd = open(savPath, O_RDWR)
    if fd < 0 { throw ProbeError.stage("inode_stability", "open failed: \(String(cString: strerror(errno)))") }
    defer { close(fd) }

    guard let mapped = mmap(nil, artifactBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
          mapped != MAP_FAILED else {
        throw ProbeError.stage("inode_stability", "mmap failed: \(String(cString: strerror(errno)))")
    }
    defer { munmap(mapped, artifactBytes) }
    let buffer = mapped.assumingMemoryBound(to: UInt8.self)

    var observations: [RoundObservation] = []
    let initialStat = fstatOf(fd)
    observations.append(RoundObservation(
        round: 0,
        stDev: Int64(initialStat.st_dev),
        stIno: UInt64(initialStat.st_ino),
        mtime: mtimeNanos(initialStat),
        digest: sha256Hex(try readWholeFile(savPath))
    ))

    for round in 1...mutationRounds {
        // Mutate every byte to a round-distinct value so the digest changes
        // deterministically, then msync to force writeback through the
        // MAP_SHARED mapping.
        let fillByte = UInt8((round * 37) % 256)
        for i in 0..<artifactBytes {
            buffer[i] = fillByte
        }
        let syncRc = msync(mapped, artifactBytes, MS_SYNC)
        if syncRc != 0 {
            throw ProbeError.stage("inode_stability", "msync failed: \(String(cString: strerror(errno)))")
        }
        let st = fstatOf(fd)
        let digest = sha256Hex(try readWholeFile(savPath))
        observations.append(RoundObservation(
            round: round,
            stDev: Int64(st.st_dev),
            stIno: UInt64(st.st_ino),
            mtime: mtimeNanos(st),
            digest: digest
        ))
    }

    // Stage 1: inode_stability
    let firstPair = (observations.first!.stDev, observations.first!.stIno)
    let allStable = observations.allSatisfy { ($0.stDev, $0.stIno) == firstPair }
    let observedPairs: [[String: AnyEncodable]] = observations.map {
        ["round": AnyEncodable($0.round), "st_dev": AnyEncodable($0.stDev), "st_ino": AnyEncodable($0.stIno)]
    }
    let inodeResult = InodeStabilityResult(stable: allStable, observedPairs: observedPairs)

    // Stage 2: mtime_fidelity
    var contentChangedWithoutMtimeAdvance = 0
    var mtimeAdvancedWithoutContentChange = 0
    var everyChangeHadMtimeAdvance = true
    for idx in 1..<observations.count {
        let prev = observations[idx - 1]
        let curr = observations[idx]
        let contentChanged = curr.digest != prev.digest
        let mtimeAdvanced = curr.mtime > prev.mtime
        if contentChanged && !mtimeAdvanced {
            contentChangedWithoutMtimeAdvance += 1
            everyChangeHadMtimeAdvance = false
        }
        if mtimeAdvanced && !contentChanged {
            mtimeAdvancedWithoutContentChange += 1
        }
    }
    let mtimeResult = MtimeFidelityResult(
        mtimeAdvancedOnEveryContentChange: everyChangeHadMtimeAdvance,
        contentChangedWithoutMtimeAdvanceCount: contentChangedWithoutMtimeAdvance,
        mtimeAdvancedWithoutContentChangeCount: mtimeAdvancedWithoutContentChange
    )

    return (inodeResult, mtimeResult, observations)
}

// MARK: - Stage 3: event_delivery
//
// Registers both an FSEventStream on the temp directory and a
// DispatchSource vnode source on the open descriptor, then performs the
// same mutation rounds through the MAP_SHARED mapping with no write(2) call
// at all, recording whether either mechanism observes the mutation.

final class EventCounters {
    var fsEvents = 0
    var vnodeEvents = 0
    let lock = NSLock()

    func bumpFSEvents(by n: Int) {
        lock.lock(); fsEvents += n; lock.unlock()
    }
    func bumpVnode() {
        lock.lock(); vnodeEvents += 1; lock.unlock()
    }
    func snapshot() -> (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        return (fsEvents, vnodeEvents)
    }
}

func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let counters = Unmanaged<EventCounters>.fromOpaque(info).takeUnretainedValue()
    counters.bumpFSEvents(by: numEvents)
}

struct EventDeliveryResult {
    var fsEventsEventsReceived: Int
    var vnodeEventsReceived: Int
    var perRound: [[String: AnyEncodable]]
}

func runEventDeliveryStage(savPath: String, tempDir: String) throws -> EventDeliveryResult {
    let counters = EventCounters()

    // FSEventStream on the temp directory.
    let unmanagedCounters = Unmanaged.passUnretained(counters).toOpaque()
    var context = FSEventStreamContext(
        version: 0,
        info: unmanagedCounters,
        retain: nil,
        release: nil,
        copyDescription: nil
    )
    let pathsToWatch = [tempDir] as CFArray
    guard let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        fsEventsCallback,
        &context,
        pathsToWatch,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.0,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
    ) else {
        throw ProbeError.stage("event_delivery", "FSEventStreamCreate failed")
    }
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
    defer {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    // DispatchSource vnode watch on the open .sav descriptor.
    let fd = open(savPath, O_RDWR)
    if fd < 0 { throw ProbeError.stage("event_delivery", "open failed: \(String(cString: strerror(errno)))") }
    defer { close(fd) }

    let vnodeSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .extend, .attrib],
        queue: DispatchQueue.main
    )
    vnodeSource.setEventHandler {
        counters.bumpVnode()
    }
    vnodeSource.resume()
    defer { vnodeSource.cancel() }

    guard let mapped = mmap(nil, artifactBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
          mapped != MAP_FAILED else {
        throw ProbeError.stage("event_delivery", "mmap failed: \(String(cString: strerror(errno)))")
    }
    defer { munmap(mapped, artifactBytes) }
    let buffer = mapped.assumingMemoryBound(to: UInt8.self)

    var perRound: [[String: AnyEncodable]] = []

    for round in 1...mutationRounds {
        let (fsBefore, vnodeBefore) = counters.snapshot()
        let fillByte = UInt8((round * 61) % 256)
        for i in 0..<artifactBytes {
            buffer[i] = fillByte
        }
        _ = msync(mapped, artifactBytes, MS_SYNC)

        let deadline = Date().addingTimeInterval(Double(eventWaitMillisecondsPerRound) / 1000.0)
        var observedWithinMs: Int? = nil
        let start = Date()
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            let (fsNow, vnodeNow) = counters.snapshot()
            if fsNow > fsBefore || vnodeNow > vnodeBefore {
                observedWithinMs = Int(Date().timeIntervalSince(start) * 1000)
                break
            }
        }

        perRound.append([
            "round": AnyEncodable(round),
            "event_observed_within_ms": AnyEncodable(observedWithinMs as Any)
        ])
    }

    let (finalFS, finalVnode) = counters.snapshot()
    return EventDeliveryResult(
        fsEventsEventsReceived: finalFS,
        vnodeEventsReceived: finalVnode,
        perRound: perRound
    )
}

// MARK: - Stage 4: post_death_writeback
//
// Forks a child (by re-invoking this same script with --writer-child) that
// maps the file MAP_SHARED, mutates it without msync, and is then killed
// with SIGKILL from the parent. The parent then polls the file's digest for
// up to 10s and records whether the digest changed after the child died.

struct PostDeathWritebackResult {
    var digestChangedAfterProcessDeath: Bool
    var observedDelayMs: Int?
}

func runPostDeathWritebackStage(savPath: String, scriptPath: String) throws -> PostDeathWritebackResult {
    let digestBeforeChild = sha256Hex(try readWholeFile(savPath))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = [scriptPath, "--writer-child", savPath]
    let devNull = FileHandle.nullDevice
    process.standardOutput = devNull
    process.standardError = devNull

    try process.run()

    // Give the child a bounded window to actually map and start mutating
    // before we kill it, otherwise we might kill it before any dirty page
    // exists at all.
    var digestChangedWhileAlive = false
    let aliveDeadline = Date().addingTimeInterval(3.0)
    var lastDigest = digestBeforeChild
    while Date() < aliveDeadline {
        usleep(100_000)
        if let data = try? readWholeFile(savPath) {
            let d = sha256Hex(data)
            if d != digestBeforeChild {
                digestChangedWhileAlive = true
                lastDigest = d
                break
            }
        }
    }

    process.terminate() // best-effort; escalate to SIGKILL below regardless
    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()

    let digestAtDeath = (try? readWholeFile(savPath)).map(sha256Hex) ?? lastDigest

    let pollDeadline = Date().addingTimeInterval(postDeathPollSeconds)
    let pollStart = Date()
    var changedAfterDeath = false
    var observedDelayMs: Int? = nil
    while Date() < pollDeadline {
        usleep(50_000)
        if let data = try? readWholeFile(savPath) {
            let d = sha256Hex(data)
            if d != digestAtDeath {
                changedAfterDeath = true
                observedDelayMs = Int(Date().timeIntervalSince(pollStart) * 1000)
                break
            }
        }
    }

    _ = digestChangedWhileAlive // recorded implicitly via digestAtDeath capture; kept for clarity/debuggability
    return PostDeathWritebackResult(
        digestChangedAfterProcessDeath: changedAfterDeath,
        observedDelayMs: observedDelayMs
    )
}

// MARK: - Errors

enum ProbeError: Error, CustomStringConvertible {
    case stage(String, String)

    var description: String {
        switch self {
        case .stage(let name, let message):
            return "stage \(name) failed: \(message)"
        }
    }
}

// MARK: - Environment block

func filesystemType(ofDirectory path: String) -> String {
    var fs = statfs()
    let rc = statfs(path, &fs)
    if rc != 0 {
        return "unknown"
    }
    return withUnsafeBytes(of: &fs.f_fstypename) { raw -> String in
        let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
        return String(cString: ptr)
    }
}

func macOSVersionString() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

func hardwareModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    if size == 0 { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    let rc = sysctlbyname("hw.model", &buffer, &size, nil, 0)
    if rc != 0 { return "unknown" }
    return String(cString: buffer)
}

func pageSize() -> Int {
    return Int(getpagesize())
}

// MARK: - Optional read-only mGBA artifact observation
//
// When --mgba-artifact is supplied, runs the inode_stability and
// mtime_fidelity stages as a READ-ONLY observer against that live artifact
// (opened O_RDONLY, never mutated) instead of the synthetic writer.

func runMgbaObserverStage(artifactPath: String) throws -> (InodeStabilityResult, MtimeFidelityResult) {
    let fd = open(artifactPath, O_RDONLY)
    if fd < 0 {
        throw ProbeError.stage("mgba_observer", "open (read-only) failed: \(String(cString: strerror(errno)))")
    }
    defer { close(fd) }

    var observations: [RoundObservation] = []
    for round in 0...mutationRounds {
        let st = fstatOf(fd)
        let digest = sha256Hex(try readWholeFile(artifactPath))
        observations.append(RoundObservation(
            round: round,
            stDev: Int64(st.st_dev),
            stIno: UInt64(st.st_ino),
            mtime: mtimeNanos(st),
            digest: digest
        ))
        if round < mutationRounds {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    let firstPair = (observations.first!.stDev, observations.first!.stIno)
    let allStable = observations.allSatisfy { ($0.stDev, $0.stIno) == firstPair }
    let observedPairs: [[String: AnyEncodable]] = observations.map {
        ["round": AnyEncodable($0.round), "st_dev": AnyEncodable($0.stDev), "st_ino": AnyEncodable($0.stIno)]
    }
    let inodeResult = InodeStabilityResult(stable: allStable, observedPairs: observedPairs)

    var contentChangedWithoutMtimeAdvance = 0
    var mtimeAdvancedWithoutContentChange = 0
    var everyChangeHadMtimeAdvance = true
    for idx in 1..<observations.count {
        let prev = observations[idx - 1]
        let curr = observations[idx]
        let contentChanged = curr.digest != prev.digest
        let mtimeAdvanced = curr.mtime > prev.mtime
        if contentChanged && !mtimeAdvanced {
            contentChangedWithoutMtimeAdvance += 1
            everyChangeHadMtimeAdvance = false
        }
        if mtimeAdvanced && !contentChanged {
            mtimeAdvancedWithoutContentChange += 1
        }
    }
    let mtimeResult = MtimeFidelityResult(
        mtimeAdvancedOnEveryContentChange: everyChangeHadMtimeAdvance,
        contentChangedWithoutMtimeAdvanceCount: contentChangedWithoutMtimeAdvance,
        mtimeAdvancedWithoutContentChangeCount: mtimeAdvancedWithoutContentChange
    )
    return (inodeResult, mtimeResult)
}

// MARK: - JSON assembly

func toJSONValue(_ any: Any) -> Any {
    if let wrapped = any as? AnyEncodable {
        return toJSONValue(wrapped.value)
    }
    if let optionalInt = any as? Int? {
        if let v = optionalInt { return v }
        return NSNull()
    }
    if let dict = any as? [String: AnyEncodable] {
        var out: [String: Any] = [:]
        for (k, v) in dict { out[k] = toJSONValue(v) }
        return out
    }
    if let arr = any as? [[String: AnyEncodable]] {
        return arr.map { toJSONValue($0) }
    }
    return any
}

func buildReport(
    runId: String,
    recordedAt: String,
    envFilesystemType: String,
    envArtifactBytes: Int,
    envPageSize: Int,
    envOSVersion: String,
    envHardwareModel: String,
    mgbaObserved: Bool,
    inode: InodeStabilityResult,
    mtime: MtimeFidelityResult,
    events: EventDeliveryResult,
    postDeath: PostDeathWritebackResult,
    conclusions: [String]
) -> [String: Any] {
    let environment: [String: Any] = [
        "os_version": envOSVersion,
        "hardware_model": envHardwareModel,
        "filesystem_type": envFilesystemType,
        "page_size": envPageSize,
        "artifact_bytes": envArtifactBytes
    ]

    let inodeMeasurement: [String: Any] = [
        "stable": inode.stable,
        "observed_pairs": inode.observedPairs.map { toJSONValue($0) }
    ]

    let mtimeMeasurement: [String: Any] = [
        "mtime_advanced_on_every_content_change": mtime.mtimeAdvancedOnEveryContentChange,
        "content_changed_without_mtime_advance_count": mtime.contentChangedWithoutMtimeAdvanceCount,
        "mtime_advanced_without_content_change_count": mtime.mtimeAdvancedWithoutContentChangeCount
    ]

    let eventMeasurement: [String: Any] = [
        "fsevents_events_received": events.fsEventsEventsReceived,
        "vnode_events_received": events.vnodeEventsReceived,
        "per_round": events.perRound.map { toJSONValue($0) }
    ]

    let postDeathMeasurement: [String: Any] = [
        "digest_changed_after_process_death": postDeath.digestChangedAfterProcessDeath,
        "observed_delay_ms": postDeath.observedDelayMs as Any
    ]

    let measurements: [String: Any] = [
        "inode_stability": inodeMeasurement,
        "mtime_fidelity": mtimeMeasurement,
        "event_delivery": eventMeasurement,
        "post_death_writeback": postDeathMeasurement
    ]

    return [
        "probe_id": "SAVE-P1",
        "run_id": runId,
        "recorded_at": recordedAt,
        "environment": environment,
        "mgba_observed": mgbaObserved,
        "measurements": measurements,
        "conclusions": conclusions
    ]
}

func emitJSON(_ report: [String: Any]) {
    // JSONSerialization does not accept top-level NSNull inside nested dicts
    // containing Optional<Int> unless properly boxed; the report above only
    // uses NSNull/Int/Bool/String/Array/Dictionary, which are all valid.
    guard JSONSerialization.isValidJSONObject(report) else {
        die("assembled report is not valid JSON — this is a probe bug")
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        die("failed to serialize report: \(error)")
    }
}

// MARK: - Main

let args = parseArgs()

if let writerChildPath = args.writerChildPath {
    runWriterChild(path: writerChildPath)
}

let scriptPath = CommandLine.arguments[0]

let tempRoot = NSTemporaryDirectory()
let probeDirName = "save-p1-probe-\(UUID().uuidString)"
let probeDir = (tempRoot as NSString).appendingPathComponent(probeDirName)

do {
    try FileManager.default.createDirectory(atPath: probeDir, withIntermediateDirectories: true)
} catch {
    die("failed to create temp probe directory: \(error)")
}

var exitStatus: Int32 = 0
var conclusions: [String] = []

func cleanupProbeDir() {
    try? FileManager.default.removeItem(atPath: probeDir)
}

let savPath = (probeDir as NSString).appendingPathComponent("probe.sav")

do {
    // Seed the artifact with deterministic non-zero bytes so the very first
    // digest is not the trivial all-zero digest.
    var seed = Data(count: artifactBytes)
    for i in 0..<artifactBytes { seed[i] = UInt8(i % 256) }
    try seed.write(to: URL(fileURLWithPath: savPath))

    let (inodeResult, mtimeResult, _) = try runInodeAndMtimeStages(savPath: savPath)
    conclusions.append(
        inodeResult.stable
            ? "inode_stability: st_dev/st_ino held identical across \(mutationRounds) msync rounds — mGBA-style in-place mmap writers do not rotate inode identity on APFS."
            : "inode_stability: st_dev/st_ino CHANGED across msync rounds — an in-place-write assumption would be wrong on this host."
    )
    conclusions.append(
        mtimeResult.mtimeAdvancedOnEveryContentChange
            ? "mtime_fidelity: st_mtimespec advanced on every observed content change — mtime is a faithful (but still unused) proxy on this host."
            : "mtime_fidelity: st_mtimespec did NOT advance on \(mtimeResult.contentChangedWithoutMtimeAdvanceCount) content change(s) — confirms mtime heuristics are unsafe, exactly as D-01/D-03 already assume."
    )

    let eventResult = try runEventDeliveryStage(savPath: savPath, tempDir: probeDir)
    let anyEventsObserved = eventResult.fsEventsEventsReceived > 0 || eventResult.vnodeEventsReceived > 0
    conclusions.append(
        anyEventsObserved
            ? "event_delivery: FSEvents and/or vnode sources DID fire for mmap/msync writes on this host (fsevents=\(eventResult.fsEventsEventsReceived), vnode=\(eventResult.vnodeEventsReceived)) — an event accelerant is available, though D-01's poll remains the ground truth per the phase decision."
            : "event_delivery: neither FSEvents nor the vnode DispatchSource observed any of \(mutationRounds) mmap/msync mutation rounds — this is the documented justification for polling rather than folklore."
    )

    let postDeathResult = try runPostDeathWritebackStage(savPath: savPath, scriptPath: scriptPath)
    conclusions.append(
        postDeathResult.digestChangedAfterProcessDeath
            ? "post_death_writeback: dirty MAP_SHARED pages DID land on disk after the writer process was SIGKILLed (delay ~\(postDeathResult.observedDelayMs ?? -1)ms) — confirms the post-exit settle pass must be unconditional (D-05)."
            : "post_death_writeback: no additional writeback was observed in the \(Int(postDeathPollSeconds))s window after SIGKILL on this host — does not change D-05, which stays unconditional regardless."
    )

    var mgbaObserved = false
    if let mgbaPath = args.mgbaArtifactPath {
        _ = try runMgbaObserverStage(artifactPath: mgbaPath)
        mgbaObserved = true
        conclusions.append("mgba_observed: true — a live adapter-declared artifact at \(mgbaPath) was additionally observed read-only.")
    } else {
        conclusions.append("mgba_observed: false — no --mgba-artifact was supplied; the real-emulator confirmation is carried by CP7-SAVE-C (plan 04-12), never inferred here.")
    }

    let report = buildReport(
        runId: UUID().uuidString,
        recordedAt: ISO8601DateFormatter().string(from: Date()),
        envFilesystemType: filesystemType(ofDirectory: probeDir),
        envArtifactBytes: artifactBytes,
        envPageSize: pageSize(),
        envOSVersion: macOSVersionString(),
        envHardwareModel: hardwareModel(),
        mgbaObserved: mgbaObserved,
        inode: inodeResult,
        mtime: mtimeResult,
        events: eventResult,
        postDeath: postDeathResult,
        conclusions: conclusions
    )

    emitJSON(report)
} catch {
    FileHandle.standardError.write("save-p1-probe: \(error)\n".data(using: .utf8)!)
    exitStatus = 1
}

cleanupProbeDir()
exit(exitStatus)
