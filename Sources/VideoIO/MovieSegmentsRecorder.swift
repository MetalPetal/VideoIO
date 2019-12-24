//
//  MovieSegmentsRecorder.swift
//  
//
//  Created by yinglun on 2019/12/20.
//

import Foundation
import AVFoundation

public struct MovieSegment {
    
    public let url: URL
    
    public let duration: TimeInterval
    
    public init(url: URL, duration: TimeInterval) {
        self.url = url
        self.duration = duration
    }
    
}

public protocol MovieSegmentsRecorderDelegate: class {
    
    // for current segment
    
    func segmentsRecorderDidStartRecording(_ recorder: MovieSegmentsRecorder)

    func segmentsRecorderDidCancelRecording(_ recorder: MovieSegmentsRecorder)

    func segmentsRecorder(_ recorder: MovieSegmentsRecorder, didFailWithError error: Error)

    func segmentsRecorderDidStopRecording(_ recorder: MovieSegmentsRecorder)
    
    func segmentsRecorder(_ recorder: MovieSegmentsRecorder, didUpdateWithDuration totalDuration: TimeInterval)
    
    // for segments
    
    func segmentsRecorder(_ recorder: MovieSegmentsRecorder, didUpdateSegments segments: [MovieSegment])

    func segmentsRecorder(_ recorder: MovieSegmentsRecorder, didStopMergingWithURL url: URL)
    
}

public enum MovieSegmentsRecorderError: LocalizedError {
    case noSegments
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .noSegments:
            return "no segments"
        case .cancelled:
            return "cancelled"
        }
    }
}

public final class MovieSegmentsRecorder {
    
    /// internal state machine
    private enum Status: Int, Equatable {
        case idle = 0
        case startingRecording
        case recording
        case stoppingRecording
        case cancelRecording
        case merging
        case deleting
    }
    
    private var status: Status = .idle
    private let statusLock = UnfairLock()
    
    private let mergeQueue = DispatchQueue(label: "org.MetalPetal.VideoIO.SegmentsRecorder")
    
    private var recorder: MovieRecorder?
    private var recordingURL: URL?
    private var mergingURL: URL?
    
    private var segments: [MovieSegment] = []
    
    private weak var delegate: MovieSegmentsRecorderDelegate?
    private let callbackQueue: DispatchQueue

    private let configuration: MovieRecorder.Configuration
    
    public init(configuration: MovieRecorder.Configuration = MovieRecorder.Configuration(), delegate: MovieSegmentsRecorderDelegate, delegateQueue: DispatchQueue = .main) {
        self.configuration = configuration
        self.delegate = delegate
        self.callbackQueue = delegateQueue
    }
    
    // for current segment
    
    public func startRecording() {
        statusLock.lock()
        if status != .idle {
            statusLock.unlock()
            return
        }
        transitionToStatus(.startingRecording, error: nil)
        statusLock.unlock()
        
        let recordingURL = self.generateMovieTempURL()
        self.recordingURL = recordingURL
        
        let recorder = MovieRecorder(url: recordingURL, configuration: self.configuration, delegate: self, delegateQueue: self.mergeQueue)
        self.recorder = recorder
        
        // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
        recorder.prepareToRecord()
    }
    
    public func append(sampleBuffer: CMSampleBuffer) {
        statusLock.lock()
        defer { statusLock.unlock() }
        if status == .recording {
            recorder?.append(sampleBuffer: sampleBuffer)
        }
    }
    
    public func stopRecording() {
        statusLock.lock()
        if status != .recording {
            statusLock.unlock()
            return
        }
        transitionToStatus(.stoppingRecording, error: nil)
        statusLock.unlock()
        
        // asynchronous, will call us back with recorderDidFinishRecording: or recorder:didFailWithError: when done
        recorder?.finishRecording()
    }
    
    public func cancelRecording() {
        statusLock.lock()
        if status != .recording {
            statusLock.unlock()
            return
        }
        transitionToStatus(.cancelRecording, error: nil)
        statusLock.unlock()
        
        recorder?.cancelRecording()
    }
    
    // for segments
    
    public func deleteLastSegment() {
        statusLock.lock()
        if status != .idle {
            statusLock.unlock()
            // busy now
            return
        }
        transitionToStatus(.deleting, error: nil)
        statusLock.unlock()

        mergeQueue.async {
            if self.segments.count > 0 {
                let url = self.segments.last?.url
                self.segments.removeLast()
                
                DispatchQueue.global(qos: .background).async {
                    if let url = url {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            
            let segments = self.segments
            
            self.statusLock.lock()
            self.transitionToStatus(.idle, error: nil)
            self.invokeDelegateCallback {
                self.delegate?.segmentsRecorder(self, didUpdateSegments: segments)
            }
            self.statusLock.unlock()
        }
        
    }
    
    public func deleteAllSegments() {
        statusLock.lock()
        if status != .idle {
            statusLock.unlock()
            // busy now
            return
        }
        transitionToStatus(.deleting, error: nil)
        statusLock.unlock()
        
        mergeQueue.async {
            if self.segments.count > 0 {
                let urls = self.segments.map { $0.url }
                self.segments.removeAll()
                
                DispatchQueue.global(qos: .background).async {
                    for url in urls {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            
            let segments = self.segments
            
            self.statusLock.lock()
            self.transitionToStatus(.idle, error: nil)
            self.invokeDelegateCallback {
                self.delegate?.segmentsRecorder(self, didUpdateSegments: segments)
            }
            self.statusLock.unlock()
        }
    }
    
    public func mergeAllSegments(cleanAfterMerge: Bool = false) {
        statusLock.lock()
        if status != .idle {
            statusLock.unlock()
            // busy now
            return
        }
        transitionToStatus(.merging, error: nil)
        statusLock.unlock()
        
        mergeQueue.async {
            
            self.mergeSavedVideoSegments { [weak self] (r) in
                guard let `self` = self else { return }
                self.statusLock.lock()
                switch r {
                case .success(let mergedURL):
                    self.mergingURL = mergedURL
                    self.transitionToStatus(.idle, error: nil)
                case .failure(let error):
                    self.transitionToStatus(.idle, error: error)
                }
                self.statusLock.unlock()
                
                if cleanAfterMerge {
                    self.deleteAllSegments()
                }
            }
            
        }
    }
    
    private func mergeSavedVideoSegments(completion: @escaping (Result<URL, Error>) -> Void) {
        if segments.isEmpty {
            completion(.failure(MovieSegmentsRecorderError.noSegments))
            return
        }
        
        // prepare compostion and set orientation
        
        let composition = AVMutableComposition()
        var current: CMTime = .zero
        var firstSegmentTransform: CGAffineTransform = .identity
        var isFirstSegmentTransformSetted = false
        for segment in self.segments {
            let asset = AVAsset(url: segment.url)
            if !isFirstSegmentTransformSetted, let videoTrack = asset.tracks(withMediaType: .video).first {
                firstSegmentTransform = videoTrack.preferredTransform
                isFirstSegmentTransformSetted = true
            }
            
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            do {
                try composition.insertTimeRange(range, of: asset, at: current)
                current = CMTimeAdd(current, asset.duration)
            } catch {
                completion(.failure(error))
                return
            }
        }
        
        if isFirstSegmentTransformSetted {
            if let videoTrack = composition.tracks(withMediaType: .video).first {
                videoTrack.preferredTransform = firstSegmentTransform
            }
        }
        
        // export
        let finalMovieTargetURL = self.generateMovieTempURL()
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            return
        }
        exportSession.outputURL = finalMovieTargetURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .failed:
                if let error = exportSession.error {
                    completion(.failure(error))
                }
            case .cancelled:
                completion(.failure(MovieSegmentsRecorderError.cancelled))
            default:
                completion(.success(finalMovieTargetURL))
            }
        }
        
    }
    
    // MARK: - Internal State Machine
    
    // call with `statusLock`
    private func transitionToStatus(_ newStatus: Status, error: Error?) {
        let oldStatus = self.status
        self.status = newStatus
        
        print("SegmentsRecorder recording state transition: \(oldStatus)->\(newStatus)")
        
        guard newStatus != oldStatus else {
            return
        }
        
        var cb: (() -> Void)?
        
        if let err = error, newStatus == .idle {
            cb = { self.delegate?.segmentsRecorder(self, didFailWithError: err) }
        } else {
            if oldStatus == .startingRecording && newStatus == .recording {
                cb = { self.delegate?.segmentsRecorderDidStartRecording(self) }
                
            } else if oldStatus == .stoppingRecording && newStatus == .idle {
                cb = { self.delegate?.segmentsRecorderDidStopRecording(self) }
            
            } else if oldStatus == .cancelRecording && newStatus == .idle {
                cb = { self.delegate?.segmentsRecorderDidCancelRecording(self) }

            } else if oldStatus == .merging && newStatus == .idle {
                if let url = self.mergingURL {
                    cb = { self.delegate?.segmentsRecorder(self, didStopMergingWithURL: url ) }
                } else {
                    assertionFailure()
                }
            }
        }
        
        if let cb = cb {
            self.invokeDelegateCallback(cb)
        }
        
    }
    
    // MARK: - Utilities
    
    private func invokeDelegateCallback(_ cb: @escaping () -> Void) {
        callbackQueue.async {
            autoreleasepool {
                cb()
            }
        }
    }
    
    private func generateMovieTempURL() -> URL {
        return URL(fileURLWithPath: "\(NSTemporaryDirectory())\(Date().timeIntervalSince1970).mp4")
    }
    
}

extension MovieSegmentsRecorder: MovieRecorderDelegate {
    
    public func movieRecorderDidFinishPreparing(_ recorder: MovieRecorder) {
        statusLock.lock()
        if status != .startingRecording {
            print("Expected to be in StartingRecording state")
            statusLock.unlock()
            return
        }
        transitionToStatus(.recording, error: nil)
        statusLock.unlock()
    }

    public func movieRecorderDidCancelRecording(_ recorder: MovieRecorder) {
        statusLock.lock()
        self.recorder = nil
        transitionToStatus(.idle, error: nil)
        statusLock.unlock()
    }

    public func movieRecorder(_ recorder: MovieRecorder, didFailWithError error: Error) {
        statusLock.lock()
        self.recorder = nil
        transitionToStatus(.idle, error: error)
        statusLock.unlock()
    }

    public func movieRecorderDidFinishRecording(_ recorder: MovieRecorder) {
        statusLock.lock()
        defer { statusLock.unlock() }
        if status != .stoppingRecording {
            print("Expected to be in StoppingRecording state")
            return
        }

        // No state transition, we are still in the process of stopping.
        // We will be stopped once we save to the assets library.
        
        guard let url = self.recordingURL, let duration = self.recorder?.duration.seconds else {
            return
        }
        
        let segment = MovieSegment(url: url, duration: duration)
        self.segments.append(segment)
        
        self.recorder = nil
        
        self.transitionToStatus(.idle, error: nil)
        
        let segments = self.segments
        
        self.invokeDelegateCallback {
            self.delegate?.segmentsRecorder(self, didUpdateSegments: segments)
        }
    }
    
    public func movieRecorder(_ recorder: MovieRecorder, didUpdateWithTotalDuration totalDuration: TimeInterval) {
        statusLock.lock()
        if status != .recording {
            statusLock.unlock()
            return
        }
        statusLock.unlock()
        
        self.invokeDelegateCallback {
            self.delegate?.segmentsRecorder(self, didUpdateWithDuration: totalDuration)
        }
    }
    
}
