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
let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
FBControlCoreGlobalConfiguration.defaultLogger = logger

let outputKeys: Set<FBAXKeys> = [.label, .frame, .value, .uniqueID, .type, .title, .frameDict, .help, .enabled, .customActions, .role, .roleDescription, .subrole, .contentRequired, .pid]

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
typealias BootstrapIMP = @convention(c) (AnyClass, Selector, AnyObject, Double, AnyObject?, UnsafeMutablePointer<NSError?>?) -> Bool
var bootstrapDone = false
var bootstrapCount = 0
func bootstrapAccessibilityOnce() {
  let cls: AnyClass = FBSimulatorControlFrameworkLoader.self
  let sel = NSSelectorFromString("bootstrapAccessibilityForSimulatorDevice:timeout:logger:error:")
  guard let method = class_getClassMethod(cls, sel) else { return }
  let original = unsafeBitCast(method_getImplementation(method), to: BootstrapIMP.self)
  let block: @convention(block) (AnyClass, AnyObject, Double, AnyObject?, UnsafeMutablePointer<NSError?>?) -> Bool = { klass, device, timeout, logger, error in
    if bootstrapDone { return true }
    bootstrapCount += 1
    let ok = original(klass, sel, device, max(timeout, 20), logger, error)
    if ok { bootstrapDone = true }
    return ok
  }
  method_setImplementation(method, imp_implementationWithBlock(block))
}
@MainActor
func main() async {
  do {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(logger)
    if !args.contains("--bootstrap-every-call") { bootstrapAccessibilityOnce() }
    let control = try FBSimulatorControl.withConfiguration(FBSimulatorControlConfiguration(deviceSetPath: nil, logger: logger, reporter: nil))
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

    while let line = readLine() {
      let t0 = Date()
      guard let data = line.data(using: .utf8), let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let op = req["op"] as? String else { emit(["ok": false, "error": "bad request"]); continue }
      let id = req["id"] ?? NSNull()
      do {
        var answer: [String: Any] = ["id": id, "ok": true]
        switch op {
        case "describe":
          let element = try await simulator.accessibilityElementForFrontmostApplication()
          defer { element.close() }
          var keys = outputKeys
          if let names = req["keys"] as? [String] { keys = Set(names.compactMap(keyNamed)) }
          let response = try element.serialize(with: FBAccessibilityRequestOptions(nestedFormat: (req["nested"] as? Bool) ?? true, keys: keys))
          answer["tree"] = withDefaults(response.elements)
          answer["cpu_ms"] = cpuMs()
        case "point":
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0
          let element = try await simulator.accessibilityElement(at: CGPoint(x: x, y: y))
          defer { element.close() }
          let response = try element.serialize(with: FBAccessibilityRequestOptions(nestedFormat: false, keys: outputKeys))
          answer["element"] = withDefaults(response.elements)
        case "tap":
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0
          try await hid.send(event: .tapAt(x: x, y: y), logger: logger)
        case "swipe":
          let x1 = req["x1"] as? Double ?? 0, y1 = req["y1"] as? Double ?? 0, x2 = req["x2"] as? Double ?? 0, y2 = req["y2"] as? Double ?? 0
          try await hid.send(event: .swipe(x1, yStart: y1, xEnd: x2, yEnd: y2, delta: req["delta"] as? Double ?? 10, duration: req["duration"] as? Double ?? 0.3), logger: logger)
        case "type":
          let text = req["text"] as? String ?? ""
          try await hid.send(event: .composite(try TextToHIDEvents.convertTextToHIDEvents(text)), logger: logger)
        case "settle":
          let (waited, updates, settled) = await settle(watcher, quietMs: req["quiet_ms"] as? Double ?? 150, timeoutMs: req["timeout_ms"] as? Double ?? 4000, firstChangeMs: req["first_change_ms"] as? Double ?? 0)
          answer["waited_ms"] = waited; answer["updates"] = updates; answer["settled"] = settled
        case "tap_settle_describe":
          // One call for an act: the tap, the wait until the screen stops changing, then the new tree.
          let x = req["x"] as? Double ?? 0, y = req["y"] as? Double ?? 0
          try await hid.send(event: .tapAt(x: x, y: y), logger: logger)
          let (waited, updates, settled) = await settle(watcher, quietMs: req["quiet_ms"] as? Double ?? 150, timeoutMs: req["timeout_ms"] as? Double ?? 4000, firstChangeMs: req["first_change_ms"] as? Double ?? 500)
          let readStart = Date()
          let element = try await simulator.accessibilityElementForFrontmostApplication()
          defer { element.close() }
          let response = try element.serialize(with: FBAccessibilityRequestOptions(nestedFormat: true, keys: outputKeys))
          answer["tree"] = withDefaults(response.elements); answer["settle_ms"] = waited; answer["updates"] = updates; answer["settled"] = settled; answer["read_ms"] = ms(readStart)
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
          try await hid.send(event: .shortButtonPress(.homeButton), logger: logger)
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
        emit(answer)
      } catch {
        emit(["id": id, "ok": false, "ms": ms(t0), "error": (error as? EngineError)?.message ?? String(describing: error)])
      }
    }
    exit(0)
  } catch {
    emit(["ready": false, "error": (error as? EngineError)?.message ?? String(describing: error)])
    exit(1)
  }
}
Task { await main() }
RunLoop.main.run()
