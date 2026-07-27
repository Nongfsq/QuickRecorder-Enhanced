import RecordingDomain

// Compatibility aliases keep the current app source stable while recording
// requests and state ownership migrate into RecordingDomain in later slices.
typealias AudioQuality = RecordingDomain.AudioQuality
typealias AudioChannels = RecordingDomain.AudioChannels
typealias AudioFormat = RecordingDomain.AudioFormat
typealias VideoFormat = RecordingDomain.VideoFormat
typealias PixFormat = RecordingDomain.PixFormat
typealias ColSpace = RecordingDomain.ColSpace
typealias Encoder = RecordingDomain.Encoder
typealias VideoBitrate = RecordingDomain.VideoBitrate
typealias StreamType = RecordingDomain.StreamType
typealias BackgroundType = RecordingDomain.BackgroundType
typealias RecordingRequest = RecordingDomain.RecordingRequest
typealias RecordingSettingsSnapshot = RecordingDomain.RecordingSettingsSnapshot
typealias VideoEncodingPolicy = RecordingDomain.VideoEncodingPolicy
typealias VideoEncodingPolicyInput = RecordingDomain.VideoEncodingPolicyInput
typealias AdaptiveVFRPolicy = RecordingDomain.AdaptiveVFRPolicy
typealias AdaptiveVFRInput = RecordingDomain.AdaptiveVFRInput
typealias RecordingSessionState = RecordingDomain.RecordingSessionState
typealias RecordingSessionEvent = RecordingDomain.RecordingSessionEvent
typealias RecordingSessionStateMachine = RecordingDomain.RecordingSessionStateMachine
