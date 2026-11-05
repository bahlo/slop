import CoreMediaIO
import Foundation

// Turns an Elgato Key Light on while a camera is in use, off otherwise.

setvbuf(stdout, nil, _IOLBF, 0) // flush per line so launchd logs show up
setvbuf(stderr, nil, _IOLBF, 0)

// MARK: - Configuration (flag > env var > default)

let defaultCameraMatch = "Facecam"
let defaultLightURL = "http://elgato-key-light-air-eaa5.local:9123/elgato/lights"

let usage = """
usage: webcam-hook [--camera <name>] [--light-url <url>] [--check]

Turns an Elgato Key Light on while a matching camera is in use, off otherwise.

  --camera <name>     substring of the camera name to watch
                      env WEBCAM_HOOK_CAMERA, default "\(defaultCameraMatch)"
  --light-url <url>   the light's /elgato/lights endpoint
                      env WEBCAM_HOOK_LIGHT_URL, default \(defaultLightURL)
  --check             list cameras, read the light's state once (GET), and exit
  -h, --help          show this help
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("webcam-hook: \(message)\n\n\(usage)\n".utf8))
    exit(64) // EX_USAGE
}

let env = ProcessInfo.processInfo.environment
var cameraMatch = env["WEBCAM_HOOK_CAMERA"] ?? defaultCameraMatch
var lightURLString = env["WEBCAM_HOOK_LIGHT_URL"] ?? defaultLightURL
var checkOnly = false

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    // Accept both "--flag value" and "--flag=value".
    let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
    let flag = parts[0]
    func value() -> String {
        if parts.count == 2 { return parts[1] }
        guard let next = args.popFirst() else { fail("\(flag) needs a value") }
        return next
    }
    switch flag {
    case "--camera": cameraMatch = value()
    case "--light-url": lightURLString = value()
    case "--check": checkOnly = true
    case "-h", "--help": print(usage); exit(0)
    default: fail("unknown argument \(arg)")
    }
}

guard !cameraMatch.isEmpty else { fail("camera name match must not be empty") }
guard let lightURL = URL(string: lightURLString),
      ["http", "https"].contains(lightURL.scheme?.lowercased()),
      lightURL.host != nil
else { fail("invalid light URL \(lightURLString)") }

let timestamp = ISO8601DateFormatter()
func log(_ message: String) {
    print("\(timestamp.string(from: Date())) \(message)")
}

// MARK: - CoreMediaIO

enum Camera {
    static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func all() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == 0 else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func name(_ id: CMIOObjectID) -> String {
        var addr = address(kCMIOObjectPropertyName)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &used, &value) == 0, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    static func isRunning(_ id: CMIOObjectID) -> Bool {
        var addr = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return value != 0
    }

    // An unplugged camera counts as off.
    static func anyRunning(matching match: String) -> Bool {
        all().contains { name($0).contains(match) && isRunning($0) }
    }
}

// MARK: - Light

func describe(_ resp: URLResponse?, _ err: Error?) -> String {
    err.map { "\($0)" } ?? "status \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
}

func isOK(_ resp: URLResponse?, _ err: Error?) -> Bool {
    err == nil && (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
}

func getLight(_ done: @escaping (_ body: String?, _ error: String?) -> Void) {
    URLSession.shared.dataTask(with: URLRequest(url: lightURL, timeoutInterval: 5)) { data, resp, err in
        if isOK(resp, err) {
            done(String(decoding: data ?? Data(), as: UTF8.self), nil)
        } else {
            done(nil, describe(resp, err))
        }
    }.resume()
}

func setLight(_ on: Bool, done: @escaping (Bool) -> Void) {
    var req = URLRequest(url: lightURL, timeoutInterval: 5)
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Only "on" is sent, so brightness and colour temperature are left alone.
    req.httpBody = Data(#"{"numberOfLights":1,"lights":[{"on":\#(on ? 1 : 0)}]}"#.utf8)
    URLSession.shared.dataTask(with: req) { _, resp, err in
        let ok = isOK(resp, err)
        if !ok { log("light request failed: \(describe(resp, err))") }
        DispatchQueue.main.async { done(ok) }
    }.resume()
}

// MARK: - Main

if checkOnly {
    print("camera match: \"\(cameraMatch)\"")
    let ids = Camera.all()
    if ids.isEmpty { print("no cameras found (inside a sandbox the list is always empty)") }
    for id in ids {
        let n = Camera.name(id)
        print("  \(n.contains(cameraMatch) ? "*" : " ") \(n) [\(Camera.isRunning(id) ? "running" : "idle")]")
    }
    print("GET \(lightURL.absoluteString)")
    getLight { body, error in
        print(body.map { "  \($0)" } ?? "  failed: \(error ?? "")")
        exit(body == nil ? 1 : 0)
    }
    RunLoop.main.run()
}

log("watching cameras matching \"\(cameraMatch)\", light \(lightURL.absoluteString)")
log("cameras: \(Camera.all().map(Camera.name))")
var last = Camera.anyRunning(matching: cameraMatch)
var inFlight = false
log("started, camera \(last ? "on" : "off")")

// Read the light once at startup (GET, changes nothing). Under launchd this is
// also what triggers the Local Network prompt, so it shows up at login rather
// than the first time the camera turns on.
getLight { body, error in
    if let body {
        log("light reachable: \(body)")
    } else {
        log("light not reachable: \(error ?? ""). If it works from Terminal, check "
            + "System Settings > Privacy & Security > Local Network for webcam-hook.")
    }
}

// Poll once a second: cheap, and handles the camera being plugged in or out.
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    guard !inFlight else { return }
    let on = Camera.anyRunning(matching: cameraMatch)
    guard on != last else { return }
    log("camera \(on ? "on" : "off") -> light \(on ? "on" : "off")")
    inFlight = true
    setLight(on) { ok in
        inFlight = false
        if ok { last = on } // on failure, retry next tick
    }
}
RunLoop.main.run()
