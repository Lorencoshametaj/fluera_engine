package com.nebulaengine.nebula_engine

import android.app.Activity
import android.os.Build
import android.view.Display
import android.view.Surface
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterSurfaceView

/**
 * Manages display refresh rate and forces 120Hz mode for Flutter.
 * 
 * Handles all display mode manipulation logic. Supports both onCreate initialization
 * and post-creation Flutter surface optimization.
 */
class DisplayRefreshRateManager(private val activity: Activity) {
    
    /**
     * Force 120Hz BEFORE Flutter initialization.
     * Must be called before super.onCreate() to ensure Flutter captures the correct rate.
     */
    fun force120HzBeforeFlutterInit() {
        try {
            val layoutParams = activity.window.attributes
            
            layoutParams.preferredRefreshRate = 120.0f
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val display = getDisplay()
                display?.let { d ->
                    val modes = d.supportedModes
                    
                    var bestMode: Display.Mode? = null
                    var highestRate = 0.0f
                    
                    for (mode in modes) {
                        if (mode.refreshRate > highestRate) {
                            highestRate = mode.refreshRate
                            bestMode = mode
                        }
                    }
                    
                    bestMode?.let { mode ->
                        layoutParams.preferredDisplayModeId = mode.modeId
                    }
                }
            }
            
            activity.window.attributes = layoutParams
        } catch (e: Exception) {
            // Silent fail - not critical
        }
    }
    
    /**
     * Apply 120Hz to Flutter surface view after it's created.
     * Handles LTPO/Variable Refresh Rate displays that ignore onCreate settings.
     */
    fun apply120HzToFlutterSurface(flutterSurfaceView: FlutterSurfaceView) {
        try {
            val layoutParams = activity.window.attributes
            layoutParams.preferredRefreshRate = 120.0f
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val display = getDisplay()
                display?.let { d ->
                    d.supportedModes.maxByOrNull { it.refreshRate }?.let { mode ->
                        layoutParams.preferredDisplayModeId = mode.modeId
                    }
                }
            }
            
            activity.window.attributes = layoutParams
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                flutterSurfaceView.holder?.surface?.let { surface ->
                    surface.setFrameRate(120.0f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
                }
            }
        } catch (e: Exception) {
            // Silent fail
        }
    }
    
    /**
     * Get current display refresh rate
     */
    fun getDisplayRefreshRate(): Int {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val display = getDisplay()
                display?.mode?.refreshRate?.toInt() ?: 60
            } else {
                @Suppress("DEPRECATION")
                val display = activity.windowManager.defaultDisplay
                display.refreshRate.toInt()
            }
        } catch (e: Exception) {
            60 // Fallback
        }
    }
    
    /**
     * Set preferred refresh rate (called from Dart)
     */
    fun setPreferredRefreshRate(targetRate: Float) {
        try {
            val layoutParams = activity.window.attributes
            
            layoutParams.preferredRefreshRate = targetRate
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val display = getDisplay()
                display?.let { d ->
                    val modes = d.supportedModes
                    
                    var bestMode: Display.Mode? = null
                    var closestDiff = Float.MAX_VALUE
                    
                    for (mode in modes) {
                        val diff = kotlin.math.abs(mode.refreshRate - targetRate)
                        if (diff < closestDiff) {
                            closestDiff = diff
                            bestMode = mode
                        }
                    }
                    
                    bestMode?.let { mode ->
                        layoutParams.preferredDisplayModeId = mode.modeId
                    }
                }
            }
            
            activity.window.attributes = layoutParams
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    val surfaceView = activity.window.decorView.rootView.findViewTreeSurfaceView()
                    surfaceView?.holder?.surface?.let { surface ->
                        surface.setFrameRate(targetRate, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
                    }
                } catch (e: Exception) {
                    // Ignore
                }
            }
        } catch (e: Exception) {
            // Silent fail
        }
    }
    
    private fun getDisplay(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
    }
    
    private fun android.view.View.findViewTreeSurfaceView(): android.view.SurfaceView? {
        if (this is android.view.SurfaceView) {
            return this
        }
        if (this is android.view.ViewGroup) {
            for (i in 0 until childCount) {
                val found = getChildAt(i).findViewTreeSurfaceView()
                if (found != null) return found
            }
        }
        return null
    }
}
