package ai.azenha.cosmolabe

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Streams device attitude to Dart.
 *
 * TYPE_ROTATION_VECTOR is the platform's own sensor fusion, already blending
 * gyroscope, accelerometer and magnetometer. Its world frame is exactly the
 * East-North-Up the app works in, so unlike iOS no frame correction is needed
 * here — but it is referenced to *magnetic* north, so the Dart side has to
 * apply the declination itself.
 */
class MotionBridge(context: Context) :
    EventChannel.StreamHandler, SensorEventListener {

    companion object {
        const val CHANNEL_NAME = "cosmolabe/orientation"

        fun register(messenger: BinaryMessenger, context: Context) {
            val bridge = MotionBridge(context)
            EventChannel(messenger, CHANNEL_NAME).setStreamHandler(bridge)
            MethodChannel(messenger, "$CHANNEL_NAME/control")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isAvailable" -> result.success(bridge.isAvailable())
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private var eventSink: EventChannel.EventSink? = null

    /** Reused across every sample; allocating in a 60 Hz callback would hand
     * the garbage collector a steady stream of short-lived arrays. */
    private val quaternion = FloatArray(4)

    private var headingAccuracy = 180.0

    private fun rotationSensor(): Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)

    private fun isAvailable(): Boolean = rotationSensor() != null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events

        val sensor = rotationSensor()
        if (sensor == null) {
            events?.error("unavailable", "This device has no rotation sensor", null)
            return
        }

        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        // The magnetometer's own accuracy arrives separately, through
        // onAccuracyChanged; watch it so the calibration prompt can appear.
        sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        eventSink = null
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val sink = eventSink ?: return
        if (event == null) return
        if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR &&
            event.sensor.type != Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR
        ) {
            return
        }

        // Returns [w, x, y, z] in the East-North-Up world frame.
        SensorManager.getQuaternionFromVector(quaternion, event.values)

        sink.success(
            mapOf(
                "w" to quaternion[0].toDouble(),
                "x" to quaternion[1].toDouble(),
                "y" to quaternion[2].toDouble(),
                "z" to quaternion[3].toDouble(),
                "accuracy" to headingAccuracy,
                // Magnetic north, not true north.
                "trueNorth" to false,
            )
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type != Sensor.TYPE_MAGNETIC_FIELD) return
        headingAccuracy = when (accuracy) {
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 5.0
            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 15.0
            SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 35.0
            else -> 180.0
        }
    }
}
