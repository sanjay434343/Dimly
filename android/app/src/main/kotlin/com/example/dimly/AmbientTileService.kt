package com.example.dimly

import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

class AmbientTileService : TileService() {
    private lateinit var cameraManager: CameraManager
    private var cameraId: String? = null
    private var isAmbientActive = false

    override fun onCreate() {
        super.onCreate()
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cameraId = cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        
        // Start background service when tile is used
        FlashlightBackgroundService.startService(this)
        
        // Always try to open the app, regardless of lock state
        openApp()
    }

    private fun openApp() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                       Intent.FLAG_ACTIVITY_CLEAR_TOP or
                       Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("activate_ambient", true)
            }
            
            // Use startActivity instead of startActivityAndCollapse for better compatibility
            startActivity(intent)
            
            // Manually collapse the quick settings panel
            try {
                val statusBarService = getSystemService("statusbar")
                val collapse = statusBarService?.javaClass?.getMethod("collapsePanels")
                collapse?.invoke(statusBarService)
            } catch (e: Exception) {
                // Fallback: just log the error, the activity will still open
                Log.d("AmbientTile", "Could not collapse panels: ${e.message}")
            }
            
        } catch (e: Exception) {
            Log.e("AmbientTile", "Error opening app", e)
        }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        
        tile.state = if (isAmbientActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Ambient"
        tile.contentDescription = "Open Dimly for ambient light control"
        
        try {
            tile.icon = Icon.createWithResource(this, R.drawable.ambient_tile_icon)
        } catch (e: Exception) {
            tile.icon = Icon.createWithResource(this, android.R.drawable.ic_dialog_info)
        }
        tile.updateTile()
    }
}
