//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/23.
//

import Foundation
import AVFoundation

public struct SampleBufferUtilities {
    public static func makeSampleBufferByReplacingImageBuffer(of sampleBuffer: CMSampleBuffer, with imageBuffer: CVImageBuffer) -> CMSampleBuffer? {
        guard let _ = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        var timingInfo = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo) == 0 else {
            return nil
        }
        var outputSampleBuffer: CMSampleBuffer?
        var newFormatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: imageBuffer, formatDescriptionOut: &newFormatDescription)
        guard let formatDescription = newFormatDescription else {
            return nil
        }
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: imageBuffer, formatDescription: formatDescription, sampleTiming: &timingInfo, sampleBufferOut: &outputSampleBuffer)
        guard let buffer = outputSampleBuffer else {
            return nil
        }
        return buffer
    }
}
