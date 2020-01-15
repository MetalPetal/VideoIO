# VideoIO

![](https://github.com/MetalPetal/VideoIO/workflows/Swift/badge.svg)

Video Input/Output Utilities

## VideoComposition

Wraps around `AVMutableVideoComposition` with custom video compositor. A `BlockBasedVideoCompositor` is provided for convenience.

With [MetalPetal](https://github.com/MetalPetal/MetalPetal)

```Swift
let context = try! MTIContext(device: MTLCreateSystemDefaultDevice()!)
let handler = MTIAsyncVideoCompositionRequestHandler(context: context, tracks: asset.tracks(withMediaType: .video)) {   request in
    return FilterGraph.makeImage { output in
        request.anySourceImage => filterA => filterB => output
    }!
}
let composition = VideoComposition(propertiesOf: asset, compositionRequestHandler: handler.handle(request:))
let playerItem = AVPlayerItem(asset: asset)
playerItem.videoComposition = composition.makeAVVideoComposition()
player.replaceCurrentItem(with: playerItem)
player.play()
```

Without MetalPetal

```Swift
let composition = VideoComposition(propertiesOf: asset, compositionRequestHandler: { request in
    //Process video frame
})
let playerItem = AVPlayerItem(asset: asset)
playerItem.videoComposition = composition.makeAVVideoComposition()
player.replaceCurrentItem(with: playerItem)
player.play()
```

## AssetExportSession

Export `AVAsset`s. With the ability to customize video/audio settings as well as `pause` / `resume`.

```Swift
var configuration = AssetExportSession.Configuration(fileType: .mp4, videoSettings: .h264(videoSize: videoComposition.renderSize), audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 128 * 1000))
configuration.metadata = ...
configuration.videoComposition = ...
configuration.audioMix = ...
self.exporter = try! AssetExportSession(asset: asset, outputURL: outputURL, configuration: configuration)
exporter.export(progress: { p in
    
}, completion: { error in
    //Done
})
```

## PlayerVideoOutput

Output video buffers from `AVPlayer`.

```Swift
let player: AVPlayer = ...
let playerOutput = PlayerVideoOutput(player: player) { videoFrame in
    //Got video frame
}
player.play()
```

## MovieRecorder

Record video and audio.

## MovieSegmentsRecorder

Record and merge video segements.

## AudioQueueCaptureSession

Capture audio using `AudioQueue`.

## Camera

Simple audio/video capture.

