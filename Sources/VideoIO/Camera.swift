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
    
    public struct Configurator {
        /// Called when video connection estiblished or video device changed. Called before `captureSession.commitConfiguration`.
        public var videoConnectionConfigurator: (Camera, AVCaptureConnection) -> Void
        
        /// Called when a new video device is selected. Called in `device.lockForConfiguration`/`unlockForConfiguration` block.
        public var videoDeviceConfigurator: (Camera, AVCaptureDevice) -> Void
       
        public static let portraitFrontMirroredVideoOutput: Configurator = {
            var configurator = Configurator()
            configurator.videoConnectionConfigurator = { camera, connection in
                connection.videoOrientation = .portrait
                if camera.videoDevice?.position == .front {
                    connection.isVideoMirrored = true
                }
            }
            return configurator
        }()
        
        public init() {
            self.videoDeviceConfigurator = { _,_ in }
            self.videoConnectionConfigurator = { _,_ in }
        }
    }
    
    public let captureSession: AVCaptureSession
    
    public let photoOutput: AVCapturePhotoOutput?
        
    private let configurator: Configurator
    
    private let defaultCameraPosition: AVCaptureDevice.Position
    
    public init(captureSessionPreset: AVCaptureSession.Preset, defaultCameraPosition: AVCaptureDevice.Position = .back, configurator: Configurator = Configurator()) {
        let captureSession = AVCaptureSession()
        assert(captureSession.canSetSessionPreset(captureSessionPreset))
        captureSession.beginConfiguration()
        captureSession.sessionPreset = captureSessionPreset
        let photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            self.photoOutput = photoOutput
        } else {
            self.photoOutput = nil
        }
        captureSession.commitConfiguration()
        self.captureSession = captureSession
        self.configurator = configurator
        self.defaultCameraPosition = defaultCameraPosition
        super.init()
    }
    
    public var captureSessionIsRunning: Bool {
        return self.captureSession.isRunning
    }
    
    /// Start the capture session. Completion handler is called when the session is started, called on main queue.
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
            if #available(iOS 13.0, *) {
                deviceTypes = [.builtInDualWideCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera]
            } else if #available(iOS 11.1, *) {
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
            let newVideoDeviceInput = try AVCaptureDeviceInput(device: device)
            self.captureSession.beginConfiguration()
            if let currentVideoDeviceInput = self.videoDeviceInput {
                self.captureSession.removeInput(currentVideoDeviceInput)
            }
            if self.captureSession.canAddInput(newVideoDeviceInput) {
                self.captureSession.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
            } else {
                self.captureSession.commitConfiguration()
                throw Error.cannotAddInput
            }
                        
            if let connection = self.videoCaptureConnection {
                self.configurator.videoConnectionConfigurator(self, connection)
            }
            self.captureSession.commitConfiguration()
            
            try device.lockForConfiguration()
            self.configurator.videoDeviceConfigurator(self, device)
            device.unlockForConfiguration()
        } else {
            throw Error.noDeviceFound
        }
    }
    
    public var videoCaptureConnection: AVCaptureConnection? {
        return self.videoDataOutput?.connection(with: .video)
    }
    
    public private(set) var videoDataOutput: AVCaptureVideoDataOutput?
        
    public func enableVideoDataOutput(on queue: DispatchQueue = .main, delegate: AVCaptureVideoDataOutputSampleBufferDelegate) throws {
        assert(self.videoDataOutput == nil)
        if self.videoDevice == nil {
            try self.switchToVideoCaptureDevice(with: self.defaultCameraPosition)
        }
        self.captureSession.beginConfiguration()
        defer {
            self.captureSession.commitConfiguration()
        }
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
        
        if let connection = self.videoCaptureConnection {
            self.configurator.videoConnectionConfigurator(self, connection)
        }
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
        defer {
            self.captureSession.commitConfiguration()
        }
        if self.audioDeviceInput == nil {
            if let device = AVCaptureDevice.default(for: .audio), let audioDeviceInput = try? AVCaptureDeviceInput(device: device) {
                if self.captureSession.canAddInput(audioDeviceInput) {
                    self.captureSession.addInput(audioDeviceInput)
                    self.audioDeviceInput = audioDeviceInput
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
        defer {
            self.captureSession.commitConfiguration()
        }
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
    
    @available(iOS 11.0, *)
    public var depthCaptureConnection: AVCaptureConnection? {
        return self.depthDataOutput?.connection(with: .depthData)
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
        if self.videoDevice == nil {
            try self.switchToVideoCaptureDevice(with: self.defaultCameraPosition)
        }
        self.captureSession.beginConfiguration()
        defer {
            self.captureSession.commitConfiguration()
        }
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
        
        if let connection = self.videoCaptureConnection {
            self.configurator.videoConnectionConfigurator(self, connection)
        }
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

