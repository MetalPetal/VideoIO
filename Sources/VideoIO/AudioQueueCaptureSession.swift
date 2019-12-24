//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/24.
//

import Foundation
import AVFoundation

@available(macOS, unavailable)
public protocol AudioQueueCaptureSessionDelegate: class {
    func audioQueueCaptureSession(_ session: AudioQueueCaptureSession, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
}

@available(macOS, unavailable)
public class AudioQueueCaptureSession {
    
    public enum Error: Swift.Error {
        case noInputAvailable
        case cannotCreateAudioQueue
        case cannotGetAudioQueueProperty
        case cannotCreateAudioFormatDescription
        case cannotStartAudioQueue
        case cannotGetTimebaseInfo
    }
    
    private struct Constants {
        static let numberOfBuffersInQueue = 30
        static let maximumInflightBuffers = 15
    }
    
    private class LifetimeTracker {
        private let callback: () -> Void
        init(callback: @escaping () -> Void) {
            self.callback = callback
        }
        deinit {
            self.callback()
        }
        
        private struct Key {
            static var tracker = ""
        }
        
        static func attach(to: AnyObject, callback: @escaping () -> Void) {
            let tracker = LifetimeTracker(callback: callback)
            objc_setAssociatedObject(to, &Key.tracker, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private let inflightBufferCountLock = UnfairLock()
    private var inflightBufferCount = 0
    
    private let queue: DispatchQueue = DispatchQueue(label: "org.MetalPetal.VideoIO.AudioQueueCaptureSession")
    
    private var audioQueue: AudioQueueRef?
    
    private var buffers = [AudioQueueBufferRef?](repeating: nil, count: Constants.numberOfBuffersInQueue)
    
    private var audioFormatDescription: CMAudioFormatDescription?

    public let sampleRate: Double
    
    private weak var delegate: AudioQueueCaptureSessionDelegate?
    private let delegateQueue: DispatchQueue
    
    public init(sampleRate: Double = 44100, delegate: AudioQueueCaptureSessionDelegate, delegateQueue: DispatchQueue = .main) {
        self.sampleRate = sampleRate
        self.delegate = delegate
        self.delegateQueue = delegateQueue
    }
    
    deinit {
        self.stopAudioRecording()
    }
    
    private static func bufferSize(format: AudioStreamBasicDescription, audioQueue: AudioQueueRef, duration: TimeInterval) throws -> Int {
        let frames = Int(ceil(duration * format.mSampleRate))
        if format.mBytesPerFrame > 0 {
            return frames * Int(format.mBytesPerFrame)
        } else {
            var maxPacketSize: UInt32 = 0
            if format.mBytesPerPacket > 0 {
                maxPacketSize = format.mBytesPerPacket
            } else {
                var propertySize: UInt32 = UInt32(MemoryLayout.size(ofValue: maxPacketSize))
                if AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &propertySize) != 0 {
                    throw Error.cannotGetAudioQueueProperty
                }
            }
            var packets: Int = 0
            if format.mFramesPerPacket > 0 {
                packets = frames / Int(format.mFramesPerPacket)
            } else {
                packets = frames
            }
            if (packets == 0) {
                packets = 1
            }
            return packets * Int(maxPacketSize)
        }
    }
    
    public func beginAudioRecording() throws {
        try self.queue.sync {
            self._stopAudioRecording()
            do {
                try self._beginAudioRecording()
            } catch {
                self._stopAudioRecording()
                throw error
            }
        }
    }
    
    public func beginAudioRecordingAsynchronously(completion: @escaping (Swift.Error?) -> Void) {
        self.queue.async {
            do {
                self._stopAudioRecording()
                try self._beginAudioRecording()
                self.delegateQueue.async {
                    completion(nil)
                }
            } catch {
                self._stopAudioRecording()
                self.delegateQueue.async {
                    completion(error)
                }
            }
        }
    }
    
    private func _beginAudioRecording() throws {
        if AVAudioSession.sharedInstance().isInputAvailable {
            var recordFormat = AudioStreamBasicDescription()
            recordFormat.mSampleRate = sampleRate
            recordFormat.mChannelsPerFrame = UInt32(AVAudioSession.sharedInstance().inputNumberOfChannels)
            recordFormat.mFormatID = kAudioFormatLinearPCM
            recordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
            recordFormat.mBitsPerChannel = 16
            recordFormat.mBytesPerPacket = (recordFormat.mBitsPerChannel / 8) * recordFormat.mChannelsPerFrame
            recordFormat.mBytesPerFrame = recordFormat.mBytesPerPacket
            recordFormat.mFramesPerPacket = 1
            
            let timebaseInfo: mach_timebase_info_data_t = try {
                var info = mach_timebase_info()
                if mach_timebase_info(&info) != KERN_SUCCESS {
                    throw Error.cannotGetTimebaseInfo
                }
                return info
            }()
            
            var audioQueue: AudioQueueRef!
            let status = AudioQueueNewInputWithDispatchQueue(&audioQueue, &recordFormat, 0, self.queue) { [weak self] (inAudioQueue, bufferRef, startTime, inNumPackets, inPacketDesc) in
                guard let strongSelf = self else { return }
                if inNumPackets > 0 {
                    let t = Double(startTime.pointee.mHostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom) / Double(NSEC_PER_SEC)
                    let pts = CMTime(seconds: t, preferredTimescale: CMTimeScale(strongSelf.sampleRate))
                    var dataBuffer: CMBlockBuffer?
                    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: Int(bufferRef.pointee.mAudioDataByteSize), blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: Int(bufferRef.pointee.mAudioDataByteSize), flags: 0, blockBufferOut: &dataBuffer)
                    if let dataBuffer = dataBuffer, let formatDesc = strongSelf.audioFormatDescription {
                        CMBlockBufferReplaceDataBytes(with: bufferRef.pointee.mAudioData, blockBuffer: dataBuffer, offsetIntoDestination: 0, dataLength: Int(bufferRef.pointee.mAudioDataByteSize))
                        var sampleBuffer: CMSampleBuffer?
                        CMAudioSampleBufferCreateWithPacketDescriptions(allocator: nil, dataBuffer: dataBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDesc, sampleCount: CMItemCount(inNumPackets), presentationTimeStamp: pts, packetDescriptions: inPacketDesc, sampleBufferOut: &sampleBuffer)
                        if let sampleBuffer = sampleBuffer {
                            //callback
                            strongSelf.inflightBufferCountLock.lock()
                            if strongSelf.inflightBufferCount < Constants.maximumInflightBuffers {
                                strongSelf.inflightBufferCount += 1
                                strongSelf.inflightBufferCountLock.unlock()
                                
                                LifetimeTracker.attach(to: dataBuffer) { [weak self] in
                                    guard let strongSelf = self else {
                                        return
                                    }
                                    strongSelf.inflightBufferCountLock.lock()
                                    defer { strongSelf.inflightBufferCountLock.unlock() }
                                    strongSelf.inflightBufferCount -= 1
                                }
                                
                                strongSelf.delegateQueue.async {
                                    strongSelf.delegate?.audioQueueCaptureSession(strongSelf, didOutputSampleBuffer: sampleBuffer)
                                }
                            } else {
                                strongSelf.inflightBufferCountLock.unlock()
                                print("\(strongSelf): Buffer dropped due to too many inflight buffer.")
                            }
                        }
                    }
                }
                AudioQueueEnqueueBuffer(inAudioQueue, bufferRef, 0, nil)
            }
            
            if status != 0 {
                throw Error.cannotCreateAudioQueue
            }
            
            let bufferByteSize = try AudioQueueCaptureSession.bufferSize(format: recordFormat, audioQueue: audioQueue, duration: 0.1)
            
            for i in 0 ..< Constants.numberOfBuffersInQueue {
                AudioQueueAllocateBuffer(audioQueue, UInt32(bufferByteSize), &self.buffers[i])
                if let bufferRef = self.buffers[i] {
                    AudioQueueEnqueueBuffer(audioQueue, bufferRef, 0, nil)
                }
            }
            
            var size = UInt32(MemoryLayout.size(ofValue: recordFormat))
            if AudioQueueGetProperty(audioQueue, kAudioQueueProperty_StreamDescription, &recordFormat, &size) != 0 {
                throw Error.cannotGetAudioQueueProperty
            }
            
            var acl = AudioChannelLayout()
            acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
            if CMAudioFormatDescriptionCreate(allocator: nil, asbd: &recordFormat, layoutSize: MemoryLayout.size(ofValue: acl), layout: &acl, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &self.audioFormatDescription) != 0 {
                throw Error.cannotCreateAudioFormatDescription
            }
            
            if AudioQueueStart(audioQueue, nil) != 0 {
                throw Error.cannotStartAudioQueue
            }
        } else {
            throw Error.noInputAvailable
        }
    }
    
    public func stopAudioRecording() {
        self.queue.sync {
            self._stopAudioRecording()
        }
    }
    
    private func _stopAudioRecording() {
        if let audioQueue = self.audioQueue {
            AudioQueueStop(audioQueue, true)
            AudioQueueDispose(audioQueue, true)
            for i in 0 ..< Constants.numberOfBuffersInQueue {
                self.buffers[i] = nil
            }
            self.audioQueue = nil
        }
        self.audioFormatDescription = nil
    }
    
}
