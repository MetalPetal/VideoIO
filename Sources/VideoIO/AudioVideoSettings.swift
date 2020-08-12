//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/20.
//

import Foundation
import AVFoundation
import VideoToolbox

extension AVVideoCodecType: Codable {
    
}

public struct VideoSettings: Codable {
    
    public struct ScalingMode: RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
        public init(_ value: String) {
            self.init(rawValue: value)
        }
        public static let fit = ScalingMode(AVVideoScalingModeFit)
        public static let resize = ScalingMode(AVVideoScalingModeResize)
        public static let resizeAspect = ScalingMode(AVVideoScalingModeResizeAspect)
        public static let resizeAspectFill = ScalingMode(AVVideoScalingModeResizeAspectFill)
    }
    
    public struct CompressionProperties: Codable {
        public var averageBitRate: Int?
        public var profileLevel: String?
        
        public var allowFrameReordering: Bool?
        
        public init(averageBitRate: Int, profileLevel: String) {
            self.averageBitRate = averageBitRate
            self.profileLevel = profileLevel
        }
        
        public init() {
            
        }
        
        public struct CodingKeys: CodingKey {
            public let stringValue: String
            public init(_ stringValue: String) {
                self.stringValue = stringValue
            }
            public init?(stringValue: String) {
                self.stringValue = stringValue
            }
            public let intValue: Int? = nil
            public init?(intValue: Int) {
                fatalError()
            }
            
            public static let averageBitRate = CodingKeys(AVVideoAverageBitRateKey)
            public static let profileLevel = CodingKeys(AVVideoProfileLevelKey)
            public static let allowFrameReordering = CodingKeys(AVVideoAllowFrameReorderingKey)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(averageBitRate, forKey: .averageBitRate)
            try container.encodeIfPresent(profileLevel, forKey: .profileLevel)
            try container.encodeIfPresent(allowFrameReordering, forKey: .allowFrameReordering)
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.averageBitRate = try container.decodeIfPresent(Int.self, forKey: .averageBitRate)
            self.profileLevel = try container.decodeIfPresent(String.self, forKey: .profileLevel)
            self.allowFrameReordering = try container.decodeIfPresent(Bool.self, forKey: .allowFrameReordering)
        }
    }
    
    public var width: Int
    public var height: Int
    public var codec: AVVideoCodecType
    public var scalingMode: ScalingMode?
    
    public var compressionProperties: CompressionProperties?
    
    public init(size: CGSize, codec: AVVideoCodecType) {
        self.width = Int(size.width)
        self.height = Int(size.height)
        self.codec = codec
    }
    
    public struct CodingKeys: CodingKey {
        public let stringValue: String
        public init(_ stringValue: String) {
            self.stringValue = stringValue
        }
        public init?(stringValue: String) {
            self.stringValue = stringValue
        }
        public let intValue: Int? = nil
        public init?(intValue: Int) {
            fatalError()
        }
        
        public static let width = CodingKeys(AVVideoWidthKey)
        public static let height = CodingKeys(AVVideoHeightKey)
        public static let codec = CodingKeys(AVVideoCodecKey)
        public static let compressionProperties = CodingKeys(AVVideoCompressionPropertiesKey)
        public static let scalingMode = CodingKeys(AVVideoScalingModeKey)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(codec, forKey: .codec)
        try container.encodeIfPresent(scalingMode?.rawValue, forKey: .scalingMode)
        try container.encodeIfPresent(compressionProperties, forKey: .compressionProperties)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.width = try container.decode(Int.self, forKey: .width)
        self.height = try container.decode(Int.self, forKey: .height)
        self.codec = try container.decode(AVVideoCodecType.self, forKey: .codec)
        self.scalingMode = (try container.decodeIfPresent(String.self, forKey: .scalingMode)).map(ScalingMode.init(rawValue:))
        self.compressionProperties = try container.decodeIfPresent(CompressionProperties.self, forKey: .compressionProperties)
    }
    
    public func toDictionary() -> [String: Any] {
        let data = try! JSONEncoder().encode(self)
        return try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    }
    
    public static func h264(videoSize: CGSize, averageBitRate: Int? = nil) -> Self {
        let codec: AVVideoCodecType
        if #available(iOS 11.0, *) {
            codec = .h264
        } else {
            codec = AVVideoCodecType(rawValue: AVVideoCodecH264)
        }
        var videoSettings = VideoSettings(size: videoSize, codec: codec)
        if let averageBitRate = averageBitRate {
            videoSettings.compressionProperties = CompressionProperties(averageBitRate: averageBitRate, profileLevel: AVVideoProfileLevelH264HighAutoLevel)
        }
        return videoSettings
    }
    
    @available(iOS 11.0, *)
    public static func hevc(videoSize: CGSize, averageBitRate: Int? = nil) -> Self {
        var videoSettings = VideoSettings(size: videoSize, codec: .hevc)
        if let averageBitRate = averageBitRate {
            videoSettings.compressionProperties = CompressionProperties(averageBitRate: averageBitRate, profileLevel: kVTProfileLevel_HEVC_Main_AutoLevel as String)
        }
        return videoSettings
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    public static func hevcWithAlpha(videoSize: CGSize, averageBitRate: Int? = nil) -> Self {
        var videoSettings = VideoSettings(size: videoSize, codec: .hevcWithAlpha)
        if let averageBitRate = averageBitRate {
            videoSettings.compressionProperties = CompressionProperties(averageBitRate: averageBitRate, profileLevel: kVTProfileLevel_HEVC_Main_AutoLevel as String)
        }
        return videoSettings
    }
}

public struct AudioSettings: Codable {
    
    public var formatID: AudioFormatID
    public var sampleRate: Double
    public var bitRate: Int?
    
    public var numberOfChannels: Int?
    public var channelLayout: Data?
    
    public init(formatID: AudioFormatID, channels: Int, sampleRate: Double) {
        self.formatID = formatID
        self.numberOfChannels = channels
        self.sampleRate = sampleRate
    }
    
    public init(formatID: AudioFormatID, channelLayout: Data, sampleRate: Double) {
        self.formatID = formatID
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
    }
    
    public struct CodingKeys: CodingKey {
        public let stringValue: String
        public init(_ stringValue: String) {
            self.stringValue = stringValue
        }
        public init?(stringValue: String) {
            self.stringValue = stringValue
        }
        public let intValue: Int? = nil
        public init?(intValue: Int) {
            fatalError()
        }
        
        public static let formatID = CodingKeys(AVFormatIDKey)
        public static let numberOfChannels = CodingKeys(AVNumberOfChannelsKey)
        public static let sampleRate = CodingKeys(AVSampleRateKey)
        public static let bitRate = CodingKeys(AVEncoderBitRateKey)
        public static let channelLayout = CodingKeys(AVChannelLayoutKey)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatID, forKey: .formatID)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(channelLayout, forKey: .channelLayout)
        try container.encodeIfPresent(numberOfChannels, forKey: .numberOfChannels)
        try container.encodeIfPresent(bitRate, forKey: .bitRate)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatID = try container.decode(AudioFormatID.self, forKey: .formatID)
        self.sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        self.channelLayout = try container.decodeIfPresent(Data.self, forKey: .channelLayout)
        self.numberOfChannels = try container.decode(Int.self, forKey: .numberOfChannels)
        self.bitRate = try container.decodeIfPresent(Int.self, forKey: .bitRate)
    }
    
    public func toDictionary() -> [String: Any] {
        let data = try! JSONEncoder().encode(self)
        return try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    }
    
    public static func aac(channels: Int, sampleRate: Double, bitRate: Int?) -> Self {
        var settings = AudioSettings(formatID: kAudioFormatMPEG4AAC, channels: channels, sampleRate: sampleRate)
        settings.bitRate = bitRate
        return settings
    }
    
    public static func aac(channelLayout: Data, sampleRate: Double, bitRate: Int?) -> Self {
        var settings = AudioSettings(formatID: kAudioFormatMPEG4AAC, channelLayout: channelLayout, sampleRate: sampleRate)
        settings.bitRate = bitRate
        return settings
    }
}
    
