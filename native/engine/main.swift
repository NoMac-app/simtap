// simulator-use engine (prototype): one process per booted Simulator that loads CoreSimulator's
// private frameworks, the HID connection and the accessibility translator once, then answers JSON
// requests, one per line on stdin, one JSON answer per line on stdout. Built on AXe's
// FBSimulatorControl frameworks (MIT).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FBControlCore
import FBSimulatorControl

let started = Date()
func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }
func emit(_ object: [String: Any]) {
  let data = try! JSONSerialization.data(withJSONObject: object)
  FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([0x0A]))
}
struct EngineError: Error { let message: String }

let args = CommandLine.arguments
guard let udidIndex = args.firstIndex(of: "--udid"), udidIndex + 1 < args.count else { emit(["ok": false, "error": "usage: engine --udid UDID"]); exit(2) }
let udid = args[udidIndex + 1]
/** A session's own device set (a folder on its volume); the user's default set when absent. */
let deviceSetPath: String? = args.firstIndex(of: "--set").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
FBControlCoreGlobalConfiguration.defaultLogger = logger

// Custom actions are left out unless asked for (keys): simulator-use never shows them, and on a web page a read with
// them took about 2 s in one run (0.1 s in another) against 60 to 400 ms without.
let outputKeys: Set<FBAXKeys> = [.label, .frame, .value, .uniqueID, .type, .title, .frameDict, .help, .enabled, .role, .roleDescription, .subrole, .contentRequired, .pid]

func keyNamed(_ name: String) -> FBAXKeys? {
  switch name {
  case "label": return .label; case "frame": return .frame; case "value": return .value; case "uniqueID": return .uniqueID
  case "type": return .type; case "title": return .title; case "frameDict": return .frameDict; case "help": return .help
  case "enabled": return .enabled; case "customActions": return .customActions; case "role": return .role
  case "roleDescription": return .roleDescription; case "subrole": return .subrole; case "contentRequired": return .contentRequired; case "pid": return .pid
  default: return nil
  }
}
var lastCPU: Double = 0
func cpuMs() -> Int {
  var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
  let now = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
  defer { lastCPU = now }; return Int(now - lastCPU)
}
/** The last tree any read returned, to tell a screen that moved but did not change yet (an app still opening). */
var lastTreeSignature = 0
var lastFrontPid = -1
/** How long each accessibility read of the last readFrontmost took, in ms (the describe answer carries it). */
var lastSerializeMs: [Int] = []
/** What the screen shows, not how it is drawn: kinds, labels and ids (a pressed icon or a moving frame is the same screen). */
func signature(_ tree: Any) -> Int {
  var hasher = Hasher()
  func walk(_ node: Any) {
    if let list = node as? [Any] { list.forEach(walk); return }
    guard let n = node as? [String: Any] else { return }
    hasher.combine(n["type"] as? String); hasher.combine(n["AXLabel"] as? String); hasher.combine(n["AXUniqueId"] as? String)
    (n["children"] as? [Any])?.forEach(walk)
  }
  walk(tree); return hasher.finalize()
}
func isEmptyApp(_ tree: Any) -> Bool {
  let roots = (tree as? [[String: Any]]) ?? []
  return roots.isEmpty || !roots.contains { (($0["children"] as? [Any])?.count ?? 0) > 0 }
}
func withDefaults(_ any: Any) -> Any {
  if let list = any as? [Any] { return list.map(withDefaults) }
  guard var element = any as? [String: Any] else { return any }
  for (key, value) in element { element[key] = withDefaults(value) }
  if element["type"] != nil, element["traits"] == nil { element["traits"] = [String]() }
  return element
}

func jpeg(fromPNG data: Data, maxPoints: (Double, Double)?, quality: Double) throws -> Data {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw EngineError(message: "screenshot could not be decoded") }
  var out = image
  if let (w, h) = maxPoints, w > 0, h > 0, let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    if let scaled = ctx.makeImage() { out = scaled }
  }
  let result = NSMutableData()
  guard let dest = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { throw EngineError(message: "jpeg encoder unavailable") }
  CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
  guard CGImageDestinationFinalize(dest) else { throw EngineError(message: "jpeg encoding failed") }
  return result as Data
}

/** Counts the Simulator's screen updates: "settled" means no update for a quiet period. */
final class DamageWatcher: NSObject, FBFramebufferConsumer, @unchecked Sendable {
  private let lock = NSLock(); private var lastUpdate = Date(); private var updates = 0
  var surface: IOSurface?; private var lastSeed: UInt32 = 0
  func didChange(_ surface: IOSurface?) { lock.lock(); if let surface { self.surface = surface }; lock.unlock(); mark() }
  func didReceiveDamageRect() { mark() }
  private func mark() { lock.lock(); lastUpdate = Date(); updates += 1; lock.unlock() }
  /** The surface's seed changes whenever its contents do: a free check, unlike a screenshot. */
  func pollSeed() { lock.lock(); defer { lock.unlock() }
    guard let surface else { return }
    let seed = IOSurfaceGetSeed(unsafeBitCast(surface, to: IOSurfaceRef.self))
    if seed != lastSeed { lastSeed = seed; lastUpdate = Date(); updates += 1 } }
  func snapshot() -> (Date, Int) { lock.lock(); defer { lock.unlock() }; return (lastUpdate, updates) }
}
/** Waits until the screen has not changed for quietMs (or timeoutMs passes); returns waited ms, updates seen and whether it settled. */
func settle(_ watcher: DamageWatcher, quietMs: Double, timeoutMs: Double, firstChangeMs: Double = 0) async -> (Int, Int, Bool) {
  let start = Date(); watcher.pollSeed(); let (_, before) = watcher.snapshot()
  // After an input iOS may start its animation a few hundred ms later: wait for the first change first.
  if firstChangeMs > 0 {
    while Date().timeIntervalSince(start) * 1000 < firstChangeMs {
      try? await Task.sleep(nanoseconds: 15_000_000); watcher.pollSeed()
      if watcher.snapshot().1 != before { break }
    }
    if watcher.snapshot().1 == before { return (ms(start), 0, true) }
  }
  while true {
    try? await Task.sleep(nanoseconds: 15_000_000)
    watcher.pollSeed()
    let (last, count) = watcher.snapshot()
    let quietFor = Date().timeIntervalSince(max(last, start)) * 1000
    if quietFor >= quietMs { return (ms(start), count - before, true) }
    if Date().timeIntervalSince(start) * 1000 >= timeoutMs { return (ms(start), count - before, false) }
  }
}
final class StreamCounter: @unchecked Sendable {
  let start: Date; var bytes = 0, chunks = 0, first = -1
  init(start: Date) { self.start = start }
  func add(_ n: Int) { bytes += n; chunks += 1; if first < 0 { first = ms(start) } }
}
func blocking(_ work: @escaping @Sendable () throws -> Void) async throws {
  try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
    DispatchQueue.global().async { do { try work(); cont.resume() } catch { cont.resume(throwing: error) } }
  }
}
/**
 FBSimulatorControl bootstraps accessibility (a short-lived XCTest remote automation session) before every
 accessibility request on iOS 27 runtimes. A per-call CLI needs that; a long-lived engine needs it once per
 phone: repeated sessions pile up in the phone's testmanagerd, slow every read and finally time out.
 This replaces the class method with one that runs the original once and then reports success.
 */
/**
 iOS 27 Simulators read accessibility only while an XCTest "remote automation session" has loaded it, and an
 app launched afterwards is unreadable until it is loaded again. FBSimulatorControl opens a session, loads
 accessibility and closes the session before every request; in a long-lived process new sessions soon time out.
 The engine instead opens one session per phone, keeps it for its whole life, and reloads accessibility on that
 same session when the frontmost app reads empty (forceBootstrap). The framework's per-request bootstrap is
 replaced by this.
 */
var bootstrapCount = 0
var signalSources: [DispatchSourceSignal] = []
var forceBootstrap = false
var automationSession: AnyObject?
var skipBootstrap = CommandLine.arguments.contains("--no-bootstrap")
func objcCall(_ target: AnyObject, _ name: String) -> IMP? {
  let sel = NSSelectorFromString(name)
  if let cls = target as? AnyClass { return class_getMethodImplementation(object_getClass(cls), sel) }
  return class_getMethodImplementation(object_getClass(target), sel)
}
func openSession(device: AnyObject, timeout: Double) -> (AnyObject?, String?) {
  guard let providerClass: AnyClass = NSClassFromString("XCUIDeviceRemoteDaemonConnectionProvider"),
        let sessionClass: AnyClass = NSClassFromString("XCUIDeviceRemoteAutomationSession") else { return (nil, "XCTest automation classes unavailable") }
  typealias ProviderFn = @convention(c) (AnyClass, Selector, AnyObject) -> Unmanaged<AnyObject>?
  let provider = unsafeBitCast(objcCall(providerClass, "connectionProviderForSimDevice:"), to: ProviderFn.self)(providerClass, NSSelectorFromString("connectionProviderForSimDevice:"), device)?.takeUnretainedValue()
  guard let provider else { return (nil, "no daemon connection provider") }
  let done = DispatchSemaphore(value: 0); var session: AnyObject?; var failure: String?
  let completion: @convention(block) (AnyObject?, NSError?) -> Void = { s, e in session = s; failure = e?.localizedDescription; done.signal() }
  typealias RequestFn = @convention(c) (AnyClass, Selector, AnyObject, AnyObject) -> Void
  unsafeBitCast(objcCall(sessionClass, "requestSessionWithDaemonConnectionProvider:completion:"), to: RequestFn.self)(sessionClass, NSSelectorFromString("requestSessionWithDaemonConnectionProvider:completion:"), provider, completion as AnyObject)
  if done.wait(timeout: .now() + timeout) == .timedOut { return (nil, "timed out creating the remote automation session") }
  guard let session else { return (nil, failure ?? "no session") }
  typealias EnableFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
  if session.responds(to: NSSelectorFromString("enableAutomationModeWithError:")) {
    var error: NSError?
    if !unsafeBitCast(objcCall(session, "enableAutomationModeWithError:"), to: EnableFn.self)(session, NSSelectorFromString("enableAutomationModeWithError:"), &error) { return (nil, "automation mode: \(error?.localizedDescription ?? "refused")") }
  }
  return (session, nil)
}
/** Ends the automation session so the phone accepts the next client's session (a session left open blocks them). */
func closeSession() {
  guard let session = automationSession else { return }
  automationSession = nil
  if session.responds(to: NSSelectorFromString("invalidate")) { _ = session.perform(NSSelectorFromString("invalidate")) }
  // The invalidation is a message to the phone's testmanagerd: give it time to arrive before the process ends.
  RunLoop.current.run(until: Date().addingTimeInterval(0.8))
}
func loadAccessibility(_ session: AnyObject, timeout: Double) -> String? {
  let done = DispatchSemaphore(value: 0); var ok = false; var failure: String?
  let reply: @convention(block) (Bool, NSError?) -> Void = { loaded, e in ok = loaded; failure = e?.localizedDescription; done.signal() }
  typealias LoadFn = @convention(c) (AnyObject, Selector, Double, AnyObject) -> Void
  unsafeBitCast(objcCall(session, "loadAccessibilityWithTimeout:reply:"), to: LoadFn.self)(session, NSSelectorFromString("loadAccessibilityWithTimeout:reply:"), timeout, reply as AnyObject)
  if done.wait(timeout: .now() + timeout + 1) == .timedOut { return "timed out loading accessibility" }
  return ok ? nil : (failure ?? "accessibility load refused")
}
typealias BootstrapIMP = @convention(c) (AnyClass, Selector, AnyObject, Double, AnyObject?, UnsafeMutablePointer<NSError?>?) -> Bool
var lastBootstrapError: String?
func installPersistentBootstrap() {
  let cls: AnyClass = FBSimulatorControlFrameworkLoader.self
  let sel = NSSelectorFromString("bootstrapAccessibilityForSimulatorDevice:timeout:logger:error:")
  guard let method = class_getClassMethod(cls, sel) else { return }
  let original = unsafeBitCast(method_getImplementation(method), to: BootstrapIMP.self)
  let block: @convention(block) (AnyClass, AnyObject, Double, AnyObject?, UnsafeMutablePointer<NSError?>?) -> Bool = { klass, device, timeout, logger, errorOut in
    if skipBootstrap { return true }
    if let session = automationSession {
      if !forceBootstrap { return true }
      bootstrapCount += 1; forceBootstrap = false
      if let failure = loadAccessibility(session, timeout: 10) { lastBootstrapError = failure; return true }
      return true
    }
    // The first time: the framework's own bootstrap loads the XCTest frameworks; then our session stays open.
    bootstrapCount += 1
    // The XCTest frameworks the session needs, loaded the framework's way, without its throwaway session.
    var loaded = false
    if let loader = (FBSimulatorControlFrameworkLoader.self as AnyObject).perform(NSSelectorFromString("accessibilityAutomationFrameworks"))?.takeUnretainedValue() as? FBSimulatorControlFrameworkLoader {
      loaded = (try? loader.loadPrivateFrameworks(logger as? FBControlCoreLogger)) != nil
    }
    if !loaded { _ = original(klass, sel, device, max(timeout, 20), logger, errorOut) }
    let (session, failure) = openSession(device: device, timeout: 20)
    guard let session else { lastBootstrapError = failure; return false }
    if let failure = loadAccessibility(session, timeout: 10) { lastBootstrapError = failure }
    automationSession = session; forceBootstrap = false
    return true
  }
  method_setImplementation(method, imp_implementationWithBlock(block))
}
func nodeCount(_ tree: Any) -> Int {
  if let list = tree as? [Any] { return list.reduce(0) { $0 + nodeCount($1) } }
  guard let n = tree as? [String: Any] else { return 0 }
  return 1 + ((n["children"] as? [Any]).map(nodeCount) ?? 0)
}
@MainActor
func readFrontmost(_ simulator: FBSimulator, keys: Set<FBAXKeys>, nested: Bool = true) async throws -> Any {
  var reloaded = false
  lastSerializeMs = []
  for attempt in 0..<2 {
    do {
      let readStart = Date()
      let element = try await simulator.accessibilityElementForFrontmostApplication()
      var tree = withDefaults(try element.serialize(with: FBAccessibilityRequestOptions(nestedFormat: nested, keys: keys)).elements)
      element.close()
      lastSerializeMs.append(ms(readStart))
      if attempt == 0 && isEmptyApp(tree) { forceBootstrap = true; reloaded = true; continue }
      // A different app in front (one opened or closed) fills in its elements over a moment: read again until two
      // reads agree, up to 2 s. Within one app a single read is enough.
      let pid = ((tree as? [[String: Any]])?.first?["pid"] as? Int) ?? -1
      if reloaded || pid != lastFrontPid {
        let start = Date()
        while Date().timeIntervalSince(start) < 2 {
          try? await Task.sleep(nanoseconds: 250_000_000)
          let againStart = Date()
          let again = try await simulator.accessibilityElementForFrontmostApplication()
          let next = withDefaults(try again.serialize(with: FBAccessibilityRequestOptions(nestedFormat: nested, keys: keys)).elements)
          again.close()
          lastSerializeMs.append(ms(againStart))
          let same = signature(next) == signature(tree)
          tree = next
          // Two equal reads of a nearly empty app are its shell before the content: not settled yet.
          if same && !isEmptyApp(tree) && nodeCount(tree) >= 12 { break }
        }
      }
      lastFrontPid = ((tree as? [[String: Any]])?.first?["pid"] as? Int) ?? -1
      lastTreeSignature = signature(tree)
      return tree
    } catch {
      if attempt == 0 && String(describing: error).contains("No translation object") { forceBootstrap = true; continue }
      throw error
    }
  }
  return []
}
@MainActor
func main() async {
  do {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(logger)
    if !args.contains("--bootstrap-every-call") { installPersistentBootstrap() }
    let control = try FBSimulatorControl.withConfiguration(FBSimulatorControlConfiguration(deviceSetPath: deviceSetPath, logger: logger, reporter: nil))
    guard let simulator = control.set.allSimulators.first(where: { $0.udid == udid }) else { throw EngineError(message: "no simulator \(udid)") }
    guard simulator.state == .booted else { throw EngineError(message: "simulator \(udid) is not booted") }
    let loaded = ms(started)
    let hidStart = Date()
    let hid = try await simulator.connectToHID()
    let watcher = DamageWatcher()
    let fbStart = Date()
    let framebuffer: FBFramebuffer? = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<FBFramebuffer, Error>) in
      DispatchQueue.global().async { do { cont.resume(returning: try simulator.connectToFramebuffer().block()) } catch { cont.resume(throwing: error) } }
    }
    let surface = framebuffer?.attach(watcher, on: DispatchQueue(label: "damage"))
    watcher.surface = surface
    emit(["ready": true, "load_ms": loaded, "hid_ms": ms(hidStart), "framebuffer_ms": ms(fbStart), "framebuffer": framebuffer != nil, "surface": surface != nil, "name": simulator.name])

    for sig in [SIGTERM, SIGINT, SIGHUP] {
      signal(sig, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { closeSession(); exit(0) }
      source.resume(); signalSources.append(source)
    }
    while let line = readLine() {
      let t0 = Date()
      guard let data = line.data(using: .utf8), let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let op = req["op"] as? String else { emit(["ok": false, "error": "bad request"]); continue }
      let id = req["id"] ?? NSNull()
      do {
        var answer: [String: Any] = ["id": id, "ok": true]
        switch op {
        case "describe":
          var keys = outputKeys
          if let names = req["keys"] as? [String] {
            // An unknown name would silently drop that attribute from every element (AXLabel for label read as no text).
            let unknown = names.filter { keyNamed($0) == nil }
            if !unknown.isEmpty { throw EngineError(message: "unknown keys \(unknown.joined(separator: ", ")); the names are label, frame, value, uniqueID, type, title, frameDict, help, enabled, customActions, role, roleDescription, subrole, contentRequired, pid") }
            keys = Set(names.compactMap(keyNamed))
          }
          answer["tree"] = try await readFrontmost(simulator, keys: keys, nested: (req["nested"] as? Bool) ?? true)
          answer["cpu_ms"] = cpuMs(); answer["serialize_ms"] = lastSerializeMs
        case "point":
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0
          for attempt in 0..<2 {
            do {
              let element = try await simulator.accessibilityElement(at: CGPoint(x: x, y: y))
              defer { element.close() }
              answer["element"] = withDefaults(try element.serialize(with: FBAccessibilityRequestOptions(nestedFormat: false, keys: outputKeys)).elements)
              break
            } catch {
              if attempt == 0 && String(describing: error).contains("No translation object") { forceBootstrap = true; continue }
              throw error
            }
          }
        case "tap":
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0
          try await hid.send(event: .tapAt(x: x, y: y), logger: logger)
        case "swipe":
          let x1 = req["x1"] as? Double ?? 0, y1 = req["y1"] as? Double ?? 0, x2 = req["x2"] as? Double ?? 0, y2 = req["y2"] as? Double ?? 0
          try await hid.send(event: .swipe(x1, yStart: y1, xEnd: x2, yEnd: y2, delta: req["delta"] as? Double ?? 10, duration: req["duration"] as? Double ?? 0.3), logger: logger)
        case "type":
          let text = req["text"] as? String ?? ""
          try await hid.send(event: .composite(try TextToHIDEvents.convertTextToHIDEvents(text)), logger: logger)
        case "steps":
          // simulator-use's input batch, as one HID composite: [{"tap":[x,y]}, {"sleep":s}, {"key":code},
          // {"combo":{"mods":[codes],"key":code}}, {"type":"text"}, {"touch":[x,y],"hold":s}].
          var events: [FBSimulatorHIDEvent] = []
          for step in (req["steps"] as? [[String: Any]]) ?? [] {
            if let p = step["tap"] as? [Double], p.count == 2 { events.append(.tapAt(x: p[0], y: p[1])) }
            else if let s = step["sleep"] as? Double { events.append(.delay(s)) }
            else if let k = step["key"] as? Int { events += [.keyboard(direction: .down, keyCode: UInt32(k)), .keyboard(direction: .up, keyCode: UInt32(k))] }
            else if let c = step["combo"] as? [String: Any], let k = c["key"] as? Int {
              let mods = ((c["mods"] as? [Int]) ?? []).map { UInt32($0) }
              events += mods.map { .keyboard(direction: .down, keyCode: $0) }
              events += [.keyboard(direction: .down, keyCode: UInt32(k)), .keyboard(direction: .up, keyCode: UInt32(k))]
              events += mods.reversed().map { .keyboard(direction: .up, keyCode: $0) }
            }
            else if let t = step["type"] as? String { events += try TextToHIDEvents.convertTextToHIDEvents(t) }
            else if let p = step["touch"] as? [Double], p.count == 2 {
              events += [.touch(direction: .down, x: p[0], y: p[1]), .delay(step["hold"] as? Double ?? 0.1), .touch(direction: .up, x: p[0], y: p[1])]
            }
            else { throw EngineError(message: "unknown step \(step)") }
          }
          try await hid.send(event: .composite(events), logger: logger)
        case "drag":
          // A finger put down, moved in steps and lifted (sliders, reordering); a swipe is a quick drag.
          let x1 = req["x1"] as? Double ?? 0, y1 = req["y1"] as? Double ?? 0, x2 = req["x2"] as? Double ?? 0, y2 = req["y2"] as? Double ?? 0
          let duration = req["duration"] as? Double ?? 0.6, n = max(1, Int(req["steps"] as? Double ?? 20))
          var events: [FBSimulatorHIDEvent] = [.touch(direction: .down, x: x1, y: y1), .delay(req["hold"] as? Double ?? 0.05)]
          for i in 1...n { let f = Double(i) / Double(n); events += [.delay(duration / Double(n)), .touch(direction: .down, x: x1 + (x2 - x1) * f, y: y1 + (y2 - y1) * f)] }
          events.append(.touch(direction: .up, x: x2, y: y2))
          try await hid.send(event: .composite(events), logger: logger)
        case "lock":
          try await hid.send(event: .shortButtonPress(.lock), logger: logger)
        case "settle":
          let (waited, updates, settled) = await settle(watcher, quietMs: req["quiet_ms"] as? Double ?? 150, timeoutMs: req["timeout_ms"] as? Double ?? 4000, firstChangeMs: req["first_change_ms"] as? Double ?? 0)
          answer["waited_ms"] = waited; answer["updates"] = updates; answer["settled"] = settled
        case "tap_settle_describe":
          // One call for an act: the tap, the wait until the screen stops changing, then the new tree.
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0
          try await hid.send(event: .tapAt(x: x, y: y), logger: logger)
          let (waited, updates, settled) = await settle(watcher, quietMs: req["quiet_ms"] as? Double ?? 150, timeoutMs: req["timeout_ms"] as? Double ?? 4000, firstChangeMs: req["first_change_ms"] as? Double ?? 800)
          let readStart = Date()
          // An app still launching reads as an application with nothing in it: wait for content, up to 3 s.
          var tree: Any = []; var reads = 0
          let before = lastTreeSignature
          while true {
            tree = try await readFrontmost(simulator, keys: outputKeys); reads += 1
            // The screen moved but reads as before: the change (an app opening) is not in the tree yet.
            let unchanged = updates > 0 && signature(tree) == before
            if (!isEmptyApp(tree) && !unchanged) || Date().timeIntervalSince(readStart) > 2.5 { break }
            _ = await settle(watcher, quietMs: 150, timeoutMs: 1000, firstChangeMs: 0)
          }
          answer["tree"] = tree; answer["settle_ms"] = waited; answer["updates"] = updates; answer["settled"] = settled; answer["read_ms"] = ms(readStart); answer["reads"] = reads
        case "tap_trace":
          // When the screen changes after a tap: one timestamp (ms after the tap) per surface change.
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0, windowMs = req["window_ms"] as? Double ?? 3000
          try await hid.send(event: .tapAt(x: x, y: y), logger: logger)
          let start = Date(); var changes: [Int] = []; var last = watcher.snapshot().1
          while Date().timeIntervalSince(start) * 1000 < windowMs {
            try? await Task.sleep(nanoseconds: 5_000_000); watcher.pollSeed()
            let now = watcher.snapshot().1; if now != last { changes.append(ms(start)); last = now }
          }
          answer["changes"] = changes
        case "home":
          // A press, held briefly; if the screen did not change, once more (a press during an app's launch is dropped).
          // With "wait": false only the press (the caller waits for the screen itself).
          for attempt in 0..<((req["wait"] as? Bool) == false ? 1 : 2) {
            if (req["wait"] as? Bool) == false {
              try await hid.send(event: .composite([.button(direction: .down, button: .homeButton), .delay(0.06), .button(direction: .up, button: .homeButton)]), logger: logger)
              break
            }
            try await hid.send(event: .composite([.button(direction: .down, button: .homeButton), .delay(0.06), .button(direction: .up, button: .homeButton)]), logger: logger)
            let (_, updates, _) = await settle(watcher, quietMs: 150, timeoutMs: 3000, firstChangeMs: 600)
            answer["attempts"] = attempt + 1; answer["updates"] = updates
            if updates > 0 { break }
          }
        case "screenshot":
          let png = try await simulator.takeScreenshot(format: .png)
          let shotMs = ms(t0)
          if (req["format"] as? String) == "png" { answer["bytes"] = png.count }
          else {
            var size: (Double, Double)? = nil
            if let w = req["width"] as? Double, let h = req["height"] as? Double { size = (w, h) }
            let jpg = try jpeg(fromPNG: png, maxPoints: size, quality: req["quality"] as? Double ?? 0.7)
            answer["bytes"] = jpg.count
            if req["path"] as? String != nil { try jpg.write(to: URL(fileURLWithPath: req["path"] as! String)) }
            if req["inline"] as? Bool == true { answer["jpeg_base64"] = jpg.base64EncodedString() }
          }
          answer["capture_ms"] = shotMs
        case "stream":
          // Hardware-encoded video of the screen for N seconds into a file: the live view's source.
          let seconds = req["seconds"] as? Double ?? 10, fps = req["fps"] as? Double ?? 30
          let codec: FBVideoStreamCodec = (req["codec"] as? String) == "hevc" ? .hevc : .h264
          let transportName = req["transport"] as? String ?? "annexb"
          let transport: FBVideoStreamTransport = transportName == "fmp4" ? .fmp4 : (transportName == "mpegts" ? .mpegts : .annexB)
          let config = FBVideoStreamConfiguration(format: .compressedVideo(withCodec: codec, transport: transport), framesPerSecond: NSNumber(value: fps),
            rateControl: .bitrate(NSNumber(value: req["bitrate"] as? Double ?? 2_000_000)), scaleFactor: NSNumber(value: req["scale"] as? Double ?? 0.5), keyFrameRate: NSNumber(value: req["keyframe_s"] as? Double ?? 2))
          let stream = try await simulator.createStream(configuration: config)
          let path = req["path"] as? String ?? "/tmp/sue-stream.bin"
          FileManager.default.createFile(atPath: path, contents: nil)
          guard let fh = FileHandle(forWritingAtPath: path) else { throw EngineError(message: "cannot write \(path)") }
          let counter = StreamCounter(start: t0)
          let consumer = FBBlockDataConsumer.synchronousDataConsumer { data in fh.write(data); counter.add(data.count) }
          _ = cpuMs()
          try await blocking { try stream.startStreaming(consumer).block() }
          try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
          try await blocking { try stream.stopStreaming().block() }
          fh.closeFile()
          answer["bytes"] = counter.bytes; answer["chunks"] = counter.chunks; answer["first_chunk_ms"] = counter.first
          answer["kbit_s"] = Int(Double(counter.bytes) * 8 / 1000 / seconds); answer["engine_cpu_pct"] = Int(Double(cpuMs()) / (seconds * 10))
        default:
          throw EngineError(message: "unknown op \(op)")
        }
        answer["ms"] = ms(t0); answer["bootstraps"] = bootstrapCount
        if let failure = lastBootstrapError { answer["bootstrap_error"] = failure; lastBootstrapError = nil }
        emit(answer)
      } catch {
        emit(["id": id, "ok": false, "ms": ms(t0), "error": (error as? EngineError)?.message ?? String(describing: error)])
      }
    }
    closeSession()
    exit(0)
  } catch {
    emit(["ready": false, "error": (error as? EngineError)?.message ?? String(describing: error)])
    exit(1)
  }
}
Task { await main() }
RunLoop.main.run()
