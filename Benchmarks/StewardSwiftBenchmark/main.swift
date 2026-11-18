// Parse times for a corpus's largest Swift files: swift-syntax's parse on
// its own, and SwiftFile's whole read (the nesting scan, the hop to its
// thread, the parse, and the model). Run it in a release build:
//
//     swift run -c release StewardSwiftBenchmark <directory> [largest] [runs]
//
// It prints a Markdown table, as docs/performance.md records it.

import Foundation
import StewardSwift
import SwiftParser

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: StewardSwiftBenchmark <directory> [largest, default 10] [runs, default 5]")
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let largest = arguments.count > 2 ? Int(arguments[2]) ?? 10 : 10
let runs = arguments.count > 3 ? Int(arguments[3]) ?? 5 : 5

struct Source {
    var path: String
    var text: String
    var bytes: Int { text.utf8.count }
}

let sources = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
    .filter { $0.pathExtension == "swift" }
    .map { url in
        Source(
            path: String(url.standardizedFileURL.path.dropFirst(root.path.count + 1)),
            text: String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
        )
    }
    .sorted { $0.bytes > $1.bytes }

let clock = ContinuousClock()

/// The median of `runs` timings of `work`, after one run to warm up.
func median(_ work: () -> Void) -> Duration {
    work()
    let times = (0..<runs).map { _ in clock.measure(work) }.sorted()
    return times[times.count / 2]
}

/// `value` with one decimal, without `String(format:)`, whose C varargs
/// strict memory safety rejects.
func oneDecimal(_ value: Double) -> String {
    let tenths = Int((value * 10).rounded())
    return "\(tenths / 10).\(abs(tenths % 10))"
}

func seconds(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
}

func milliseconds(_ duration: Duration) -> String {
    oneDecimal(seconds(duration) * 1_000)
}

func megabytesPerSecond(bytes: Int, _ duration: Duration) -> String {
    oneDecimal(Double(bytes) / 1e6 / max(seconds(duration), 1e-9))
}

print("| File | KB | Parse (ms) | SwiftFile (ms) | SwiftFile (MB/s) |")
print("|---|---:|---:|---:|---:|")
sources.prefix(largest).forEach { source in
    let parse = median {
        var parser = Parser(source.text, maximumNestingLevel: 256)
        _ = SourceFileSyntax.parse(from: &parser)
    }
    let read = median { _ = try? SwiftFile(source: source.text, path: source.path) }
    print("| `\(source.path)` | \(source.bytes / 1_000) | \(milliseconds(parse)) | \(milliseconds(read)) "
        + "| \(megabytesPerSecond(bytes: source.bytes, read)) |")
}

let totalBytes = sources.map(\.bytes).reduce(0, +)
var refused = 0
let whole = clock.measure {
    sources.forEach { source in
        if (try? SwiftFile(source: source.text, path: source.path)) == nil { refused += 1 }
    }
}
print("")
print("All \(sources.count) files, \(totalBytes / 1_000) KB: \(milliseconds(whole)) ms once each, "
    + "\(megabytesPerSecond(bytes: totalBytes, whole)) MB/s, \(refused) refused.")
