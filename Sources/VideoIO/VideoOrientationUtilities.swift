//
//  File.swift
//  
//
//  Created by Yu Ao on 2020/1/2.
//

import Foundation
import AVFoundation
import CoreGraphics

public struct VideoOrientationUtilities {
    
    public static func exifOrientationToApply(from captureOrientation: AVCaptureVideoOrientation, to targetOrientation: AVCaptureVideoOrientation, shouldMirror: Bool) -> CGImagePropertyOrientation {
        switch captureOrientation {
        case .landscapeLeft:
            switch targetOrientation {
            case .portrait:
                return shouldMirror ? .leftMirrored : .left
            case .portraitUpsideDown:
                return shouldMirror ? .rightMirrored : .right
            case .landscapeLeft:
                return shouldMirror ? .upMirrored: .up
            case .landscapeRight:
                return shouldMirror ? .downMirrored: .down
            @unknown default:
                fatalError()
            }
        case .landscapeRight:
            switch targetOrientation {
            case .portrait:
                return shouldMirror ? .rightMirrored : .right
            case .portraitUpsideDown:
                return shouldMirror ? .leftMirrored : .left
            case .landscapeLeft:
                return shouldMirror ? .downMirrored: .down
            case .landscapeRight:
                return shouldMirror ? .upMirrored: .up
            @unknown default:
                fatalError()
            }
        case .portrait:
            switch targetOrientation {
            case .portrait:
                return shouldMirror ? .upMirrored : .up
            case .portraitUpsideDown:
                return shouldMirror ? .downMirrored : .down
            case .landscapeLeft:
                return shouldMirror ? .leftMirrored: .left
            case .landscapeRight:
                return shouldMirror ? .rightMirrored: .right
            @unknown default:
                fatalError()
            }
        case .portraitUpsideDown:
            switch targetOrientation {
            case .portrait:
                return shouldMirror ? .downMirrored : .down
            case .portraitUpsideDown:
                return shouldMirror ? .upMirrored : .up
            case .landscapeLeft:
                return shouldMirror ? .rightMirrored: .right
            case .landscapeRight:
                return shouldMirror ? .leftMirrored: .left
            @unknown default:
                fatalError()
            }
        @unknown default:
            fatalError()
        }
    }
}
