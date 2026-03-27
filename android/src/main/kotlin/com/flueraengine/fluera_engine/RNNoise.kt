package com.flueraengine.fluera_engine

/**
 * 🧠 RNNoise — Neural network noise suppressor.
 *
 * Wraps the xiph/rnnoise C library via JNI.
 * Processes 480-sample frames at 48kHz (10ms windows).
 * Input floats are in [-32768, 32767] range (Short scale).
 *
 * Usage:
 *   val rnnoise = RNNoise()
 *   val frame = FloatArray(RNNoise.FRAME_SIZE)
 *   // fill frame...
 *   val vad = rnnoise.processFrame(frame)  // in-place denoising
 *   rnnoise.destroy()
 */
class RNNoise {

    companion object {
        /** RNNoise frame size: 480 samples @ 48kHz = 10ms */
        const val FRAME_SIZE = 480

        init {
            System.loadLibrary("fluera_rnnoise")
        }

        @JvmStatic
        external fun nativeCreate(): Long

        @JvmStatic
        external fun nativeProcessFrame(state: Long, frame: FloatArray): Float

        @JvmStatic
        external fun nativeDestroy(state: Long)

        @JvmStatic
        external fun nativeGetFrameSize(): Int
    }

    private var state: Long = nativeCreate()

    /**
     * Process a single frame (480 samples) in-place.
     * @param frame Float array of FRAME_SIZE, values in [-32768, 32767]
     * @return VAD probability [0, 1] — how likely the frame contains voice
     */
    fun processFrame(frame: FloatArray): Float {
        if (state == 0L) return 0f
        return nativeProcessFrame(state, frame)
    }

    /**
     * Release native resources. Must be called when done.
     */
    fun destroy() {
        if (state != 0L) {
            nativeDestroy(state)
            state = 0
        }
    }
}
