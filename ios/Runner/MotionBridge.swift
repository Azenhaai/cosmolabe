import CoreMotion
import Flutter
import UIKit

/// Streams device attitude to Dart.
///
/// Core Motion already fuses the gyroscope, accelerometer and magnetometer and
/// hands back an attitude referenced to true north, which is far better than
/// anything assembled from raw sensor streams on the Dart side. The whole
/// point of this file is to get at `xTrueNorthZVertical` and hand it over.
class MotionBridge: NSObject, FlutterStreamHandler {
    static let channelName = "cosmolabe/orientation"

    private let motionManager = CMMotionManager()
    private var eventSink: FlutterEventSink?

    /// Core Motion's true-north frame has X towards north and Z up, which makes
    /// Y point west. The rest of the app works in East-North-Up, so every
    /// sample is rotated a quarter turn about the vertical before it leaves.
    private static let nwuToEnu = (w: (2.0).squareRoot() / 2, x: 0.0, y: 0.0, z: (2.0).squareRoot() / 2)

    static func register(with registrar: FlutterPluginRegistrar) {
        let bridge = MotionBridge()
        let channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        channel.setStreamHandler(bridge)

        let methods = FlutterMethodChannel(
            name: "\(channelName)/control",
            binaryMessenger: registrar.messenger()
        )
        methods.setMethodCallHandler { call, result in
            switch call.method {
            case "isAvailable":
                result(bridge.motionManager.isDeviceMotionAvailable)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        guard motionManager.isDeviceMotionAvailable else {
            return FlutterError(
                code: "unavailable",
                message: "This device has no motion sensors",
                details: nil
            )
        }

        eventSink = events

        // 60 Hz matches the display; asking for more only burns battery.
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self else { return }

            if let error {
                events(FlutterError(
                    code: "motion_failed",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            guard let motion else { return }

            let q = motion.attitude.quaternion
            let rotated = Self.applyFrameCorrection(w: q.w, x: q.x, y: q.y, z: q.z)

            events([
                "w": rotated.w,
                "x": rotated.x,
                "y": rotated.y,
                "z": rotated.z,
                // Core Motion reports calibration state rather than an angle;
                // map it onto the same "how many degrees might this be wrong"
                // scale that Android gives us.
                "accuracy": Self.headingAccuracy(motion.magneticField.accuracy),
                "trueNorth": true,
            ])
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        motionManager.stopDeviceMotionUpdates()
        eventSink = nil
        return nil
    }

    /// Left-multiplies the sample by the north-west-up to east-north-up
    /// rotation.
    private static func applyFrameCorrection(
        w: Double, x: Double, y: Double, z: Double
    ) -> (w: Double, x: Double, y: Double, z: Double) {
        let c = nwuToEnu
        return (
            w: c.w * w - c.x * x - c.y * y - c.z * z,
            x: c.w * x + c.x * w + c.y * z - c.z * y,
            y: c.w * y - c.x * z + c.y * w + c.z * x,
            z: c.w * z + c.x * y - c.y * x + c.z * w
        )
    }

    private static func headingAccuracy(
        _ accuracy: CMMagneticFieldCalibrationAccuracy
    ) -> Double {
        switch accuracy {
        case .high: return 5.0
        case .medium: return 15.0
        case .low: return 35.0
        default: return 180.0
        }
    }
}
