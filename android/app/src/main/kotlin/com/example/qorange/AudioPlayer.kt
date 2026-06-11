package com.example.qorange


import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.concurrent.thread
import kotlin.math.max

class AudioPlayer(private var sampleRate: Int = 24000) {

    companion object {
        private const val TAG = "AudioPlayer"
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_OUT_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val BUFFER_SIZE_MULTIPLIER = 4
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false
    private var playbackThread: Thread? = null
    private val audioQueue = ConcurrentLinkedQueue<ByteArray>()

    private var minBufferSize = 5
    private var targetBufferSize = 10
    private var maxBufferSize = 20
    private var jitterBufferSize = 3

    private var playbackStarted = false
    private var bufferUnderrunCount = 0
    private var bufferOverrunCount = 0

    private var playbackStartTime = 0L
    private var expectedPlaybackTime = 0L
    private var chunkDurationMs = 0L

    private var chunksReceived = 0
    private var chunksPlayed = 0
    private var jitterCorrections = 0
    private var lastBufferLogTime = 0L

    var onErrorCallback: ((String) -> Unit)? = null

    fun startPlayback(): Boolean {
        return try {
            val bufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                CHANNEL_CONFIG,
                AUDIO_FORMAT
            ) * BUFFER_SIZE_MULTIPLIER

            if (bufferSize == AudioTrack.ERROR || bufferSize == AudioTrack.ERROR_BAD_VALUE) {
                onErrorCallback?.invoke("Invalid buffer size for playback")
                return false
            }

            calculateTimingParameters()

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            val audioFormat = AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setChannelMask(CHANNEL_CONFIG)
                .setEncoding(AUDIO_FORMAT)
                .build()

            audioTrack = AudioTrack(
                audioAttributes,
                audioFormat,
                bufferSize,
                AudioTrack.MODE_STREAM,
                android.media.AudioManager.AUDIO_SESSION_ID_GENERATE
            )

            if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
                onErrorCallback?.invoke("AudioTrack initialization failed")
                return false
            }

            isPlaying = true

            playbackStarted = false
            bufferUnderrunCount = 0
            bufferOverrunCount = 0
            chunksReceived = 0
            chunksPlayed = 0
            jitterCorrections = 0
            lastBufferLogTime = System.currentTimeMillis()

            startPlaybackThread()

            Log.d(TAG, "Buffer-optimized audio playback started with sample rate: $sampleRate")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start playback", e)
            onErrorCallback?.invoke("Failed to start playback: ${e.message}")
            return false
        }
    }

    fun stopPlayback() {
        isPlaying = false
        playbackThread?.interrupt()

        try {
            audioTrack?.stop()
            audioTrack?.release()
            audioTrack = null
            audioQueue.clear()
            Log.d(TAG, "Audio playback stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping playback", e)
        }
    }

    fun queueAudioData(audioData: ByteArray) {
        if (isPlaying) {
            synchronized(audioQueue) {
                if (audioQueue.size >= maxBufferSize) {
                    audioQueue.poll()
                    bufferOverrunCount++
                    Log.d(TAG, "Buffer overflow - dropped oldest chunk")
                }

                audioQueue.offer(audioData)
                chunksReceived++

                val bufferSize = audioQueue.size

                if (!playbackStarted && bufferSize >= minBufferSize) {
                    audioTrack?.play()
                    playbackStarted = true
                    playbackStartTime = System.currentTimeMillis()
                    expectedPlaybackTime = playbackStartTime
                    Log.i(TAG, "AudioTrack started with $bufferSize chunks pre-filled")
                }
            }

            monitorBufferHealth()
        }
    }

    fun updateSampleRate(newSampleRate: Int) {
        if (newSampleRate != sampleRate) {
            Log.d(TAG, "Updating sample rate from $sampleRate to $newSampleRate")
            val wasPlaying = isPlaying

            if (wasPlaying) {
                stopPlayback()
            }

            sampleRate = newSampleRate

            if (wasPlaying) {
                startPlayback()
            }
        }
    }

    private fun startPlaybackThread() {
        playbackThread = thread {
            while (isPlaying && !Thread.currentThread().isInterrupted) {
                try {
                    if (!playbackStarted) {
                        Thread.sleep(10)
                        continue
                    }

                    val audioData = getNextAudioChunk()

                    if (audioData != null) {
                        val currentTime = System.currentTimeMillis()

                        if (currentTime < expectedPlaybackTime) {
                            val sleepTime = expectedPlaybackTime - currentTime
                            if (sleepTime > 0 && sleepTime < 100) {
                                Thread.sleep(sleepTime)
                            }
                        }

                        val bytesWritten = audioTrack?.write(audioData, 0, audioData.size) ?: 0

                        if (bytesWritten < 0) {
                            Log.w(TAG, "AudioTrack write error: $bytesWritten")
                        }

                        expectedPlaybackTime += chunkDurationMs

                        if (currentTime > expectedPlaybackTime + 100) {
                            expectedPlaybackTime = currentTime
                            jitterCorrections++
                            Log.d(TAG, "Corrected playback timing drift")
                        }

                    } else {
                        if (playbackStarted) {
                            Log.w(TAG, "Buffer completely empty - pausing AudioTrack for refill")
                            audioTrack?.pause()
                            playbackStarted = false
                            expectedPlaybackTime = 0L
                        } else {
                            Thread.sleep(20)
                        }
                    }

                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    if (isPlaying) {
                        Log.e(TAG, "Error during audio playback", e)
                        onErrorCallback?.invoke("Playback error: ${e.message}")
                    }
                    break
                }
            }
        }
    }

    private fun calculateTimingParameters() {
        val chunkSamples = 1024
        chunkDurationMs = (chunkSamples * 1000L) / sampleRate

        val targetLatencyMs = 200L
        val chunksForLatency = (targetLatencyMs / chunkDurationMs).toInt()

        minBufferSize = max(3, chunksForLatency / 3)
        targetBufferSize = max(5, chunksForLatency / 2)
        maxBufferSize = max(10, chunksForLatency)

        Log.i(TAG, "Buffer timing: chunk_duration=${chunkDurationMs}ms, target_buffer=$targetBufferSize chunks")
    }

    private fun monitorBufferHealth() {
        val currentTime = System.currentTimeMillis()

        if (currentTime - lastBufferLogTime < 5000) {
            return
        }

        val bufferSize = audioQueue.size
        val bufferHealth = (bufferSize.toFloat() / targetBufferSize) * 100

        val status = when {
            bufferSize < minBufferSize -> "STARVING"
            bufferSize > (maxBufferSize * 0.8).toInt() -> "OVERFLOWING"
            bufferSize >= targetBufferSize -> "HEALTHY"
            else -> "FILLING"
        }

        Log.i(TAG, "Buffer: $bufferSize/$maxBufferSize chunks | Health: ${bufferHealth.toInt()}% | Status: $status | Underruns: $bufferUnderrunCount, Overruns: $bufferOverrunCount")

        lastBufferLogTime = currentTime
    }

    private fun getNextAudioChunk(): ByteArray? {
        synchronized(audioQueue) {
            if (audioQueue.isEmpty()) {
                return null
            }

            val audioData = audioQueue.poll()
            chunksPlayed++

            if (audioQueue.size < minBufferSize) {
                bufferUnderrunCount++
                if (playbackStarted) {
                    Log.w(TAG, "Buffer underrun - only ${audioQueue.size} chunks left")
                }
            }

            return audioData
        }
    }

    fun isPlaying(): Boolean = isPlaying

    fun getQueueSize(): Int = audioQueue.size

    fun clearQueue() {
        audioQueue.clear()
    }

    fun getBufferHealth(): Map<String, Any> {
        return mapOf(
            "bufferSize" to audioQueue.size,
            "targetBufferSize" to targetBufferSize,
            "maxBufferSize" to maxBufferSize,
            "chunksReceived" to chunksReceived,
            "chunksPlayed" to chunksPlayed,
            "bufferUnderruns" to bufferUnderrunCount,
            "bufferOverruns" to bufferOverrunCount,
            "jitterCorrections" to jitterCorrections,
            "playbackStarted" to playbackStarted
        )
    }
}