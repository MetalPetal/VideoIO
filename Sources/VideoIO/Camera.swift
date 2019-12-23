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
    
    private class SampleBufferOutputDelegateHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
        
        private let bufferOutputCallback: (CMSampleBuffer) -> Void
        private let bufferDroppedCallback: ((CMSampleBuffer) -> Void)?
        
        public init(bufferOutputCallback: @escaping (CMSampleBuffer) -> Void, bufferDroppedCallback: ((CMSampleBuffer) -> Void)? = nil){
            self.bufferOutputCallback = bufferOutputCallback
            self.bufferDroppedCallback = bufferDroppedCallback
        }
        
        public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            self.bufferDroppedCallback?(sampleBuffer)
        }
        
        public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            self.bufferOutputCallback(sampleBuffer)
        }
        
        public static func bufferOutputCallback(_ callback: @escaping (CMSampleBuffer) -> Void) -> SampleBufferOutputDelegateHandler {
            return SampleBufferOutputDelegateHandler(bufferOutputCallback: callback)
        }
    }
    
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
    
    private var videoDataHandler: SampleBufferOutputDelegateHandler?
    
    public func enableVideoDataOutput(on queue: DispatchQueue = .main, bufferOutputCallback: @escaping (CMSampleBuffer) -> Void, bufferDroppedCallback: ((CMSampleBuffer) -> Void)?) throws {
        assert(self.videoDataOutput == nil)
        let handler = SampleBufferOutputDelegateHandler(bufferOutputCallback: bufferOutputCallback, bufferDroppedCallback: bufferDroppedCallback)
        self.videoDataHandler = handler
        self.captureSession.beginConfiguration()
        if let output = self.videoDataOutput {
            self.captureSession.removeOutput(output)
        }
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(handler, queue: queue)
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
        self.videoDataHandler = nil
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
    
    private var audioDataHandler: SampleBufferOutputDelegateHandler?

    public func enableAudioDataOutput(on queue: DispatchQueue = .main, bufferOutputCallback: @escaping (CMSampleBuffer) -> Void, bufferDroppedCallback: ((CMSampleBuffer) -> Void)?) throws {
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
        let handler = SampleBufferOutputDelegateHandler(bufferOutputCallback: bufferOutputCallback, bufferDroppedCallback: bufferDroppedCallback)
        assert(self.audioDataOutput == nil)
        self.audioDataHandler = handler
        if let audioOutput = self.audioDataOutput {
            self.captureSession.removeOutput(audioOutput)
        }
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(handler, queue: queue)
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
        self.audioDataHandler = nil
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
    
    private var metadataOutputDelegateHandler: MetadataOutputDelegateHandler?
    
    public func enableMetadataOutput(for metadataObjectTypes: [AVMetadataObject.ObjectType], on queue: DispatchQueue = .main, callback: @escaping ([AVMetadataObject]) -> Void) throws {
        assert(self.metadataOutput == nil)
        let handler = MetadataOutputDelegateHandler(callback: callback)
        self.metadataOutputDelegateHandler = handler
        self.captureSession.beginConfiguration()
        if let output = self.metadataOutput {
            self.captureSession.removeOutput(output)
        }
        let output = AVCaptureMetadataOutput()
        output.setMetadataObjectsDelegate(handler, queue: queue)
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
        self.metadataOutputDelegateHandler = nil
        self.captureSession.beginConfiguration()
        if let output = self.metadataOutput {
            self.captureSession.removeOutput(output)
        }
        self.metadataOutput = nil
        self.captureSession.commitConfiguration()
    }
    
    #endif
}
