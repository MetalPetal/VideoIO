//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation

public protocol VideoCompositorProtocol: AVVideoCompositing {
    associatedtype Instruction: AVVideoCompositionInstructionProtocol
}

public class BlockBasedVideoCompositor: NSObject, VideoCompositorProtocol {
    
    public enum Error: Swift.Error {
        case unsupportedInstruction
    }
    
    public class Instruction: NSObject, AVVideoCompositionInstructionProtocol {
        
        typealias Handler = (_ request: AVAsynchronousVideoCompositionRequest) -> Void
        
        public let timeRange: CMTimeRange
        
        public let enablePostProcessing: Bool = false
        
        public let containsTweening: Bool = true
        
        public let requiredSourceTrackIDs: [NSValue]?
        
        public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
        
        internal let handler: Handler
        
        internal init(handler: @escaping Handler, timeRange: CMTimeRange, requiredSourceTrackIDs: [CMPersistentTrackID] = []) {
            self.handler = handler
            self.timeRange = timeRange
            if requiredSourceTrackIDs.count > 0 {
                self.requiredSourceTrackIDs = requiredSourceTrackIDs.map({ NSNumber(value: $0) })
            } else {
                self.requiredSourceTrackIDs = nil
            }
        }
    }
    
    public let sourcePixelBufferAttributes: [String : Any]? = [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]]
    
    public let requiredPixelBufferAttributesForRenderContext: [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        
    }
    
    public func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? Instruction else {
            assertionFailure()
            asyncVideoCompositionRequest.finish(with: Error.unsupportedInstruction)
            return
        }
        instruction.handler(asyncVideoCompositionRequest)
    }
}

public class VideoComposition<Compositor> where Compositor: VideoCompositorProtocol {
    public let asset: AVAsset
    
    @available(iOS 11.0, macOS 10.13, *)
    public var sourceTrackIDForFrameTiming: CMPersistentTrackID {
        get {
            return self.videoComposition.sourceTrackIDForFrameTiming
        }
        set {
            self.videoComposition.sourceTrackIDForFrameTiming = newValue
        }
    }
    
    public var frameDuration: CMTime {
        get {
            return self.videoComposition.frameDuration
        }
        set {
            return self.videoComposition.frameDuration = newValue
        }
    }
    
    public var renderSize: CGSize {
        get {
            return self.videoComposition.renderSize
        }
        set {
            self.videoComposition.renderSize = newValue
        }
    }
    
    @available(iOS 11, macOS 10.14, *)
    public var renderScale: Float {
        get {
            return self.videoComposition.renderScale
        }
        set {
            self.videoComposition.renderScale = newValue
        }
    }
    
    public var instructions: [Compositor.Instruction] {
        get {
            return self.videoComposition.instructions as! [Compositor.Instruction]
        }
        set {
            self.videoComposition.instructions = newValue
        }
    }
    
    private let videoComposition: AVMutableVideoComposition
    
    public func makeAVVideoComposition() -> AVVideoComposition {
        return self.videoComposition.copy() as! AVVideoComposition
    }
    
    public init(propertiesOf asset: AVAsset) {
        self.asset = asset.copy() as! AVAsset
        self.videoComposition = AVMutableVideoComposition(propertiesOf: self.asset)
        self.videoComposition.customVideoCompositorClass = Compositor.self
        if let presentationVideoSize = self.asset.presentationVideoSize {
            self.renderSize = presentationVideoSize
        }
    }
}

extension VideoComposition where Compositor == BlockBasedVideoCompositor {
    public convenience init(propertiesOf asset: AVAsset, compositionRequestHandler: @escaping (AVAsynchronousVideoCompositionRequest) -> Void) {
        self.init(propertiesOf: asset)
        self.instructions = [.init(handler: compositionRequestHandler, timeRange: CMTimeRange(start: .zero, duration: CMTime(value: CMTimeValue.max, timescale: 48000)))]
    }
}
