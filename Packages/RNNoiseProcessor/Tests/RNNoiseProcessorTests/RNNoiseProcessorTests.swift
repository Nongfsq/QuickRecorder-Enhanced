import XCTest
@testable import RNNoiseProcessor

final class RNNoiseProcessorTests: XCTestCase {
    func testStreamCompensatesOneFrameLatencyAndFlushesTail() throws {
        let processor = try RNNoiseStreamProcessor()
        let first = (0..<480).map { Float(sin(Double($0) * 0.04)) * 0.25 }
        let second = (0..<480).map { Float(sin(Double($0) * 0.05)) * 0.2 }

        XCTAssertTrue(try processor.process(samples: first).isEmpty)
        let firstOutput = try processor.process(samples: second)
        XCTAssertEqual(firstOutput.count, 480)
        XCTAssertTrue(firstOutput.allSatisfy(\.isFinite))

        let tail = try processor.flush()
        XCTAssertEqual(tail.count, 480)
        XCTAssertTrue(tail.allSatisfy(\.isFinite))
    }

    func testArbitraryChunksPreserveSampleCountAfterFlush() throws {
        let processor = try RNNoiseStreamProcessor()
        let input = (0..<1_337).map { Float(sin(Double($0) * 0.03)) * 0.1 }
        var output: [Float] = []
        output += try processor.process(samples: Array(input[0..<173]))
        output += try processor.process(samples: Array(input[173..<941]))
        output += try processor.process(samples: Array(input[941...]))
        output += try processor.flush()

        XCTAssertEqual(output.count, input.count)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }
}
