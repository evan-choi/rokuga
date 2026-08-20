import AVFoundation
import XCTest
@testable import EncoderKit

final class AudioMixerTests: XCTestCase {
    private func makeBuffer(frames: Int, value: Float, format: AVAudioFormat = AudioMixer.canonicalFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0 ..< Int(format.channelCount) {
            let data = buffer.floatChannelData![channel]
            for index in 0 ..< frames {
                data[index] = value
            }
        }
        return buffer
    }

    func testSystemPassthroughWithoutMic() {
        let mixer = AudioMixer()
        let system = makeBuffer(frames: 480, value: 0.25)
        let mixed = mixer.mix(system: system)
        XCTAssertEqual(mixed?.floatChannelData?[0][100], 0.25)
    }

    func testMicIsSummedIntoSystem() throws {
        let mixer = AudioMixer()
        mixer.enqueueMicrophone(makeBuffer(frames: 480, value: 0.3))
        let mixed = mixer.mix(system: makeBuffer(frames: 480, value: 0.25))
        XCTAssertEqual(try XCTUnwrap(mixed?.floatChannelData?[0][0]), 0.55, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mixed?.floatChannelData?[1][479]), 0.55, accuracy: 0.0001)
    }

    func testMixClampsToUnity() {
        let mixer = AudioMixer()
        mixer.enqueueMicrophone(makeBuffer(frames: 480, value: 0.9))
        let mixed = mixer.mix(system: makeBuffer(frames: 480, value: 0.8))
        XCTAssertEqual(mixed?.floatChannelData?[0][0], 1.0)
    }

    func testShortMicFIFOOnlyCoversAvailableSamples() throws {
        let mixer = AudioMixer()
        mixer.enqueueMicrophone(makeBuffer(frames: 100, value: 0.5))
        let mixed = mixer.mix(system: makeBuffer(frames: 480, value: 0.1))
        XCTAssertEqual(try XCTUnwrap(mixed?.floatChannelData?[0][50]), 0.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mixed?.floatChannelData?[0][200]), 0.1, accuracy: 0.0001)
    }

    func testMonoMicUpmixedToStereo() throws {
        let monoFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false))
        let mixer = AudioMixer()
        mixer.enqueueMicrophone(makeBuffer(frames: 480, value: 0.2, format: monoFormat))
        let mixed = mixer.mix(system: makeBuffer(frames: 480, value: 0.1))
        XCTAssertEqual(try XCTUnwrap(mixed?.floatChannelData?[0][0]), 0.3, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(mixed?.floatChannelData?[1][0]), 0.3, accuracy: 0.01)
    }
}
