//
//  MovieRecorder.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation
import CoreImage

public protocol MovieRecorderDelegate: class {
    
    func movieRecorderDidFinishPreparing(_ recorder: MovieRecorder)

    func movieRecorderDidCancelRecording(_ recorder: MovieRecorder)

    func movieRecorder(_ recorder: MovieRecorder, didFailWithError error: Error)

    func movieRecorderDidFinishRecording(_ recorder: MovieRecorder)
    
    func movieRecorder(_ recorder: MovieRecorder, didUpdateWithTotalDuration totalDuration: TimeInterval)

}

public enum MovieRecorderError: LocalizedError {
    case sessionDidNotStart
    case cannotSetupInput
    
    public var errorDescription: String? {
        switch  self {
        case .sessionDidNotStart:
            return "session did not start"
        case .cannotSetupInput:
            return "cannot setup asset writer input"
        }
    }
}

public final class MovieRecorder {
    
    /// internal state machine
    private enum Status: Int, Equatable {
        case idle = 0
        case preparingToRecord
        case recording
        case finishingRecordingPart1 // waiting for inflight buffers to be appended
        case finishingRecordingPart2 // calling finish writing on the asset writer
        case finished // terminal state
        case failed // terminal state
        case cancelled // terminal state
    }
    
    private var status: Status = .idle
    private let statusLock = NSLock()
    
    private let writingQueue = DispatchQueue(label: "com.meteor.movie-recorder")
    
    public let url: URL

    private var assetWriter: AVAssetWriter?
    private var haveStartedSession = false
    
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    
    private var videoSampleTime: CMTime = .invalid
    private var lastVideoSampleTime: CMTime = .invalid
    
    private var audioSampleBufferQueue: [CMSampleBuffer] = []
    
    public weak var delegate: MovieRecorderDelegate?
    public var callbackQueue: DispatchQueue = .main
    
    public var metadata: [AVMetadataItem] = []

    /// Exif Orientation
    public var videoOrientation: Int32 = 0
    
    public var videoSettings: [String: Any] = [:]
    public var audioSettings: [String: Any] = [:]

    public var duration: CMTime {
        return videoSampleTime
    }
    
    /// Set audio enabled `true` to record both video and audio.
    /// Set `false' to record video only. Default is `true` `
    public var audioEnabled: Bool = true

    /// Init with target URL
    public init(url: URL) {
        self.url = url
    }

    /// Asynchronous, might take several hundred milliseconds.
    /// When finished the delegate's recorderDidFinishPreparing: or recorder:didFailWithError: method will be called.
    public func prepareToRecord() {
        statusLock.lock()
        defer { statusLock.unlock() }
        if status != .idle {
            print("Already prepared, cannot prepare again")
            return
        }
        transitionToStatus(.preparingToRecord, error: nil)

        writingQueue.async {
            autoreleasepool {
                // AVAssetWriter will not write over an existing file.
                try? FileManager.default.removeItem(at: self.url)
                
                do {
                    self.assetWriter = try AVAssetWriter(url: self.url, fileType: .mp4)
                    self.assetWriter?.metadata = self.metadata
                    self.statusLock.lock()
                    self.transitionToStatus(.recording, error: nil)
                    self.statusLock.unlock()
                } catch {
                    self.statusLock.lock()
                    self.transitionToStatus(.failed, error: error)
                    self.statusLock.unlock()
                }
            }
        }
    }

    public func append(sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        
        statusLock.lock()
        defer { statusLock.unlock() }
        if status.rawValue < Status.recording.rawValue {
            print("Not ready to record yet")
            return
        }
        
        writingQueue.async {
            
            autoreleasepool {
                
                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                self.statusLock.lock()
                if self.status.rawValue > Status.finishingRecordingPart1.rawValue {
                    self.statusLock.unlock()
                    return
                }
                self.statusLock.unlock()

                var err: Error?
                
                if mediaType == kCMMediaType_Video {
                    if self.videoInput == nil {
                        do {
                            try self.setupAssetWriterVideoInput(formatDescription: formatDescription, videoOrientation: self.videoOrientation, settings: self.videoSettings)
                        } catch {
                            err = error
                        }
                    }
                } else if mediaType == kCMMediaType_Audio && self.audioEnabled {
                    if self.audioInput == nil {
                        do {
                            try self.setupAssetWriterAudioInput(formatDescription: formatDescription, settings: self.audioSettings)
                        } catch {
                            err = error
                        }
                    }
                } else {
                    // ignore other meida types
                    return
                }
                                
                if let e = err {
                    self.statusLock.lock()
                    self.transitionToStatus(.failed, error: e)
                    self.statusLock.unlock()
                }

                
                let isAudioReady: Bool = self.audioEnabled ? self.audioInput != nil : true
                
                if err == nil && self.videoInput != nil && isAudioReady {
                    
                    if self.haveStartedSession == false && mediaType == kCMMediaType_Video {
                        
                        if let assetWriter = self.assetWriter {
                            let success = assetWriter.startWriting()
                            if !success {
                                err = assetWriter.error
                            }
                            
                            if let e = err {
                                self.statusLock.lock()
                                self.transitionToStatus(.failed, error: e)
                                self.statusLock.unlock()
                            }
                            
                            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            assetWriter.startSession(atSourceTime: presentationTime)
                            
                            self.videoSampleTime = .zero
                            self.lastVideoSampleTime = presentationTime
                            self.haveStartedSession = true
                        }

                    }
                    
                }
                
                let mediaInput = mediaType == kCMMediaType_Video ? self.videoInput : self.audioInput
                
                if let input = mediaInput, input.isReadyForMoreMediaData, self.haveStartedSession {
                    
                    if mediaType == kCMMediaType_Video {
                        let success = input.append(sampleBuffer)
                        if success {
                            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            self.videoSampleTime = CMTimeAdd(self.videoSampleTime, CMTimeSubtract(presentationTime, self.lastVideoSampleTime))
                            let duration = self.videoSampleTime.seconds
                            self.callbackQueue.async {
                                self.delegate?.movieRecorder(self, didUpdateWithTotalDuration: duration)
                            }
                            self.lastVideoSampleTime = presentationTime
                        }
                        
                    } else if mediaType == kCMMediaType_Audio {
                        self.tryToAppendLastAudioSampleBuffers()
                        self.tryToAppendAudioSampleBuffer(sampleBuffer)
                    }
                    
                } else {
                    print("\(mediaType) input not ready for more media data, dropping buffer")
                }
                
            }
            
        }
        
    }

    /// Asynchronous, might take several hundred milliseconds.
    /// When finished the delegate's recorderDidFinishRecording: or recorder:didFailWithError: method will be called.
    public func finishRecording() {
        statusLock.lock()
        defer { statusLock.unlock() }
        var shouldFinishRecording = false
        switch status {
        case .idle, .preparingToRecord, .finishingRecordingPart1, .finishingRecordingPart2, .finished:
            print("Not recording")
        case .failed:
            // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
            // Because of this we are lenient when finishRecording is called and we are in an error state.
            print("Recording has failed, nothing to do")
        case .cancelled:
            print("Recording has failed, nothing to do")
        case .recording:
            shouldFinishRecording = true
        }
        
        if shouldFinishRecording {
            transitionToStatus(.finishingRecordingPart1, error: nil)
        } else {
            return
        }
        
        writingQueue.async {
            autoreleasepool {
                self.statusLock.lock()
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                if self.status != .finishingRecordingPart1 {
                    self.statusLock.unlock()
                    return
                }
                
                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                self.transitionToStatus(.finishingRecordingPart2, error: nil)
                self.statusLock.unlock()

                self.tryToAppendLastAudioSampleBuffers()
                
                if let assetWriter = self.assetWriter, assetWriter.status == .writing {
                    assetWriter.finishWriting {
                        self.statusLock.lock()
                        if let error = assetWriter.error {
                            self.transitionToStatus(.failed, error: error)
                        } else {
                            self.transitionToStatus(.finished, error: nil)
                        }
                        self.statusLock.unlock()
                    }
                } else {
                    self.statusLock.lock()
                    self.transitionToStatus(.cancelled, error: MovieRecorderError.sessionDidNotStart)
                    self.statusLock.unlock()
                }
            }
        }
        
    }

    /// Asynchronous, might take several hundred milliseconds.
    /// When finished the delegate's movieRecorderDidCancelRecording: method will be called.
    public func cancelRecording() {
        statusLock.lock()
        defer { statusLock.unlock() }
        if status == .recording {
            transitionToStatus(.finishingRecordingPart1, error: nil)
        } else {
            return
        }
        
        writingQueue.async {
            autoreleasepool {
                self.statusLock.lock()
                if self.status == .finishingRecordingPart1 {
                    self.assetWriter?.cancelWriting()
                    self.transitionToStatus(.cancelled, error: nil)
                }
                self.statusLock.unlock()
            }
        }
    }
    
    // MARK: - Internal State Machine
    
    // call with `statusLock`
    private func transitionToStatus(_ newStatus: Status, error: Error?) {
        var shouldNotifyDelegate = false
        
        print("MovieRecorder state transition: \(self.status)->\(newStatus)")
        
        if newStatus != self.status {
            // terminal states
            if newStatus == .finished || newStatus == .failed || newStatus == .cancelled {
                shouldNotifyDelegate = true
                
                // make sure there are no more sample buffers in flight before we tear down the asset writer and inputs
                writingQueue.async {
                    self.teardownAssetWriterAndInputs()
                    if newStatus == .failed {
                        try? FileManager.default.removeItem(at: self.url)
                    }
                }
                
                if let err = error {
                    print("MovieRecorder error: \(err)")
                }
                
            } else if newStatus == .recording {
                shouldNotifyDelegate = true
            }
            
            self.status = newStatus
        }

        if shouldNotifyDelegate {
            callbackQueue.async {
                autoreleasepool {
                    switch newStatus {
                    case .recording:
                        self.delegate?.movieRecorderDidFinishPreparing(self)
                    case .finished:
                        self.delegate?.movieRecorderDidFinishRecording(self)
                    case .failed:
                        if let err = error {
                            self.delegate?.movieRecorder(self, didFailWithError: err)
                        }
                    case .cancelled:
                        self.delegate?.movieRecorderDidCancelRecording(self)
                    default:
                        assertionFailure("Unexpected recording status \(newStatus) for delegate callback")
                        break
                    }
                }
            }
        }
    }
    
    private func teardownAssetWriterAndInputs() {
        videoInput = nil
        audioInput = nil
        assetWriter = nil
        audioSampleBufferQueue.removeAll()
        lastVideoSampleTime = .invalid
        haveStartedSession = false
    }
    
    // MARK: - Setup Asset Writer Inputs
    
    private func setupAssetWriterVideoInput(formatDescription: CMFormatDescription, videoOrientation: Int32, settings: [String: Any]) throws {
        guard let assetWriter = self.assetWriter else {
            throw MovieRecorderError.cannotSetupInput
        }
        
        var videoSettings = settings
        if videoSettings.isEmpty {
            print("No video settings provided, using default settings")
            
            videoSettings = [
                AVVideoCodecKey : AVVideoCodecH264,
                AVVideoWidthKey : 480,
                AVVideoHeightKey : 480,
                AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey : 1 * 1024 * 1024,
                    AVVideoMaxKeyFrameIntervalKey : 30
                ]
            ]
        }
        
        if assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings, sourceFormatHint: formatDescription)
            videoInput.expectsMediaDataInRealTime = true
            
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            let image = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: Int(dimensions.width), height: Int(dimensions.height)))
            
            videoInput.transform = image.orientationTransform(forExifOrientation: videoOrientation)
            
            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
                self.videoInput = videoInput
            } else {
                throw MovieRecorderError.cannotSetupInput
            }
            
        } else {
            throw MovieRecorderError.cannotSetupInput
        }
        
    }
    
    private func setupAssetWriterAudioInput(formatDescription: CMFormatDescription, settings: [String: Any]) throws {
        guard let assetWriter = self.assetWriter else {
            throw MovieRecorderError.cannotSetupInput
        }
        
        var audioSettings = settings
        if audioSettings.isEmpty {
            print("No audio settings provided, using default settings")
            
            audioSettings = [
                AVFormatIDKey : kAudioFormatMPEG4AAC,
                AVEncoderBitRatePerChannelKey : 64 * 1024
            ]
        }
        
        if let currentASBD = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
            audioSettings[AVSampleRateKey] = currentASBD.pointee.mSampleRate
        }
        
        var aclSize: Int = 0
        let currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, sizeOut: &aclSize)
        let currentChannelLayoutData: Data
        if let currentChannelLayout = currentChannelLayout, aclSize > 0 {
            currentChannelLayoutData = Data(bytes: currentChannelLayout, count: aclSize)
        } else {
            currentChannelLayoutData = Data()
        }
        audioSettings[AVChannelLayoutKey] = currentChannelLayoutData
        
        if assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDescription)
            audioInput.expectsMediaDataInRealTime = true
            
            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
                self.audioInput = audioInput
            } else {
                throw MovieRecorderError.cannotSetupInput
            }
            
        } else {
            throw MovieRecorderError.cannotSetupInput
        }

    }
    
    // MARK: - Audio sample buffer queue operations
    // call in _writingQueue
    
    private func tryToAppendLastAudioSampleBuffers() {
        guard self.audioSampleBufferQueue.count > 0 else {
            return
        }
        let array = self.audioSampleBufferQueue
        for i in 0 ..< array.count {
            let audioSampleBuffer = array[i]
            self.audioSampleBufferQueue.remove(at: i)
            self.tryToAppendAudioSampleBuffer(audioSampleBuffer)
        }
    }
    
    private func tryToAppendAudioSampleBuffer(_ audioSampleBuffer: CMSampleBuffer) {
        let duration = CMSampleBufferGetDuration(audioSampleBuffer)
        let presentationTime = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(audioSampleBuffer), duration)
        if CMTimeCompare(presentationTime, self.lastVideoSampleTime) > 0 {
            self.audioSampleBufferQueue.append(audioSampleBuffer)
        } else if let audioInput = self.audioInput {
            if audioInput.isReadyForMoreMediaData {
                let success = audioInput.append(audioSampleBuffer)
                if !success {
                    let error = self.assetWriter?.error
                    statusLock.lock()
                    self.transitionToStatus(.failed, error: error)
                    statusLock.unlock()
                }
            }
        }
    }
    
}
