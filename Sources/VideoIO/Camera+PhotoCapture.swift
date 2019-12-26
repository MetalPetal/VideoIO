//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/26.
//

import Foundation
import AVFoundation

@available(OSX 10.15, *)
extension Camera {
    @available(iOS 11.0, *)
    private class PhotoCaptureDelegateHandler: NSObject, AVCapturePhotoCaptureDelegate {
        var willBeginCaptureHandler: ((AVCaptureResolvedPhotoSettings) -> Void)?
        var didFinishProcessingHandler: ((Result<AVCapturePhoto, Swift.Error>) -> Void)?
        func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
            self.willBeginCaptureHandler?(resolvedSettings)
        }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Swift.Error?) {
            if let error = error {
                self.didFinishProcessingHandler?(.failure(error))
            } else {
                self.didFinishProcessingHandler?(.success(photo))
            }
        }
    }
    
    @available(iOS 11.0, *)
    public func capturePhoto(with settings: AVCapturePhotoSettings,
                             willBeginCaptureHandler: ((AVCaptureResolvedPhotoSettings) -> Void)? = nil,
                             didFinishProcessingHandler: @escaping (Result<AVCapturePhoto, Swift.Error>) -> Void) {
        assert(self.photoOutput != nil)
        guard let photoOutput = self.photoOutput else { return }
        let handler = PhotoCaptureDelegateHandler()
        handler.willBeginCaptureHandler = willBeginCaptureHandler
        handler.didFinishProcessingHandler = { [weak self, unowned handler] result in
            didFinishProcessingHandler(result)
            guard let strongSelf = self else { return }
            strongSelf.photoCaptureDelegateHandlers.removeAll(where: { $0 === handler})
        }
        photoOutput.capturePhoto(with: settings, delegate: handler)
        self.photoCaptureDelegateHandlers.append(handler)
    }
    
    public func capturePhoto(with settings: AVCapturePhotoSettings, delegate: AVCapturePhotoCaptureDelegate) {
        assert(self.photoOutput != nil)
        self.photoOutput?.capturePhoto(with: settings, delegate: delegate)
    }
}
