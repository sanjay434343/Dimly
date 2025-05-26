package com.example.dimly

import android.content.Context
import android.content.SharedPreferences
import android.graphics.drawable.Icon
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

class FlashlightTileService : TileService() {
    
    private lateinit var cameraManager: CameraManager
    private var cameraId: String? = null
    private lateinit var prefs: SharedPreferences
    
    // Brightness levels: 25%, 65%, 100%
    private val brightnessLevels = floatArrayOf(0.25f, 0.65f, 1.0f)
    private var currentBrightnessIndex = -1 // -1 means off
    
    override fun onCreate() {
        super.onCreate()
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cameraId = cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        }
        prefs = getSharedPreferences("flashlight_tile", Context.MODE_PRIVATE)
        currentBrightnessIndex = prefs.getInt("brightness_index", -1)
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        
        // Cycle through brightness levels: off -> 25% -> 65% -> 100% -> off
        currentBrightnessIndex = (currentBrightnessIndex + 1) % (brightnessLevels.size + 1)
        if (currentBrightnessIndex >= brightnessLevels.size) {
            currentBrightnessIndex = -1 // Back to off
        }
        
        // Save current state
        prefs.edit().putInt("brightness_index", currentBrightnessIndex).apply()
        
        // Apply the flashlight state
        applyFlashlightState()
        updateTileState()
    }
    
    private fun applyFlashlightState() {
        try {
            if (cameraId == null) return
            
            if (currentBrightnessIndex == -1) {
                // Turn off
                cameraManager.setTorchMode(cameraId!!, false)
            } else {
                // Turn on with specific brightness
                val intensity = brightnessLevels[currentBrightnessIndex]
                
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
            }
        } catch (e: Exception) {
            Log.e("FlashlightTile", "Error controlling flashlight", e)
        }
    }
    
    private fun updateTileState() {
        val tile = qsTile ?: return
        
        when (currentBrightnessIndex) {
            -1 -> {
                // Off state
                tile.state = Tile.STATE_INACTIVE
                tile.label = "Dimly"
                tile.contentDescription = "Flashlight Off"
                tile.icon = Icon.createWithResource(this, R.drawable.dimly_tile_icon)
            }
            0 -> {
                // 25% brightness
                tile.state = Tile.STATE_ACTIVE
                tile.label = "Dimly 25%"
                tile.contentDescription = "Flashlight 25% Brightness"
                tile.icon = Icon.createWithResource(this, R.drawable.dimly_tile_icon)
            }
            1 -> {
                // 65% brightness
                tile.state = Tile.STATE_ACTIVE
                tile.label = "Dimly 65%"
                tile.contentDescription = "Flashlight 65% Brightness"
                tile.icon = Icon.createWithResource(this, R.drawable.dimly_tile_icon)
            }
            2 -> {
                // 100% brightness
                tile.state = Tile.STATE_ACTIVE
                tile.label = "Dimly 100%"
                tile.contentDescription = "Flashlight 100% Brightness"
                tile.icon = Icon.createWithResource(this, R.drawable.dimly_tile_icon)
            }
        }
        
        tile.updateTile()
    }
}
