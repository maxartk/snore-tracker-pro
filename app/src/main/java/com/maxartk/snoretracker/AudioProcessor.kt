package com.maxartk.snoretracker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Process
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.sqrt

data class SnoreState(
    val isRecording: Boolean = false,
    val level: Float = 0f,          // 0-1 adjusted level
    val rawLevel: Float = 0f,       // 0-1 raw level before bg subtraction
    val snoreCount: Int = 0,
    val totalDamage: Int = 0,
    val backgroundLevel: Float = 0f, // 0-1
    val isCalibrating: Boolean = false,
    val calibrationProgress: Float = 0f, // 0-1
    val isCooldown: Boolean = false,
    val error: String? = null,
)

data class SnoreSettings(
    var threshold: Float = 0.04f,
    var pricePerSnore: Int = 100,
    var durationSeconds: Int = 1,
    var gain: Float = 10f,
)

class AudioProcessor(private val context: Context) {

    val _state = MutableStateFlow(SnoreState())
    val state: StateFlow<SnoreState> = _state

    val settings = SnoreSettings()

    private var audioRecord: AudioRecord? = null
    private var recordingJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Snore detection
    private var snoreInProgress = false
    private var snoreStartTime = 0L
    private var inCooldown = false
    private var backgroundLevel = 0f
    private var snoreCount = 0
    private var totalDamage = 0
    private var volumeHistory = mutableListOf<Float>()

    private val calibrationTotal = 80  // ~2 seconds at 50ms per sample
    private var calibrationCount = 0
    private var calibrationSamples = mutableListOf<Float>()

    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun start() {
        if (!hasPermission()) {
            _state.value = _state.value.copy(error = "Немає дозволу на мікрофон")
            return
        }

        try {
            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                _state.value = _state.value.copy(error = "Мікрофон не підтримується")
                return
            }

            // Use 2x buffer for safety
            val actualBufferSize = maxOf(bufferSize, 3200) * 2

            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                audioFormat,
                actualBufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                _state.value = _state.value.copy(error = "Не вдалося ініціалізувати мікрофон")
                audioRecord?.release()
                audioRecord = null
                return
            }

            // Reset state
            snoreCount = 0
            totalDamage = 0
            snoreInProgress = false
            inCooldown = false
            backgroundLevel = 0f
            calibrationCount = 0
            calibrationSamples.clear()
            volumeHistory.clear()

            audioRecord?.startRecording()

            _state.value = _state.value.copy(
                isRecording = true,
                isCalibrating = true,
                calibrationProgress = 0f,
                error = null,
                snoreCount = 0,
                totalDamage = 0,
            )

            recordingJob = scope.launch {
                val buffer = ShortArray(actualBufferSize / 2)
                while (isActive) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: break
                    if (read <= 0) continue

                    processBuffer(buffer, read)
                }
            }

        } catch (e: SecurityException) {
            _state.value = _state.value.copy(error = "Дозвіл на мікрофон відхилено")
        } catch (e: Exception) {
            _state.value = _state.value.copy(error = "Помилка: ${e.message}")
        }
    }

    private fun processBuffer(buffer: ShortArray, read: Int) {
        // Calculate RMS
        var sum = 0L
        for (i in 0 until read) {
            val s = buffer[i].toInt()
            sum += s.toLong() * s.toLong()
        }

        if (read == 0) return

        val rms = sqrt(sum.toDouble() / read)
        val normalizedRms = (rms / 32768.0).toFloat()
        val amplifiedRms = (normalizedRms * settings.gain).coerceIn(0f, 1f)

        // Calibration phase
        if (calibrationCount < calibrationTotal) {
            calibrationSamples.add(amplifiedRms)
            calibrationCount++

            val progress = calibrationCount.toFloat() / calibrationTotal
            _state.value = _state.value.copy(
                isCalibrating = true,
                calibrationProgress = progress,
                rawLevel = amplifiedRms,
            )

            if (calibrationCount == calibrationTotal) {
                // Sort and take bottom 40% as background noise
                calibrationSamples.sort()
                val cutoff = (calibrationSamples.size * 0.4).toInt()
                backgroundLevel = calibrationSamples.subList(0, maxOf(1, cutoff))
                    .average().toFloat()

                _state.value = _state.value.copy(
                    isCalibrating = false,
                    backgroundLevel = backgroundLevel,
                )
            }
            return
        }

        // Normal processing
        val adjustedLevel = (amplifiedRms - backgroundLevel).coerceIn(0f, 1f)

        // Decay when silent
        val displayLevel = if (amplifiedRms < 0.005f) {
            _state.value.level * 0.85f
        } else {
            adjustedLevel
        }

        // Add to history
        volumeHistory.add(displayLevel)
        if (volumeHistory.size > 250) volumeHistory.removeAt(0)

        // Snore detection
        if (!snoreInProgress && !inCooldown && displayLevel > settings.threshold) {
            snoreStartTime = System.currentTimeMillis()
            snoreInProgress = true
        } else if (snoreInProgress) {
            val elapsed = System.currentTimeMillis() - snoreStartTime
            if (elapsed >= settings.durationSeconds * 1000L) {
                completeSnore()
            } else if (displayLevel <= settings.threshold * 0.25f) {
                snoreInProgress = false
            }
        }

        _state.value = _state.value.copy(
            level = displayLevel,
            rawLevel = amplifiedRms,
            snoreCount = snoreCount,
            totalDamage = totalDamage,
            isCooldown = inCooldown,
        )
    }

    private fun completeSnore() {
        snoreCount++
        totalDamage += settings.pricePerSnore
        snoreInProgress = false
        inCooldown = true

        _state.value = _state.value.copy(
            snoreCount = snoreCount,
            totalDamage = totalDamage,
            isCooldown = true,
        )

        scope.launch {
            delay(1500)
            inCooldown = false
            _state.value = _state.value.copy(isCooldown = false)
        }
    }

    fun stop() {
        recordingJob?.cancel()
        recordingJob = null

        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null

        _state.value = _state.value.copy(
            isRecording = false,
            isCalibrating = false,
        )
    }

    fun reset() {
        snoreCount = 0
        totalDamage = 0
        volumeHistory.clear()
        snoreInProgress = false
        inCooldown = false

        _state.value = _state.value.copy(
            snoreCount = 0,
            totalDamage = 0,
            level = 0f,
        )
    }

    fun getVolumeHistory(): List<Float> = volumeHistory.toList()

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun requestStartWithPermission() {
        if (hasPermission()) start()
    }

    fun destroy() {
        stop()
        scope.cancel()
    }
}