//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation

@available(macOS, unavailable)
public class PlayerVideoOutput: NSObject {
    
    public struct Configuration {
        public var sourcePixelBufferAttributes: [String: Any]?
        public var preferredFramesPerSecond: Int = 30
        public static let `default` = Configuration()
        public init() {
            
        }
    }
    
    public struct VideoFrame {
        public var preferredTrackTransform: CGAffineTransform
        public var presentationTimestamp: CMTime
        public var playerTimestamp: CMTime
        public var pixelBuffer: CVPixelBuffer
    }
    
    public var configuration = Configuration() {
        didSet {
            self.displayLink?.preferredFramesPerSecond = self.configuration.preferredFramesPerSecond
        }
    }
    
    public private(set) var player: AVPlayer? {
        willSet {
            if newValue == self.player {
                return
            }
            self.detachCurrentPlayer()
        }
        didSet {
            if self.player == oldValue {
                return
            }
            self.attachCurrentPlayer()
        }
    }
    
    public func setNeedsUpdate() {
        self.displayLink?.isPaused = false
        self.forceUpdate = true
    }
    
    public func updateIfNeeded() {
        if self.forceUpdate {
            self.update(forced: true)
            self.forceUpdate = false
        }
    }
    
    private var displayLink: CADisplayLink?
    
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemObservation: NSKeyValueObservation?

    private var playerItem: AVPlayerItem?
    private var playerItemOutput: AVPlayerItemVideoOutput?
    
    private let advanceInterval: TimeInterval = 1.0/60.0
    
    private var preferredVideoTransform: CGAffineTransform = .identity
    
    private var forceUpdate: Bool = false
    
    private var handler: (VideoFrame) -> Void
    
    public init(handler: @escaping (VideoFrame) -> Void) {
        self.handler = handler
        super.init()
    }
    
    public init(player: AVPlayer, configuration: Configuration = .default, handler: @escaping (VideoFrame) -> Void) {
        self.configuration = configuration
        self.handler = handler
        self.player = player
        super.init()
        self.attachCurrentPlayer()
    }
    
    private func detachCurrentPlayer() {
        self.updatePlayerItem(nil)
        self.playerItemObservation?.invalidate()
        self.playerItemObservation = nil
    }
    
    private func attachCurrentPlayer() {
        self.playerItemObservation = self.player?.observe(\.currentItem, options: [.initial, .new], changeHandler: { [weak self] (player, change) in
            guard let strongSelf = self, strongSelf.player == player else {
                return
            }
            strongSelf.updatePlayerItem(strongSelf.player?.currentItem)
        })
    }
    
    private func updatePlayerItem(_ playerItem: AVPlayerItem?) {
        self.displayLink?.invalidate()
        self.displayLink = nil
        if let output = self.playerItemOutput, let item = self.playerItem {
            if item.outputs.contains(output) {
                item.remove(output)
            }
        }
        self.playerItemOutput = nil
        self.playerItemStatusObservation?.invalidate()
        self.playerItemStatusObservation = nil
        
        self.playerItem = playerItem
        self.playerItemStatusObservation = self.playerItem?.observe(\.status, options: [.initial,.new], changeHandler: { [weak self] item, change in
            guard let strongSelf = self else {
                return
            }
            if strongSelf.playerItem == item, item.status == .readyToPlay {
                strongSelf.handleReadyToPlay()
            }
        })
    }
    
    private func handleReadyToPlay() {
        guard let _ = self.player, let playerItem = self.playerItem else {
            return
        }
        
        var hasVideoTrack: Bool = false
        for track in playerItem.asset.tracks {
            if track.mediaType == .video {
                hasVideoTrack = true
                self.preferredVideoTransform = track.preferredTransform
                break
            }
        }
        if !hasVideoTrack {
            assertionFailure("No video track found.")
            return
        }
        
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: self.configuration.sourcePixelBufferAttributes)
        output.setDelegate(self, queue: .main)
        playerItem.add(output)
        self.playerItemOutput = output
        
        self.setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        
        if self.playerItemOutput != nil {
            let displayLink = CADisplayLink(target: DisplayLinkTarget({ [weak self] in
                self?.handleUpdate()
            }), selector: #selector(DisplayLinkTarget.handleDisplayLinkUpdate(sender:)))
            displayLink.preferredFramesPerSecond = self.configuration.preferredFramesPerSecond
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }
    
    private func handleUpdate() {
        if let player = self.player, player.rate != 0 {
            self.forceUpdate = true
        }
        self.update(forced: self.forceUpdate)
        self.forceUpdate = false
    }
    
    private func update(forced: Bool) {
        guard let output = self.playerItemOutput, let player = self.player else {
            return
        }
        
        let requestTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if requestTime < .zero {
            return
        }
        
        if !forced && !output.hasNewPixelBuffer(forItemTime: requestTime) {
            self.displayLink?.isPaused = true
            output.requestNotificationOfMediaDataChange(withAdvanceInterval: self.advanceInterval)
            return
        }
        
        var presentationTime: CMTime = .zero
        if let pixelBuffer = output.copyPixelBuffer(forItemTime: requestTime, itemTimeForDisplay: &presentationTime) {
            self.handler(VideoFrame(preferredTrackTransform: self.preferredVideoTransform,
                                    presentationTimestamp: presentationTime,
                                    playerTimestamp: player.currentTime(),
                                    pixelBuffer: pixelBuffer))
        }
    }
    
    private class DisplayLinkTarget {
        private let handler: () -> Void
        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }
        @objc func handleDisplayLinkUpdate(sender: CADisplayLink) {
            self.handler()
        }
    }
}

@available(macOS, unavailable)
extension PlayerVideoOutput: AVPlayerItemOutputPullDelegate {
    public func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        self.displayLink?.isPaused = false
    }
}
