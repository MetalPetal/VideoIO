import AVFoundation
import CoreImage

@available(iOS 11.0, tvOS 10.0, macOS 10.14, *)
public final class MultitrackMovieRecorder {
    
    public enum RecorderError: LocalizedError {
        case cannotSetupVideoInputs
        case cannotSetupAudioInputs
        case unexpectedAssetWriterStatus
        case alreadyStopped
        
        public var errorDescription: String? {
            switch self {
            case .cannotSetupVideoInputs:
                return "Cannot setup video inputs."
            case .cannotSetupAudioInputs:
                return "Cannot setup audio inputs."
            case .unexpectedAssetWriterStatus:
                return "Unexpected asset writer status."
            case .alreadyStopped:
                return "Already stopped."
            }
        }
    }
    
    public enum BufferAppendingError: LocalizedError {
        case invalidBufferCount
        case invalidMediaType
        case differentPresentationTimeStamp
        
        public var errorDescription: String? {
            switch self {
            case .invalidMediaType:
                return "Invalid media type."
            case .invalidBufferCount:
                return "Invalid buffer count."
            case .differentPresentationTimeStamp:
                return "Buffers must have the same PTS."
            }
        }
    }
    
    public enum ConfigurationError: LocalizedError {
        case notSupported
        public var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Configuration not supported, there must be at least one video track."
            }
        }
    }
    
    public struct Configuration {
        public var metadata: [AVMetadataItem] = []
        
        /// Exif Orientation
        public var videoOrientation: Int32 = 0
        
        // You can use VideoSettings/AudioSettings API to create these dictionary.
        public var videoSettings: [String: Any] = [:]
        
        // Audio sample rate and channel layout will be override by the recorder.
        public var audioSettings: [String: Any] = [:]
        
        public var numberOfVideoTracks: Int
        
        public var numberOfAudioTracks: Int
        
        public init(videoTrackCount: Int, audioTrackCount: Int) {
            numberOfVideoTracks = videoTrackCount
            numberOfAudioTracks = audioTrackCount
        }
    }
    
    public let url: URL
    
    private let queue = DispatchQueue(label: "org.metalpetal.videoio.MultitrackMovieRecorder")
    
    private var assetWriter: AVAssetWriter
    private var videoInputs: [AVAssetWriterInput] = []
    private var audioInputs: [AVAssetWriterInput] = []
    
    private struct SampleBufferGroup {
        var sampleBuffers: [CMSampleBuffer]
        var presentationTimeStamp: CMTime
        var duration: CMTime
    }
    
    private var pendingAudioSampleBuffers: [SampleBufferGroup] = []
    
    private var _duration: CMTime = .zero
    public var duration: CMTime {
        self.queue.sync { _duration }
    }
    
    public var sampleWritingSessionStartTime: CMTime? {
        self.queue.sync {
            if recordingStartSampleTime == .invalid {
                return nil
            } else {
                return recordingStartSampleTime
            }
        }
    }
    
    public var sampleWritingSessionStartedHandler: ((_ sampleWritingSessionStartTime: CMTime) -> Void)?
    public var durationChangedHandler: ((_ duration: CMTime) -> Void)?
    
    private var lastVideoSampleTime: CMTime = .invalid
    private var recordingStartSampleTime: CMTime = .invalid
    
    public let configuration: Configuration
    
    private var error: Error?
    private var stopped: Bool = false
    
    public init(url: URL, configuration: Configuration) throws {
        guard configuration.numberOfVideoTracks > 0 && configuration.numberOfAudioTracks >= 0 else {
            throw ConfigurationError.notSupported
        }
        
        self.url = url
        self.configuration = configuration
        
        let fileManager = FileManager()
        try? fileManager.removeItem(at: url)
        self.assetWriter = try AVAssetWriter(url: url, fileType: .mp4)
        self.assetWriter.metadata = self.configuration.metadata
        self.assetWriter.shouldOptimizeForNetworkUse = true
    }
    
    public func appendVideoSampleBuffers(_ sampleBuffers: [CMSampleBuffer]) throws {
        guard sampleBuffers.allSatisfy({ CMSampleBufferGetFormatDescription($0).map({ CMFormatDescriptionGetMediaType($0) }) == kCMMediaType_Video }) else {
            throw BufferAppendingError.invalidMediaType
        }
        guard sampleBuffers.count == self.configuration.numberOfVideoTracks else {
            throw BufferAppendingError.invalidBufferCount
        }
        guard Set(sampleBuffers.map({ CMSampleBufferGetPresentationTimeStamp($0) }).map(\.seconds)).count == 1 else {
            throw BufferAppendingError.differentPresentationTimeStamp
        }
        guard sampleBuffers.count > 0 else {
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffers.first!)
        self.queue.async {
            guard self.stopped == false else {
                return
            }
            
            if self.videoInputs.count == 0 {
                var videoInputs: [AVAssetWriterInput] = []
                do {
                    for sampleBuffer in sampleBuffers {
                        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                            throw RecorderError.cannotSetupVideoInputs
                        }
                        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                        let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
                        let image = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: Int(dimensions.width), height: Int(dimensions.height)))
                        let transform = image.orientationTransform(forExifOrientation: self.configuration.videoOrientation)
                        var videoSettings = self.configuration.videoSettings
                        if videoSettings.isEmpty {
                            videoSettings = VideoSettings.h264(videoSize: size).toDictionary()
                        }
                        if self.assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
                            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings, sourceFormatHint: formatDescription)
                            videoInput.expectsMediaDataInRealTime = true
                            videoInput.transform = transform
                            if self.assetWriter.canAdd(videoInput) {
                                self.assetWriter.add(videoInput)
                                videoInputs.append(videoInput)
                            } else {
                                throw RecorderError.cannotSetupVideoInputs
                            }
                        } else {
                            throw RecorderError.cannotSetupVideoInputs
                        }
                    }
                } catch {
                    self.transitionToFailedStatus(error: error)
                    return
                }
                self.videoInputs = videoInputs
            }
            
            guard self.videoInputs.count == self.configuration.numberOfVideoTracks && self.audioInputs.count == self.configuration.numberOfAudioTracks else {
                return
            }
            
            if self.assetWriter.status == .unknown {
                if !self.assetWriter.startWriting() {
                    if let error = self.assetWriter.error {
                        self.transitionToFailedStatus(error: error)
                        return
                    }
                }
                
                self.assetWriter.startSession(atSourceTime: presentationTime)
                self.recordingStartSampleTime = presentationTime
                self.lastVideoSampleTime = presentationTime
                DispatchQueue.main.async {
                    self.sampleWritingSessionStartedHandler?(presentationTime)
                }
            }
            
            if self.assetWriter.status == .writing {
                if self.videoInputs.map(\.isReadyForMoreMediaData).reduce(true, { $0 && $1 }) {
                    for (index, sampleBuffer) in sampleBuffers.enumerated() {
                        if self.videoInputs[index].append(sampleBuffer) {
                            self.lastVideoSampleTime = presentationTime
                            let startTime = self.recordingStartSampleTime
                            let duration = presentationTime - startTime
                            self._duration = duration
                            DispatchQueue.main.async {
                                self.durationChangedHandler?(duration)
                            }
                        } else {
                            if let error = self.assetWriter.error {
                                self.transitionToFailedStatus(error: error)
                                return
                            }
                        }
                    }
                } else {
                    print("Video inputs: not ready for media data, dropping sample buffer (t: \(presentationTime.seconds)).")
                }
                
            }
        }
    }
    
    public func appendAudioSampleBuffers(_ sampleBuffers: [CMSampleBuffer]) throws {
        guard sampleBuffers.allSatisfy({ CMSampleBufferGetFormatDescription($0).map({ CMFormatDescriptionGetMediaType($0) }) == kCMMediaType_Audio }) else {
            throw BufferAppendingError.invalidMediaType
        }
        guard sampleBuffers.count == self.configuration.numberOfAudioTracks else {
            throw BufferAppendingError.invalidBufferCount
        }
        guard Set(sampleBuffers.map({ CMSampleBufferGetPresentationTimeStamp($0) }).map(\.seconds)).count == 1 else {
            throw BufferAppendingError.differentPresentationTimeStamp
        }
        guard sampleBuffers.count > 0 else {
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffers.first!)
        let duration = CMSampleBufferGetDuration(sampleBuffers.first!)
        self.queue.async {
            guard self.stopped == false else {
                return
            }
            
            if self.audioInputs.count == 0 {
                var audioInputs: [AVAssetWriterInput] = []
                do {
                    for sampleBuffer in sampleBuffers {
                        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                            throw RecorderError.cannotSetupAudioInputs
                        }
                        var audioSettings = self.configuration.audioSettings
                        if audioSettings.isEmpty {
                            audioSettings = [AVFormatIDKey : kAudioFormatMPEG4AAC]
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
                        
                        if self.assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) {
                            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDescription)
                            audioInput.expectsMediaDataInRealTime = true
                            if self.assetWriter.canAdd(audioInput) {
                                self.assetWriter.add(audioInput)
                                audioInputs.append(audioInput)
                            } else {
                                throw RecorderError.cannotSetupAudioInputs
                            }
                        } else {
                            throw RecorderError.cannotSetupAudioInputs
                        }
                    }
                } catch {
                    self.transitionToFailedStatus(error: error)
                    return
                }
                self.audioInputs = audioInputs
            }
            
            guard self.videoInputs.count == self.configuration.numberOfVideoTracks && self.audioInputs.count == self.configuration.numberOfAudioTracks else {
                return
            }
            
            if self.assetWriter.status == .writing {
                do {
                    try self.tryToAppendPendingSampleBuffers()
                    try self.tryToAppendAudioSampleBufferGroup(SampleBufferGroup(sampleBuffers: sampleBuffers, presentationTimeStamp: presentationTime, duration: duration))
                } catch {
                    self.transitionToFailedStatus(error: error)
                }
            }
        }
    }
    
    public func cancelRecording(completion: @escaping () -> Void) {
        self.queue.async {
            if self.stopped {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            self.stopped = true
            self.pendingAudioSampleBuffers = []
            if self.assetWriter.status == .writing {
                self.assetWriter.cancelWriting()
            }
            let fileManager = FileManager()
            try? fileManager.removeItem(at: self.url)
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    public var isStopped: Bool {
        self.queue.sync { self.stopped }
    }
    
    public func stopRecording(completion: @escaping (Error?) -> Void) {
        self.queue.async {
            if self.stopped {
                DispatchQueue.main.async {
                    completion(RecorderError.alreadyStopped)
                }
                return
            }
            
            self.stopped = true
            
            if let error = self.error {
                DispatchQueue.main.async {
                    completion(error)
                }
                return
            }
            
            do {
                try self.tryToAppendPendingSampleBuffers()
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
                return
            }
            
            if self.assetWriter.status == .writing {
                self.assetWriter.finishWriting {
                    if let error = self.assetWriter.error {
                        DispatchQueue.main.async {
                            completion(error)
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                    }
                }
            } else if let error = self.assetWriter.error {
                DispatchQueue.main.async {
                    completion(error)
                }
            } else {
                DispatchQueue.main.async {
                    completion(RecorderError.unexpectedAssetWriterStatus)
                }
            }
        }
    }
    
    private func tryToAppendPendingSampleBuffers() throws {
        dispatchPrecondition(condition: .onQueue(self.queue))
        guard self.pendingAudioSampleBuffers.count > 0 else {
            return
        }
        let pendingAudioSampleBuffers = self.pendingAudioSampleBuffers
        for sampleBufferGroup in pendingAudioSampleBuffers {
            self.pendingAudioSampleBuffers.remove(at: 0)
            try self.tryToAppendAudioSampleBufferGroup(sampleBufferGroup)
        }
    }
    
    private func tryToAppendAudioSampleBufferGroup(_ group: SampleBufferGroup) throws {
        dispatchPrecondition(condition: .onQueue(self.queue))
        let duration = group.duration
        let presentationTime = CMTimeAdd(group.presentationTimeStamp, duration)
        if CMTimeCompare(presentationTime, self.lastVideoSampleTime) > 0 {
            self.pendingAudioSampleBuffers.append(group)
        } else {
            if self.audioInputs.map(\.isReadyForMoreMediaData).reduce(true, { $0 && $1 }) {
                for (index, audioInput) in self.audioInputs.enumerated() {
                    if !audioInput.append(group.sampleBuffers[index]) {
                        if let error = self.assetWriter.error {
                            throw error
                        }
                    }
                }
            } else {
                print("Audio inputs: not ready for media data, dropping sample buffer (t: \(presentationTime.seconds)).")
            }
        }
    }
    
    private func transitionToFailedStatus(error: Error) {
        dispatchPrecondition(condition: .onQueue(self.queue))
        self.error = error
    }
}
