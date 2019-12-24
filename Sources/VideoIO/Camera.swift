//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation

@available(iOS 10.0, macOS 10.15, *)
public class Camera: NSObject {
    
    public enum Error: Swift.Error {
        case noDeviceFound
        case cannotAddInput
        case cannotAddOutput
    }
    
    public let captureSession: AVCaptureSession = AVCaptureSession()
        
    public init(captureSessionPreset: AVCaptureSession.Preset, defaultCameraPosition: AVCaptureDevice.Position = .back) {
        super.init()
        assert(self.captureSession.canSetSessionPreset(captureSessionPreset))
        self.captureSession.sessionPreset = captureSessionPreset
        try? self.switchToVideoCaptureDevice(with: defaultCameraPosition)
    }
    
    public var captureSessionIsRunning: Bool {
        return self.captureSession.isRunning
    }
    
    public func startRunningCaptureSession() {
        if !self.captureSession.isRunning {
            self.captureSession.startRunning()
        }
    }
    
    public func stopRunningCaptureSession() {
        if self.captureSession.isRunning {
            self.captureSession.stopRunning()
        }
    }
    
    public private(set) var videoDeviceInput: AVCaptureDeviceInput?
    public private(set) var audioDeviceInput: AVCaptureDeviceInput?
    
    public var videoDevice: AVCaptureDevice? {
        return self.videoDeviceInput?.device
    }
    
    public var audioDevice: AVCaptureDevice? {
        return self.audioDeviceInput?.device
    }
    
    public func switchToVideoCaptureDevice(with position: AVCaptureDevice.Position, preferredDeviceTypes: [AVCaptureDevice.DeviceType] = []) throws {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if preferredDeviceTypes.count == 0 {
            #if os(macOS)
            deviceTypes = [.builtInWideAngleCamera]
            #else
            if #available(iOS 11.1, *) {
                deviceTypes = [.builtInDualCamera, .builtInWideAngleCamera, .builtInTrueDepthCamera]
            } else if #available(iOS 10.2, *) {
                deviceTypes = [.builtInDualCamera, .builtInWideAngleCamera]
            } else {
                deviceTypes = [.builtInWideAngleCamera]
            }
            #endif
        } else {
            deviceTypes = preferredDeviceTypes
        }
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position)
        if let device = discoverySession.devices.first {
            try device.lockForConfiguration()
            
            #if os(iOS)
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            #endif
            
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            #if os(iOS)
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            device.automaticallyAdjustsVideoHDREnabled = true
            #endif
            
            device.unlockForConfiguration()
            
            let newVideoDeviceInput = try AVCaptureDeviceInput(device: device)
            self.captureSession.beginConfiguration()
            if let currentVideoDeviceInput = self.videoDeviceInput {
                self.captureSession.removeInput(currentVideoDeviceInput)
            }
            if self.captureSession.canAddInput(newVideoDeviceInput) {
                self.captureSession.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
            } else {
                throw Error.cannotAddInput
            }
            self.captureSession.commitConfiguration()
            self.updateVideoConnection()
        } else {
            throw Error.noDeviceFound
        }
    }
    
    private func updateVideoConnection() {
        if let videoConnection = self.videoCaptureConnection {
            videoConnection.videoOrientation = .portrait
            if self.videoDevice?.position == .front {
                videoConnection.isVideoMirrored = true
            }
        }
    }
    
    public var videoCaptureConnection: AVCaptureConnection? {
        return self.videoDataOutput?.connection(with: .video)
    }
    
    public private(set) var videoDataOutput: AVCaptureVideoDataOutput?
        
    public func enableVideoDataOutput(on queue: DispatchQueue = .main, delegate: AVCaptureVideoDataOutputSampleBufferDelegate) throws {
        assert(self.videoDataOutput == nil)
        self.captureSession.beginConfiguration()
        if let output = self.videoDataOutput {
            self.captureSession.removeOutput(output)
        }
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(delegate, queue: queue)
        self.videoDataOutput = videoDataOutput
        if self.captureSession.canAddOutput(videoDataOutput) {
            self.captureSession.addOutput(videoDataOutput)
        } else {
            throw Error.cannotAddOutput
        }
        self.updateVideoConnection()
        self.captureSession.commitConfiguration()
    }
    
    public func disableVideoDataOutput() {
        self.captureSession.beginConfiguration()
        if let output = self.videoDataOutput {
            self.captureSession.removeOutput(output)
        }
        self.videoDataOutput = nil
        self.captureSession.commitConfiguration()
    }
    
    public var audioCaptureConnection: AVCaptureConnection? {
        return self.audioDataOutput?.connection(with: .audio)
    }
    
    public private(set) var audioDataOutput: AVCaptureAudioDataOutput?

    public func enableAudioDataOutput(on queue: DispatchQueue = .main, delegate: AVCaptureAudioDataOutputSampleBufferDelegate) throws {
        self.captureSession.beginConfiguration()
        if self.audioDeviceInput == nil {
            if let device = AVCaptureDevice.default(for: .audio), let audioDeviceInput = try? AVCaptureDeviceInput(device: device) {
                if self.captureSession.canAddInput(audioDeviceInput) {
                    self.captureSession.addInput(audioDeviceInput)
                } else {
                    throw Error.cannotAddInput
                }
            } else {
                throw Error.cannotAddInput
            }
        }
        assert(self.audioDataOutput == nil)
        if let audioOutput = self.audioDataOutput {
            self.captureSession.removeOutput(audioOutput)
        }
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(delegate, queue: queue)
        if self.captureSession.canAddOutput(audioDataOutput) {
            self.captureSession.addOutput(audioDataOutput)
        } else {
            throw Error.cannotAddOutput
        }
        self.audioDataOutput = audioDataOutput
        self.captureSession.commitConfiguration()
    }
    
    public func disableAudioDataOutput() {
        self.captureSession.beginConfiguration()
        if let output = self.audioDataOutput {
            self.captureSession.removeOutput(output)
        }
        self.audioDataOutput = nil
        
        if let input = self.audioDeviceInput {
            self.captureSession.removeInput(input)
        }
        self.audioDeviceInput = nil
        self.captureSession.commitConfiguration()
    }
    
    #if os(iOS)
    
    private var audioQueueCaptureSession: AudioQueueCaptureSession?
    
    public func enableAudioQueueCaptureDataOutput(on queue: DispatchQueue = .main, delegate: AudioQueueCaptureSessionDelegate, completion: ((Swift.Error?) -> Void)? = nil) {
        assert(self.audioDataOutput == nil)
        assert(self.audioQueueCaptureSession == nil)
        self.audioQueueCaptureSession = AudioQueueCaptureSession(delegate: delegate, delegateQueue: queue)
        self.audioQueueCaptureSession?.beginAudioRecordingAsynchronously(completion: { error in
            completion?(error)
        })
    }
    
    public func disableAudioQueueCaptureDataOutput() {
        assert(self.audioQueueCaptureSession != nil)
        if let session = self.audioQueueCaptureSession {
            session.stopAudioRecording()
        }
        self.audioQueueCaptureSession = nil
    }
    
    private class MetadataOutputDelegateHandler: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let callback: ([AVMetadataObject]) -> Void
        public init(callback: @escaping ([AVMetadataObject]) -> Void) {
            self.callback = callback
        }
        public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            self.callback(metadataObjects)
        }
    }
    
    public var metadataCaptureConnection: AVCaptureConnection? {
        return self.metadataOutput?.connection(with: .metadata)
    }
    
    public private(set) var metadataOutput: AVCaptureMetadataOutput?
    
    public func enableMetadataOutput(for metadataObjectTypes: [AVMetadataObject.ObjectType], on queue: DispatchQueue = .main, delegate: AVCaptureMetadataOutputObjectsDelegate) throws {
        assert(self.metadataOutput == nil)
        self.captureSession.beginConfiguration()
        if let output = self.metadataOutput {
            self.captureSession.removeOutput(output)
        }
        let output = AVCaptureMetadataOutput()
        output.setMetadataObjectsDelegate(delegate, queue: queue)
        if self.captureSession.canAddOutput(output) {
            self.captureSession.addOutput(output)
        } else {
            throw Error.cannotAddOutput
        }
        output.metadataObjectTypes = metadataObjectTypes
        self.metadataOutput = output
        self.captureSession.commitConfiguration()
    }
    
    public func disableMetadataOutput() {
        self.captureSession.beginConfiguration()
        if let output = self.metadataOutput {
            self.captureSession.removeOutput(output)
        }
        self.metadataOutput = nil
        self.captureSession.commitConfiguration()
    }
    
    #endif
}
