import Foundation

enum ArchiveProgressParser {
    private static let durationPattern = #"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)"#
    private static let timePattern = #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#

    static func duration(from text: String) -> TimeInterval? {
        firstTimeMatch(pattern: durationPattern, in: text)
    }

    static func encodedTime(from text: String) -> TimeInterval? {
        var latest: TimeInterval?
        for match in timeMatches(pattern: timePattern, in: text) {
            latest = match
        }
        return latest
    }

    private static func firstTimeMatch(pattern: String, in text: String) -> TimeInterval? {
        timeMatches(pattern: pattern, in: text).first
    }

    private static func timeMatches(pattern: String, in text: String) -> [TimeInterval] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsrange).compactMap { match in
            guard match.numberOfRanges == 4,
                  let hRange = Range(match.range(at: 1), in: text),
                  let mRange = Range(match.range(at: 2), in: text),
                  let sRange = Range(match.range(at: 3), in: text),
                  let h = Double(text[hRange]),
                  let m = Double(text[mRange]),
                  let s = Double(text[sRange]) else {
                return nil
            }
            return h * 3600 + m * 60 + s
        }
    }
}
