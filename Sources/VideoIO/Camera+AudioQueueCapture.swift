//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/26.
//

import Foundation

@available(iOS 10.0, macOS 10.15, *)
@available(tvOS, unavailable)
@available(macOS, unavailable)
@available(macCatalyst 14.0, *)
extension Camera {
    public func enableAudioQueueCaptureDataOutput(on queue: DispatchQueue = .main, delegate: AudioQueueCaptureSessionDelegate) throws {
        assert(self.audioDataOutput == nil)
        assert(self.audioQueueCaptureSession == nil)
        let audioQueueCaptureSession = AudioQueueCaptureSession(delegate: delegate, delegateQueue: queue)
        try audioQueueCaptureSession.beginAudioRecording()
        self.audioQueueCaptureSession = audioQueueCaptureSession
    }
    
    public func enableAudioQueueCaptureDataOutputAsynchronously(on queue: DispatchQueue = .main, delegate: AudioQueueCaptureSessionDelegate, completion: ((Swift.Error?) -> Void)? = nil) {
        assert(self.audioDataOutput == nil)
        assert(self.audioQueueCaptureSession == nil)
        self.audioQueueCaptureSession = AudioQueueCaptureSession(delegate: delegate, delegateQueue: queue)
        self.audioQueueCaptureSession?.beginAudioRecordingAsynchronously(completion: { error in
            completion?(error)
        })
    }
    
    public func disableAudioQueueCaptureDataOutput() {
        if let session = self.audioQueueCaptureSession {
            session.stopAudioRecording()
        }
        self.audioQueueCaptureSession = nil
    }
}
