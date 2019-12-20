import XCTest
@testable import VideoIO
import AVFoundation

final class VideoIOTests: XCTestCase {
    func testAudioVideoSettings() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(VideoIO().text, "Hello, World!")
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

    static var allTests = [
        ("testAudioVideoSettings", testAudioVideoSettings),
    ]
}
