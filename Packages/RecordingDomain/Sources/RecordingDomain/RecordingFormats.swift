import Foundation

public enum AudioQuality: Int, CaseIterable, Codable, Sendable {
    case speechLow = 48
    case speech = 64
    case speechHigh = 96
    case normal = 128
    case good = 192
    case high = 256
    case extreme = 320
}

public enum AudioChannels: Int, CaseIterable, Codable, Sendable {
    case mono = 1
    case stereo = 2
}

public enum AudioFormat: String, CaseIterable, Codable, Sendable {
    case aac, alac, flac, opus, mp3
}

public enum VideoFormat: String, CaseIterable, Codable, Sendable {
    case mov, mp4
}

public enum PixFormat: String, CaseIterable, Codable, Sendable {
    case delault, yuv420p8v, yuv420p8f, yuv420p10v, yuv420p10f, bgra32
}

public enum ColSpace: String, CaseIterable, Codable, Sendable {
    case delault, srgb, p3, bt709, bt2020
}

public enum Encoder: String, CaseIterable, Codable, Sendable {
    case h264, h265
}

public enum VideoBitrate: Int, CaseIterable, Codable, Sendable {
    case auto = 0
    case kbps50 = 50
    case kbps75 = 75
    case kbps100 = 100
    case kbps150 = 150
    case kbps200 = 200
    case kbps300 = 300
    case kbps500 = 500
    case kbps800 = 800
    case kbps1000 = 1000
}

public enum StreamType: Int, CaseIterable, Codable, Sendable {
    case screen, window, windows, application, screenarea, systemaudio, idevice, camera
}

public enum BackgroundType: String, CaseIterable, Codable, Sendable {
    case wallpaper, clear, black, white, red, green, yellow, orange, gray, blue, custom
}
