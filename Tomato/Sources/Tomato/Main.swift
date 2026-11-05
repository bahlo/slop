import AppKit

@main
enum Main {
    // NSApplication.delegate is unowned; keep the delegate alive ourselves.
    private static let delegate = AppDelegate()

    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            do {
                try SelfTest.run()
                print("SELFTEST OK")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("SELFTEST FAILED: \(error)\n".utf8))
                exit(1)
            }
        }
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
