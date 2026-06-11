package com.example.qorange
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlin.math.sqrt

class AudioManager {

    companion object {
        private const val TAG = "AudioManager"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val BUFFER_SIZE_MULTIPLIER = 4
    }

    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var recordingThread: Thread? = null

    private var amplitudeThreshold = 100.0
    private var silenceCounter = 0
    private val silenceLimit = 15

    private var debugMode = false
    private var chunkSize = 1024
    private var processingDelayCount = 0
    private var captureErrors = 0
    private var lastStatsTime = 0L
    private var chunksProcessed = 0

    var onAudioDataCallback: ((ByteArray, Boolean) -> Unit)? = null
    var onErrorCallback: ((String) -> Unit)? = null

    fun startRecording(): Boolean {
        return try {
            val bufferSize = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT
            ) * BUFFER_SIZE_MULTIPLIER

            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                onErrorCallback?.invoke("Invalid buffer size")
                return false
            }

            val audioSource = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                MediaRecorder.AudioSource.VOICE_COMMUNICATION
            } else {
                MediaRecorder.AudioSource.MIC
            }

            Log.i(TAG, "Using audio source: $audioSource")

            audioRecord = AudioRecord(
                audioSource,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                onErrorCallback?.invoke("AudioRecord initialization failed")
                return false
            }

            audioRecord?.startRecording()
            isRecording = true

            processingDelayCount = 0
            captureErrors = 0
            chunksProcessed = 0
            lastStatsTime = System.currentTimeMillis()

            startRecordingThread(bufferSize)

            Log.i(TAG, "AUDIO RECORDING STARTED")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording", e)
            onErrorCallback?.invoke("Failed to start recording: ${e.message}")
            false
        }
    }

    fun stopRecording() {
        isRecording = false
        recordingThread?.interrupt()

        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            Log.d(TAG, "Audio recording stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recording", e)
        }
    }

    private fun startRecordingThread(bufferSize: Int) {
        recordingThread = Thread {
            val buffer = ByteArray(chunkSize * 2)

            while (isRecording && !Thread.currentThread().isInterrupted) {
                try {
                    val startTime = System.currentTimeMillis()

                    val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: 0

                    if (bytesRead > 0) {
                        if (chunksProcessed % 100 == 0) {
                            val state = audioRecord?.state
                            val recordingState = audioRecord?.recordingState
                            Log.i(TAG, "AudioRecord State: $state, Recording: $recordingState")
                        }

                        val hasVoice = if (debugMode) {
                            detectVoiceActivity(buffer, bytesRead)
                            true
                        } else {
                            detectVoiceActivity(buffer, bytesRead)
                        }

                        onAudioDataCallback?.invoke(buffer.copyOf(bytesRead), hasVoice)

                        chunksProcessed++

                        val processingTime = System.currentTimeMillis() - startTime
                        if (processingTime > 10) {
                            processingDelayCount++
                        }

                        monitorCapturePerformance()
                    } else {
                        Log.e(TAG, "AudioRecord.read() returned $bytesRead")
                    }

                } catch (e: Exception) {
                    captureErrors++
                    if (isRecording) {
                        Log.e(TAG, "Error reading audio data", e)
                        onErrorCallback?.invoke("Error reading audio: ${e.message}")
                    }
                    break
                }
            }
        }
        recordingThread?.start()
    }

    private fun detectVoiceActivity(buffer: ByteArray, length: Int): Boolean {
        var sum = 0.0
        var sampleCount = 0
        var maxSample = 0
        var minSample = 0

        for (i in 0 until length step 2) {
            if (i + 1 < length) {
                val sample = (buffer[i + 1].toInt() shl 8) or (buffer[i].toInt() and 0xFF)
                val signedSample = if (sample > 32767) sample - 65536 else sample

                sum += signedSample * signedSample
                sampleCount++

                if (signedSample > maxSample) maxSample = signedSample
                if (signedSample < minSample) minSample = signedSample
            }
        }

        if (sampleCount == 0) {
            Log.w(TAG, "No audio samples in buffer!")
            return false
        }

        val rms = sqrt(sum / sampleCount)

        if (chunksProcessed % 200 == 0) {
            Log.d(TAG, "Audio levels: RMS=${rms.toInt()}, Threshold=${amplitudeThreshold.toInt()}")
        }

        return if (rms > amplitudeThreshold) {
            silenceCounter = 0
            true
        } else {
            silenceCounter++
            silenceCounter < silenceLimit
        }
    }

    fun setAmplitudeThreshold(threshold: Double) {
        amplitudeThreshold = threshold
    }

    private fun monitorCapturePerformance() {
        val currentTime = System.currentTimeMillis()

        if (currentTime - lastStatsTime < 5000) {
            return
        }

        val timeElapsed = (currentTime - lastStatsTime) / 1000.0
        val delaysPerSec = if (timeElapsed > 0) processingDelayCount / timeElapsed else 0.0
        val chunksPerSec = if (timeElapsed > 0) chunksProcessed / timeElapsed else 0.0

        Log.i(TAG, "Capture: ${chunksPerSec.toInt()} chunks/s, ${delaysPerSec.toInt()} delays/s, $captureErrors errors")

        processingDelayCount = 0
        captureErrors = 0
        chunksProcessed = 0
        lastStatsTime = currentTime
    }

    fun isRecording(): Boolean = isRecording

    fun getCaptureMetrics(): Map<String, Any> {
        return mapOf(
            "isRecording" to isRecording,
            "chunksProcessed" to chunksProcessed,
            "processingDelays" to processingDelayCount,
            "captureErrors" to captureErrors,
            "amplitudeThreshold" to amplitudeThreshold,
            "silenceCounter" to silenceCounter
        )
    }

    fun adjustForCarMode(useCarOptimizations: Boolean) {
        if (useCarOptimizations) {
            chunkSize = 2048
            amplitudeThreshold = 150.0
            Log.i(TAG, "CAR MODE: chunk_size=$chunkSize, threshold=$amplitudeThreshold (HIGHLY SENSITIVE)")
        } else {
            chunkSize = 1024
            amplitudeThreshold = 100.0
            Log.i(TAG, "PHONE MODE: chunk_size=$chunkSize, threshold=$amplitudeThreshold (HIGHLY SENSITIVE)")
        }
    }

    fun setDebugMode(enabled: Boolean) {
        debugMode = enabled
    }
}