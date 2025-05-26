package com.example.dimly

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.dimly/torch"
    private val QUICKSETTINGS_CHANNEL = "com.example.dimly/quicksettings"
    private val BACKGROUND_SERVICE_CHANNEL = "com.example.dimly/background_service"
    private lateinit var cameraManager: CameraManager
    private var cameraId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cameraId = cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        }

        // Torch control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setTorch" -> {
                    val intensity = (call.argument<Double>("intensity") ?: 0.0).toFloat()
                    setTorchWithIntensity(intensity, result)
                }
                else -> result.notImplemented()
            }
        }

        // Quick Settings channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUICKSETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isQuickTileAdded" -> {
                    // For Android, once the service is declared in manifest, it's available
                    // Users need to manually add it to their quick settings
                    result.success(true)
                }
                "addQuickSettingsTile" -> {
                    // On Android, we can't programmatically add tiles
                    // We can only provide instructions to the user
                    result.success(true)
                }
                "removeQuickSettingsTile" -> {
                    // On Android, we can't programmatically remove tiles
                    // We can only provide instructions to the user
                    result.success(true)
                }
                "openQuickSettings" -> {
                    try {
                        // Try to open quick settings panel
                        val intent = Intent("android.settings.panel.action.QUICK_SETTINGS")
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback: open regular settings
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_SETTINGS)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("OPEN_SETTINGS_ERROR", ex.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Background Service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    FlashlightBackgroundService.startService(this)
                    result.success(true)
                }
                "stopBackgroundService" -> {
                    FlashlightBackgroundService.stopService(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntentExtras(intent)
    }

    override fun onResume() {
        super.onResume()
        handleIntentExtras(intent)
    }

    private fun handleIntentExtras(intent: Intent?) {
        if (intent == null) return
        
        // Handle ambient mode activation from quick tile
        if (intent.getBooleanExtra("activate_ambient", false)) {
            // Clear the flag to prevent repeated activation
            intent.removeExtra("activate_ambient")
            
            // Send message to Flutter to activate ambient mode
            try {
                // Ensure Flutter engine is ready before sending message
                if (flutterEngine != null) {
                    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "com.example.dimly/ambient")
                        .invokeMethod("activateAmbientMode", null)
                } else {
                    // If Flutter engine isn't ready, delay the message
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        if (flutterEngine != null) {
                            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "com.example.dimly/ambient")
                                .invokeMethod("activateAmbientMode", null)
                        }
                    }, 500)
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Error activating ambient mode", e)
            }
        }
        
        // Handle SOS activation from quick tile
        if (intent.getBooleanExtra("activate_sos", false)) {
            // Clear the flag to prevent repeated activation
            intent.removeExtra("activate_sos")
            
            // Send message to Flutter to activate SOS mode
            try {
                if (flutterEngine != null) {
                    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "com.example.dimly/sos")
                        .invokeMethod("activateSOSMode", null)
                } else {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        if (flutterEngine != null) {
                            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "com.example.dimly/sos")
                                .invokeMethod("activateSOSMode", null)
                        }
                    }, 500)
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Error activating SOS mode", e)
            }
        }
    }

    private fun setTorchWithIntensity(intensity: Float, result: MethodChannel.Result) {
        try {
            if (cameraId == null) {
                result.error("UNAVAILABLE", "Flash not available", null)
                return
            }

            if (intensity <= 0) {
                cameraManager.setTorchMode(cameraId!!, false)
                result.success(null)
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val characteristics = cameraManager.getCameraCharacteristics(cameraId!!)
                val maxLevel = characteristics.get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL) ?: 1

                if (maxLevel > 1) {
                    val targetLevel = (intensity * maxLevel).toInt().coerceIn(1, maxLevel)
                    cameraManager.turnOnTorchWithStrengthLevel(cameraId!!, targetLevel)
                } else {
                    cameraManager.setTorchMode(cameraId!!, true)
                }
            } else {
                cameraManager.setTorchMode(cameraId!!, true)
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e("TorchError", "Error controlling torch", e)
            result.error("TORCH_ERROR", e.message, null)
        }
    }
}
