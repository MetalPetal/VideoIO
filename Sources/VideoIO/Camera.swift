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
    
    public let captureSession: AVCaptureSession
    
    public let photoOutput: AVCapturePhotoOutput?
        
    public init(captureSessionPreset: AVCaptureSession.Preset, defaultCameraPosition: AVCaptureDevice.Position = .back) {
        let captureSession = AVCaptureSession()
        assert(captureSession.canSetSessionPreset(captureSessionPreset))
        captureSession.sessionPreset = captureSessionPreset
        let photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            self.photoOutput = photoOutput
        } else {
            self.photoOutput = nil
        }
        self.captureSession = captureSession
        super.init()
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
                deviceTypes = [.builtInDualCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera]
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
            if videoConnection.isVideoOrientationSupported && videoConnection.isVideoMirroringSupported {
                videoConnection.videoOrientation = .portrait
                if self.videoDevice?.position == .front {
                    videoConnection.isVideoMirrored = true
                }
            }
        }
        if let depthConnection = self.depthCaptureConnection {
            if depthConnection.isVideoOrientationSupported && depthConnection.isVideoMirroringSupported {
                depthConnection.videoOrientation = .portrait
                if self.videoDevice?.position == .front {
                    depthConnection.isVideoMirrored = true
                }
            }
        }
    }
    
    public var videoCaptureConnection: AVCaptureConnection? {
        return self.videoDataOutput?.connection(with: .video)
    }
    
    public var depthCaptureConnection: AVCaptureConnection? {
        return self.depthDataOutput?.connection(with: .depthData)
    }
    
    public var audioCaptureConnection: AVCaptureConnection? {
        return self.audioDataOutput?.connection(with: .audio)
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
        if self.captureSession.canAddOutput(videoDataOutput) {
            self.captureSession.addOutput(videoDataOutput)
            self.videoDataOutput = videoDataOutput
        } else {
            throw Error.cannotAddOutput
        }
        self.captureSession.commitConfiguration()
        self.updateVideoConnection()
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
            self.audioDataOutput = audioDataOutput
        } else {
            throw Error.cannotAddOutput
        }
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
            self.metadataOutput = output
        } else {
            throw Error.cannotAddOutput
        }
        output.metadataObjectTypes = metadataObjectTypes
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
    
    public var isDepthDataOutputSupported: Bool {
        if #available(iOS 11.0, *) {
            return self.photoOutput?.isDepthDataDeliverySupported ?? false
        } else {
            return false
        }
    }
    
    private var _outputSynchronizer: Any?
    @available(iOS 11.0, *)
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer? {
        get {
            return _outputSynchronizer as? AVCaptureDataOutputSynchronizer
        }
        set {
            _outputSynchronizer = newValue
        }
    }
    
    private var _depthDataOutput: Any?
    @available(iOS 11.0, *)
    public private(set) var depthDataOutput: AVCaptureDepthDataOutput? {
        get {
            return _depthDataOutput as? AVCaptureDepthDataOutput
        }
        set {
            _depthDataOutput = newValue
        }
    }
    
    @available(iOS 11.0, *)
    public func enableSynchronizedVideoAndDepthDataOutput(on queue: DispatchQueue, delegate: AVCaptureDataOutputSynchronizerDelegate) throws {
        assert(self.videoDataOutput == nil)
        assert(self.outputSynchronizer == nil)
        
        self.captureSession.beginConfiguration()
        
        if let output = self.videoDataOutput {
            self.captureSession.removeOutput(output)
        }
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if self.captureSession.canAddOutput(videoDataOutput) {
            self.captureSession.addOutput(videoDataOutput)
            self.videoDataOutput = videoDataOutput
        } else {
            throw Error.cannotAddOutput
        }
        
        let depthDataOutput = AVCaptureDepthDataOutput()
        depthDataOutput.alwaysDiscardsLateDepthData = true
        if self.captureSession.canAddOutput(depthDataOutput) {
            self.captureSession.addOutput(depthDataOutput)
            self.depthDataOutput = depthDataOutput
        } else {
            throw Error.cannotAddOutput
        }
        
        let outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer.setDelegate(delegate, queue: queue)
        self.outputSynchronizer = outputSynchronizer
        
        self.captureSession.commitConfiguration()
        self.updateVideoConnection()
    }
    
    @available(iOS 11.0, *)
    public func disableSynchronizedVideoAndDepthDataOutput() {
        self.captureSession.beginConfiguration()
        
        self.outputSynchronizer = nil
        
        if let output = self.videoDataOutput {
            self.captureSession.removeOutput(output)
        }
        self.videoDataOutput = nil
        
        if let depthOutput = self.depthDataOutput {
            self.captureSession.removeOutput(depthOutput)
        }
        self.depthDataOutput = nil
        
        self.captureSession.commitConfiguration()
    }
    
    #endif
    
    // MARK: - Extension
    
    internal var photoCaptureDelegateHandlers: [AnyObject] = []
    
    @available(macOS, unavailable)
    internal var audioQueueCaptureSession: AudioQueueCaptureSession?
}

