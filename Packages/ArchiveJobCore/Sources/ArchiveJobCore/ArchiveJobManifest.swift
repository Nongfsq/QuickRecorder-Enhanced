import Foundation

public enum ArchiveJobState: String, Codable, CaseIterable {
    case preparing
    case runtimeMissing
    case compressing
    case verifying
    case cancelling
    case interrupted
    case completed
    case failed
    case cancelled

    public var isRunning: Bool {
        switch self {
        case .preparing, .compressing, .verifying, .cancelling:
            return true
        case .runtimeMissing, .interrupted, .completed, .failed, .cancelled:
            return false
        }
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }

    public var becomesInterruptedWithoutWorker: Bool {
        switch self {
        case .preparing, .compressing, .verifying, .cancelling:
            return true
        default:
            return false
        }
    }
}

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public init?(foundationValue: Any) {
        switch foundationValue {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, child) in value {
                guard let converted = JSONValue(foundationValue: child) else { return nil }
                object[key] = converted
            }
            self = .object(object)
        case let value as [Any]:
            var array: [JSONValue] = []
            for child in value {
                guard let converted = JSONValue(foundationValue: child) else { return nil }
                array.append(converted)
            }
            self = .array(array)
        case _ as NSNull:
            self = .null
        default:
            return nil
        }
    }

    public var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.foundationValue)
        case .array(let value): return value.map(\.foundationValue)
        case .null: return NSNull()
        }
    }
}

public struct ArchiveJobManifest: Codable, Identifiable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var id: UUID
    public var source: String
    public var output: String
    public var tempOutput: String
    public var status: ArchiveJobState
    public var detail: String
    public var crf: Int
    public var svtPreset: Int
    public var gop: Int
    public var audioMode: String
    public var progress: Double?
    public var error: String?
    public var runtime: String?
    public var sourceSizeBytes: Int64?
    public var outputSizeBytes: Int64?
    public var command: [String]?
    public var validation: [String: JSONValue]?
    public var startedAt: Date
    public var updatedAt: Date
    public var endedAt: Date?

    public init(
        schemaVersion: Int = ArchiveJobManifest.currentSchemaVersion,
        id: UUID,
        source: String,
        output: String,
        tempOutput: String,
        status: ArchiveJobState,
        detail: String,
        crf: Int,
        svtPreset: Int,
        gop: Int,
        audioMode: String,
        progress: Double? = nil,
        error: String? = nil,
        runtime: String? = nil,
        sourceSizeBytes: Int64? = nil,
        outputSizeBytes: Int64? = nil,
        command: [String]? = nil,
        validation: [String: JSONValue]? = nil,
        startedAt: Date,
        updatedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.source = source
        self.output = output
        self.tempOutput = tempOutput
        self.status = status
        self.detail = detail
        self.crf = crf
        self.svtPreset = svtPreset
        self.gop = gop
        self.audioMode = audioMode
        self.progress = progress
        self.error = error
        self.runtime = runtime
        self.sourceSizeBytes = sourceSizeBytes
        self.outputSizeBytes = outputSizeBytes
        self.command = command
        self.validation = validation
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, source, output, tempOutput, status, detail
        case crf, svtPreset, gop, audioMode, progress, error, runtime
        case sourceSizeBytes, outputSizeBytes, command, validation
        case startedAt, updatedAt, endedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "Unsupported archive manifest schema \(schemaVersion)")
        }
        let idText = try container.decode(String.self, forKey: .id)
        guard let decodedID = UUID(uuidString: idText) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid archive job UUID")
        }
        id = decodedID
        source = try container.decode(String.self, forKey: .source)
        output = try container.decode(String.self, forKey: .output)
        tempOutput = try container.decode(String.self, forKey: .tempOutput)
        status = try container.decode(ArchiveJobState.self, forKey: .status)
        detail = try container.decode(String.self, forKey: .detail)
        crf = try container.decode(Int.self, forKey: .crf)
        svtPreset = try container.decode(Int.self, forKey: .svtPreset)
        gop = try container.decode(Int.self, forKey: .gop)
        audioMode = try container.decode(String.self, forKey: .audioMode)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        sourceSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sourceSizeBytes)
        outputSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .outputSizeBytes)
        command = try container.decodeIfPresent([String].self, forKey: .command)
        validation = try container.decodeIfPresent([String: JSONValue].self, forKey: .validation)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(output, forKey: .output)
        try container.encode(tempOutput, forKey: .tempOutput)
        try container.encode(status, forKey: .status)
        try container.encode(detail, forKey: .detail)
        try container.encode(crf, forKey: .crf)
        try container.encode(svtPreset, forKey: .svtPreset)
        try container.encode(gop, forKey: .gop)
        try container.encode(audioMode, forKey: .audioMode)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(runtime, forKey: .runtime)
        try container.encodeIfPresent(sourceSizeBytes, forKey: .sourceSizeBytes)
        try container.encodeIfPresent(outputSizeBytes, forKey: .outputSizeBytes)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(validation, forKey: .validation)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}

public enum ArchiveManifestCodec {
    public static func decode(_ data: Data) throws -> ArchiveJobManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ArchiveJobManifest.self, from: data)
    }

    public static func encode(_ manifest: ArchiveJobManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }
}
