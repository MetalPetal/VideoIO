//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/19.
//

import Foundation
import AVFoundation

extension AVAsset {
    public var presentationVideoSize: CGSize? {
        if let videoTrack = self.tracks(withMediaType: AVMediaType.video).first {
            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        }
        return nil
    }
    public var naturalVideoSize: CGSize? {
        if let videoTrack = self.tracks(withMediaType: AVMediaType.video).first {
            return videoTrack.naturalSize
        }
        return nil
    }
}
