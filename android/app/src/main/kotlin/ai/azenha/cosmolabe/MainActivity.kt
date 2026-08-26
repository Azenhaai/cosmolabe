package ai.azenha.cosmolabe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MotionBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
    }
}
