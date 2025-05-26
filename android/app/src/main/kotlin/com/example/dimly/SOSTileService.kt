package com.example.dimly

import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

class SOSTileService : TileService() {
    private lateinit var cameraManager: CameraManager
    private var cameraId: String? = null
    private var isSOSActive = false

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
        
        if (isLocked) {
            // Use unlockAndRun for locked device
            unlockAndRun {
                openApp()
            }
        } else {
            // Toggle SOS directly
            toggleSOS()
        }
        updateTile()
    }

    private fun openApp() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("activate_sos", true)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("SOSTile", "Error opening app", e)
        }
    }

    private fun toggleSOS() {
        try {
            if (cameraId == null) return
            
            isSOSActive = !isSOSActive
            if (isSOSActive) {
                // Start SOS pattern
                flashSOSPattern()
            }
        } catch (e: Exception) {
            Log.e("SOSTile", "Error toggling SOS", e)
            isSOSActive = false
        }
    }

    private fun flashSOSPattern() {
        Thread {
            try {
                // S (...)
                repeat(3) {
                    if (isSOSActive) {
                        cameraManager.setTorchMode(cameraId!!, true)
                        Thread.sleep(200)
                        cameraManager.setTorchMode(cameraId!!, false)
                        Thread.sleep(200)
                    }
                }
                Thread.sleep(400)
                
                // O (---)
                repeat(3) {
                    if (isSOSActive) {
                        cameraManager.setTorchMode(cameraId!!, true)
                        Thread.sleep(600)
                        cameraManager.setTorchMode(cameraId!!, false)
                        Thread.sleep(200)
                    }
                }
                Thread.sleep(400)
                
                // S (...)
                repeat(3) {
                    if (isSOSActive) {
                        cameraManager.setTorchMode(cameraId!!, true)
                        Thread.sleep(200)
                        cameraManager.setTorchMode(cameraId!!, false)
                        Thread.sleep(200)
                    }
                }
                
                // Reset state after pattern
                isSOSActive = false
                updateTile()
            } catch (e: Exception) {
                Log.e("SOSTile", "Error in SOS pattern", e)
                isSOSActive = false
            }
        }.start()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        
        tile.state = if (isSOSActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "SOS"
        tile.contentDescription = if (isSOSActive) "SOS Active" else "Activate SOS"
        
        try {
            tile.icon = Icon.createWithResource(this, R.drawable.sos_tile_icon)
        } catch (e: Exception) {
            tile.icon = Icon.createWithResource(this, android.R.drawable.ic_dialog_alert)
        }
        tile.updateTile()
    }
}
