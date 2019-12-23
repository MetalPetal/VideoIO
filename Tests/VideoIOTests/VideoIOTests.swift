import XCTest
@testable import VideoIO
import AVFoundation

@available(iOS 10.0, macOS 10.13, *)
final class VideoIOTests: XCTestCase {
    
    let testMovieURL = URL(fileURLWithPath: "\(#file)").deletingLastPathComponent().appendingPathComponent("test.mov")
    
    func testAudioVideoSettings() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        var audioSettings = AudioSettings(formatID: kAudioFormatMPEG4AAC, channels: 2, sampleRate: 44100)
        audioSettings.bitRate = 96000
        XCTAssert(audioSettings.toDictionary() as NSDictionary == [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                   AVNumberOfChannelsKey: 2,
                                                   AVSampleRateKey: 44100,
                                                   AVEncoderBitRateKey: 96000] as NSDictionary)
        
        let videoSettings: VideoSettings = .h264(videoSize: CGSize(width: 1280, height: 720), averageBitRate: 3000000)
        XCTAssert(videoSettings.toDictionary() as NSDictionary == [AVVideoWidthKey: 1280,
                                                                   AVVideoHeightKey: 720,
                                                                   AVVideoCodecKey: "avc1",
                                                                   AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3000000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]] as NSDictionary)
    }
    
    func testVideoExport() {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let asset = AVURLAsset(url: testMovieURL)
        let expectation = XCTestExpectation()
        let exporter = try! AssetExportSession(asset: asset, configuration: AssetExportSession.Configuration(fileType: .mp4, videoSettings: .h264(videoSize: asset.presentationVideoSize!), audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)), outputURL: tempURL)
        exporter.export(progress: nil) { error in
            XCTAssert(error == nil)
            XCTAssert(try! tempURL.resourceValues(forKeys: Set<URLResourceKey>([.fileSizeKey])).fileSize! > 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)
        try? fileManager.removeItem(at: tempURL)
    }

    static var allTests = [
        ("testAudioVideoSettings", testAudioVideoSettings),
        ("testVideoExport", testVideoExport),
    ]
}
