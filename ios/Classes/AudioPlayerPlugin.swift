import Flutter
import AVFoundation

/// 🎵 AudioPlayerPlugin — Native audio playback for Fluera Engine (iOS).
///
/// Handles playback of recorded audio files using AVAudioPlayer.
///
/// Platform Channel: `flueraengine.audio/player`
/// Event Channel: `flueraengine.audio/player_events`
public class AudioPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var audioPlayer: AVAudioPlayer?
    private var positionTimer: Timer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AudioPlayerPlugin()
        let channel = FlutterMethodChannel(
            name: "flueraengine.audio/player",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "flueraengine.audio/player_events",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
        instance.methodChannel = channel
        instance.eventChannel = eventChannel
    }



    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - MethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            // Configure audio session for playback
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                result(nil)
            } catch {
                result(FlutterError(code: "INIT_FAILED", message: error.localizedDescription, details: nil))
            }

        case "setFilePath":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "path is required", details: nil))
                return
            }
            handleSetFilePath(path, result: result)

        case "play":
            handlePlay(result: result)

        case "pause":
            handlePause(result: result)

        case "stop":
            handleStop(result: result)

        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let positionMs = args["position"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "position is required", details: nil))
                return
            }
            handleSeek(positionMs: positionMs, result: result)

        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "volume is required", details: nil))
                return
            }
            audioPlayer?.volume = Float(volume)
            result(nil)

        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "speed is required", details: nil))
                return
            }
            audioPlayer?.rate = Float(speed)
            result(nil)

        case "getPosition":
            let pos = Int((audioPlayer?.currentTime ?? 0) * 1000)
            result(pos)

        case "getDuration":
            if let player = audioPlayer {
                result(Int(player.duration * 1000))
            } else {
                result(nil)
            }

        case "getState":
            let state: String
            if audioPlayer == nil {
                state = "idle"
            } else if audioPlayer!.isPlaying {
                state = "playing"
            } else {
                state = "paused"
            }
            result(["state": state])

        case "release":
            releasePlayer()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Player Methods

    private func handleSetFilePath(_ path: String, result: @escaping FlutterResult) {
        releasePlayer()

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()

            sendStateEvent("ready")
            if let duration = audioPlayer?.duration {
                sendEvent("duration", data: ["duration": Int(duration * 1000)])
            }
            result(nil)
        } catch {
            result(FlutterError(code: "SET_FILE_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func handlePlay(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NOT_READY", message: "Player not ready", details: nil))
            return
        }
        player.play()
        startPositionUpdates()
        sendStateEvent("playing")
        result(nil)
    }

    private func handlePause(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NOT_READY", message: "Player not ready", details: nil))
            return
        }
        player.pause()
        stopPositionUpdates()
        sendStateEvent("paused")
        result(nil)
    }

    private func handleStop(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(nil)
            return
        }
        player.stop()
        player.currentTime = 0
        stopPositionUpdates()
        sendStateEvent("stopped")
        result(nil)
    }

    private func handleSeek(positionMs: Int, result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NOT_READY", message: "Player not ready", details: nil))
            return
        }
        player.currentTime = Double(positionMs) / 1000.0
        result(nil)
    }

    // MARK: - Position Updates

    private func startPositionUpdates() {
        stopPositionUpdates()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer, player.isPlaying else { return }
            self.sendEvent("position", data: ["position": Int(player.currentTime * 1000)])
        }
    }

    private func stopPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    // MARK: - Event Sending

    private func sendStateEvent(_ state: String) {
        sendEvent("state", data: ["state": state])
    }

    private func sendEvent(_ type: String, data: [String: Any]) {
        var event: [String: Any] = ["event": type]
        for (key, value) in data {
            event[key] = value
        }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    // MARK: - Release

    private func releasePlayer() {
        stopPositionUpdates()
        audioPlayer?.stop()
        audioPlayer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerPlugin: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPositionUpdates()
        sendStateEvent("completed")
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        sendEvent("error", data: ["error": error?.localizedDescription ?? "Decode error"])
    }
}
