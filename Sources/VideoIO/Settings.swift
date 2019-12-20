//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/20.
//

import Foundation

public struct VideoSettings {
    public struct CompressionProperties {
        public var bitRate: Int
        public var profileLevel: String
        
        public init(bitRate: Int, profileLevel: String) {
            self.bitRate = bitRate
            self.profileLevel = profileLevel
        }
    }
    public var width: Int
    public var height: Int
    public var codec: AVVideoCodecType
    public var compressionProperties: CompressionProperties
    
    public init(size: CGSize, codec: AVVideoCodecType, compressionProperties: CompressionProperties) {
        self.width = Int(size.width)
        self.height = Int(size.height)
        self.codec = codec
        self.compressionProperties = compressionProperties
    }
    
    public func toDictionary() -> [String: Any] {
        return [
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCodecKey: codec,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: compressionProperties.bitRate,
                AVVideoProfileLevelKey: compressionProperties.profileLevel
            ]
        ]
    }
}

public struct AudioSettings {
    
    public var formatID: AudioFormatID
    public var numberOfChannels: Int
    public var sampleRate: Double
    public var bitRate: Int
    
    public init(formatID: AudioFormatID, channels: Int, sampleRate: Double, bitRate: Int) {
        self.formatID = formatID
        self.numberOfChannels = channels
        self.sampleRate = sampleRate
        self.bitRate = bitRate
    }
    
    public func toDictionary() -> [String: Any] {
        return [
            AVFormatIDKey: formatID,
            AVNumberOfChannelsKey: numberOfChannels,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: bitRate
        ]
    }
}
    
