//
//  File.swift
//  
//
//  Created by YuAo on 2021/3/20.
//

import Foundation
import AVFoundation

public final class MovieMerger {
    
    public enum Error: LocalizedError {
        case noAssets
        case cannotCreateExportSession
        case unsupportedFileType
        public var errorDescription: String? {
            switch self {
            case .noAssets:
                return "No assets to merge."
            case .cannotCreateExportSession:
                return "Cannot create export session."
            case .unsupportedFileType:
                return "Unsupported file type."
            }
        }
    }
    
    public static func merge(_ assets: [URL], to url: URL, completion: @escaping (Swift.Error?) -> Void) {
        if assets.isEmpty {
            completion(Error.noAssets)
            return
        }
        let composition = AVMutableComposition()
        var current: CMTime = .zero
        var firstSegmentTransform: CGAffineTransform = .identity
        
        var isFirstSegmentTransformSet = false
        for segment in assets {
            let asset = AVURLAsset(url: segment, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            if !isFirstSegmentTransformSet, let videoTrack = asset.tracks(withMediaType: .video).first {
                firstSegmentTransform = videoTrack.preferredTransform
                isFirstSegmentTransformSet = true
            }
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            do {
                try composition.insertTimeRange(range, of: asset, at: current)
                current = CMTimeAdd(current, asset.duration)
            } catch {
                completion(error)
                return
            }
        }
        
        if isFirstSegmentTransformSet, let videoTrack = composition.tracks(withMediaType: .video).first {
            videoTrack.preferredTransform = firstSegmentTransform
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            completion(Error.cannotCreateExportSession)
            return
        }
        
        guard let fileType = MovieFileType.from(url: url)?.avFileType else {
            completion(Error.unsupportedFileType)
            return
        }
        
        exportSession.outputURL = url
        exportSession.outputFileType = fileType
        exportSession.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .failed:
                if let error = exportSession.error {
                    completion(error)
                } else {
                    assertionFailure()
                }
            case .cancelled:
                assertionFailure()
            case .completed:
                completion(nil)
            default:
                assertionFailure()
            }
        }
    }
}

