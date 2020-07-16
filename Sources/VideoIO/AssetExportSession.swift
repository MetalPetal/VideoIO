//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation

public class AssetExportSession {
    
    public struct Configuration {
        
        public var fileType: AVFileType
        
        public var shouldOptimizeForNetworkUse: Bool = true
        
        public var videoSettings: [String: Any]
        
        public var audioSettings: [String: Any]
        
        public var timeRange: CMTimeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        
        public var metadata: [AVMetadataItem] = []
        
        public var videoComposition: AVVideoComposition?
        
        public var audioMix: AVAudioMix?
        
        public init(fileType: AVFileType, rawVideoSettings: [String: Any], rawAudioSettings: [String: Any]) {
            self.fileType = fileType
            self.videoSettings = rawVideoSettings
            self.audioSettings = rawAudioSettings
        }
        
        public init(fileType: AVFileType, videoSettings: VideoSettings, audioSettings: AudioSettings) {
            self.fileType = fileType
            self.videoSettings = videoSettings.toDictionary()
            self.audioSettings = audioSettings.toDictionary()
        }
    }
    
    public enum Status {
        case idle
        case exporting
        case paused
        case completed
    }
    
    public enum Error: Swift.Error {
        case noTracks
        case cannotAddVideoOutput
        case cannotAddVideoInput
        case cannotAddAudioOutput
        case cannotAddAudioInput
        case cannotStartWriting
        case cannotStartReading
        case invalidStatus
        case cancelled
    }
    
    public private(set) var status: Status = .idle
    
    private let asset: AVAsset
    private let configuration: Configuration
    private let outputURL: URL
    
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    
    private let videoOutput: AVAssetReaderOutput?
    private let audioOutput: AVAssetReaderAudioMixOutput?
    private let videoInput: AVAssetWriterInput?
    private let audioInput: AVAssetWriterInput?
    
    private let queue: DispatchQueue = DispatchQueue(label: "com.MetalPetal.VideoIO.AssetExportSession")
    private let duration: CMTime
    
    private let pauseDispatchGroup = DispatchGroup()
    private var cancelled: Bool = false
    
    public init(asset: AVAsset, outputURL: URL, configuration: Configuration) throws {
        self.asset = asset.copy() as! AVAsset
        self.configuration = configuration
        self.outputURL = outputURL
        
        self.reader = try AVAssetReader(asset: asset)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.fileType)
        self.reader.timeRange = configuration.timeRange
        self.writer.shouldOptimizeForNetworkUse = configuration.shouldOptimizeForNetworkUse
        self.writer.metadata = configuration.metadata
        
        if configuration.timeRange.duration.isValid && !configuration.timeRange.duration.isPositiveInfinity {
            self.duration = configuration.timeRange.duration
        } else {
            self.duration = asset.duration
        }
        
        let videoTracks = asset.tracks(withMediaType: .video)
        if (videoTracks.count > 0) {
            let videoOutput: AVAssetReaderOutput
            let inputTransform: CGAffineTransform?
            if configuration.videoComposition != nil {
                let videoCompositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: nil)
                videoCompositionOutput.alwaysCopiesSampleData = false
                videoCompositionOutput.videoComposition = configuration.videoComposition
                videoOutput = videoCompositionOutput
                inputTransform = nil
            } else {
                if #available(iOS 13.0, macOS 10.15, *) {
                    if videoTracks.first!.hasMediaCharacteristic(.containsAlphaChannel) {
                        videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    } else {
                        videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]])
                    }
                } else {
                    videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]])
                }
                videoOutput.alwaysCopiesSampleData = false
                inputTransform = videoTracks.first!.preferredTransform
            }
            if self.reader.canAdd(videoOutput) {
                self.reader.add(videoOutput)
            } else {
                throw Error.cannotAddVideoOutput
            }
            self.videoOutput = videoOutput
            
            let videoInput: AVAssetWriterInput
            if let transform = inputTransform {
                let size = CGSize(width: configuration.videoSettings[AVVideoWidthKey] as! CGFloat, height: configuration.videoSettings[AVVideoHeightKey] as! CGFloat)
                let transformedSize = size.applying(transform.inverted())
                var videoSettings = configuration.videoSettings
                videoSettings[AVVideoWidthKey] = abs(transformedSize.width)
                videoSettings[AVVideoHeightKey] = abs(transformedSize.height)
                videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput.transform = transform
            } else {
                videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoSettings)
            }
            videoInput.expectsMediaDataInRealTime = false
            if self.writer.canAdd(videoInput) {
                self.writer.add(videoInput)
            } else {
                throw Error.cannotAddVideoInput
            }
            self.videoInput = videoInput
        } else {
            self.videoOutput = nil
            self.videoInput = nil
        }
        
        let audioTracks = self.asset.tracks(withMediaType: .audio)
        if audioTracks.count > 0 {
            let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            audioOutput.alwaysCopiesSampleData = false
            audioOutput.audioMix = configuration.audioMix
            if self.reader.canAdd(audioOutput) {
                self.reader.add(audioOutput)
            } else {
                throw Error.cannotAddAudioOutput
            }
            self.audioOutput = audioOutput
            
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: configuration.audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            if self.writer.canAdd(audioInput) {
                self.writer.add(audioInput)
            }
            self.audioInput = audioInput
        } else {
            self.audioOutput = nil
            self.audioInput = nil
        }
        
        if videoTracks.count == 0 && audioTracks.count == 0 {
            throw Error.noTracks
        }
    }
    
    private func encode(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) -> Bool {
        while input.isReadyForMoreMediaData {
            if self.reader.status != .reading || self.writer.status != .writing {
                input.markAsFinished()
                return false
            }
            self.pauseDispatchGroup.wait()
            if let buffer = output.copyNextSampleBuffer() {
                let progress = (CMSampleBufferGetPresentationTimeStamp(buffer) - self.configuration.timeRange.start).seconds/self.duration.seconds
                if self.videoOutput === output {
                    self.dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: progress) }
                }
                if self.audioOutput === output {
                    self.dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: progress) }
                }
                if !input.append(buffer) {
                    input.markAsFinished()
                    return false
                }
            } else {
                if self.videoOutput === output {
                    self.dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: 1) }
                }
                if self.audioOutput === output {
                    self.dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: 1) }
                }
                input.markAsFinished()
                return false
            }
        }
        return true
    }
    
    
    public class ExportProgress: Progress {
        public let videoEncodingProgress: Progress?
        public let audioEncodingProgress: Progress?
        public let finishWritingProgress: Progress
        
        private let childProgressTotalUnitCount: Int64 = 10000
        
        fileprivate init(tracksAudioEncoding: Bool, tracksVideoEncoding: Bool) {
            finishWritingProgress = Progress(totalUnitCount: childProgressTotalUnitCount)
            audioEncodingProgress = tracksAudioEncoding ? Progress(totalUnitCount: childProgressTotalUnitCount) : nil
            videoEncodingProgress = tracksVideoEncoding ? Progress(totalUnitCount: childProgressTotalUnitCount) : nil
            
            super.init(parent: nil, userInfo: nil)
            
            let pendingUnitCount: Int64 = 1
            self.addChild(finishWritingProgress, withPendingUnitCount: pendingUnitCount)
            self.totalUnitCount += pendingUnitCount
            
            if let progress = audioEncodingProgress {
                let pendingUnitCount: Int64 = 5000
                self.addChild(progress, withPendingUnitCount: pendingUnitCount)
                self.totalUnitCount += pendingUnitCount
            }
            
            if let progress = videoEncodingProgress {
                let pendingUnitCount: Int64 = 5000
                self.addChild(progress, withPendingUnitCount: pendingUnitCount)
                self.totalUnitCount += pendingUnitCount
            }
        }
        
        fileprivate func updateVideoEncodingProgress(fractionCompleted: Double) {
            self.videoEncodingProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
        fileprivate func updateAudioEncodingProgress(fractionCompleted: Double) {
            self.audioEncodingProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
        fileprivate func updateFinishWritingProgress(fractionCompleted: Double) {
            self.finishWritingProgress.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
    }
    
    private var progress: ExportProgress?
    private var progressHandler: ((ExportProgress) -> Void)?

    public func export(progress: ((ExportProgress) -> Void)?, completion: @escaping (Swift.Error?) -> Void) {
        assert(status == .idle && cancelled == false)
        if self.status != .idle || self.cancelled {
            DispatchQueue.main.async {
                completion(Error.invalidStatus)
            }
            return
        }
        
        do {
            guard self.writer.startWriting() else {
                if let error = self.writer.error {
                    throw error
                } else {
                    throw Error.cannotStartWriting
                }
            }
            guard self.reader.startReading() else {
                if let error = self.reader.error {
                    throw error
                } else {
                    throw Error.cannotStartReading
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(error)
            }
            return
        }
        
        self.status = .exporting
        self.progressHandler = progress
        self.progress = ExportProgress(tracksAudioEncoding: self.audioInput != nil, tracksVideoEncoding: self.videoInput != nil)
        
        self.writer.startSession(atSourceTime: configuration.timeRange.start)
        
        var videoCompleted = false
        var audioCompleted = false

        if let videoInput = self.videoInput, let videoOutput = self.videoOutput {
            var sessionForVideoEncoder: AssetExportSession? = self
            videoInput.requestMediaDataWhenReady(on: self.queue) { [unowned videoInput] in
                guard let session = sessionForVideoEncoder else { return }
                if !session.encode(from: videoOutput, to: videoInput) {
                    videoCompleted = true
                    sessionForVideoEncoder = nil
                    if audioCompleted {
                        session.finish(completionHandler: completion)
                    }
                }
            }
        } else {
            videoCompleted = true
        }
        
        if let audioInput = self.audioInput, let audioOutput = self.audioOutput {
            var sessionForAudioEncoder: AssetExportSession? = self
            audioInput.requestMediaDataWhenReady(on: self.queue) { [unowned audioInput] in
                guard let session = sessionForAudioEncoder else { return }
                if !session.encode(from: audioOutput, to: audioInput) {
                    audioCompleted = true
                    sessionForAudioEncoder = nil
                    if videoCompleted {
                        session.finish(completionHandler: completion)
                    }
                }
            }
        } else {
            audioCompleted = true
        }
    }
    
    private func dispatchProgressCallback(with updater: @escaping (ExportProgress) -> Void) {
        DispatchQueue.main.async {
            if let progress = self.progress {
                updater(progress)
                self.progressHandler?(progress)
            }
        }
    }
    
    private func dispatchCallback(with error: Swift.Error?, _ completionHandler: @escaping (Swift.Error?) -> Void) {
        DispatchQueue.main.async {
            self.progressHandler = nil
            self.status = .completed
            completionHandler(error)
        }
    }
    
    private func finish(completionHandler: @escaping (Swift.Error?) -> Void) {
        dispatchPrecondition(condition: DispatchPredicate.onQueue(queue))
        
        if self.reader.status == .cancelled || self.writer.status == .cancelled {
            if self.writer.status != .cancelled {
                self.writer.cancelWriting()
            } else {
                assertionFailure("Internal error. Please file a bug report.")
            }
            
            if self.reader.status != .cancelled {
                assertionFailure("Internal error. Please file a bug report.")
                self.reader.cancelReading()
            }
            
            try? FileManager().removeItem(at: self.outputURL)
            self.dispatchCallback(with: Error.cancelled, completionHandler)
            return
        }
        
        if self.writer.status == .failed {
            try? FileManager().removeItem(at: self.outputURL)
            self.dispatchCallback(with: self.writer.error, completionHandler)
        } else if self.reader.status == .failed {
            try? FileManager().removeItem(at: self.outputURL)
            self.writer.cancelWriting()
            self.dispatchCallback(with: self.reader.error, completionHandler)
        } else {
            self.writer.finishWriting {
                self.queue.async {
                    if self.writer.status == .failed {
                        try? FileManager().removeItem(at: self.outputURL)
                    }
                    if self.writer.error == nil {
                        self.dispatchProgressCallback { $0.updateFinishWritingProgress(fractionCompleted: 1) }
                    }
                    self.dispatchCallback(with: self.writer.error, completionHandler)
                }
            }
        }
    }
    
    public func pause() {
        guard self.status == .exporting && self.cancelled == false else {
            assertionFailure("self.status == .exporting && self.cancelled == false")
            return
        }
        self.status = .paused
        self.pauseDispatchGroup.enter()
    }
    
    public func resume() {
        guard self.status == .paused && self.cancelled == false else {
            assertionFailure("self.status == .paused && self.cancelled == false")
            return
        }
        self.status = .exporting
        self.pauseDispatchGroup.leave()
    }
    
    public func cancel() {
        if self.status == .paused {
            self.resume()
        }
        guard self.status == .exporting && self.cancelled == false else {
            assertionFailure("self.status == .exporting && self.cancelled == false")
            return
        }
        self.cancelled = true
        self.queue.async {
            if self.reader.status == .reading {
                self.reader.cancelReading()
            }
        }
    }
}

extension AssetExportSession {
    public static func fileType(for url: URL) -> AVFileType? {
        switch url.pathExtension.lowercased() {
        case "mp4":
            return .mp4
        case "mp3":
            return .mp3
        case "mov":
            return .mov
        case "qt":
            return .mov
        case "m4a":
            return .m4a
        case "m4v":
            return .m4v
        case "amr":
            return .amr
        case "caf":
            return .caf
        case "wav":
            return .wav
        case "wave":
            return .wav
        default:
            return nil
        }
    }
}
