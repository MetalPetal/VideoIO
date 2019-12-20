import XCTest
@testable import VideoIO
import AVFoundation

@available(iOS 10.0, *)
final class VideoIOTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(VideoIO().text, "Hello, World!")
        var audioSettings = AudioSettings(formatID: kAudioFormatMPEG4AAC, channels: 2, sampleRate: 44100)
        audioSettings.bitRate = 300
        dump(audioSettings.toDictionary())
        
        if #available(iOS 11.0, *) {
            let videoSettings = VideoSettings.hevc(videoSize: CGSize(width: 1920, height: 1080), averageBitRate: 5000 * 1000)
            dump(videoSettings.toDictionary())
        } else {
            // Fallback on earlier versions
        }
        
        /*
        let player = AVPlayer(url: URL(fileURLWithPath: "/Users/yu.ao/Desktop/WeChatSight240.mp4"))
        let playerOutput = PlayerVideoOutput(player: player, configuration: .default) { frame in
            
        }
        player.play()
        
        while true {
            RunLoop.main.run(until: Date.distantFuture)
        }
        */
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
