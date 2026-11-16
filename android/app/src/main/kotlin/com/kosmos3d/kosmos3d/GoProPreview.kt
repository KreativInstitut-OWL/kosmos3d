package com.kosmos3d.kosmos3d

import android.content.Context
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.UdpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import android.util.Log
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.extractor.ts.TsPayloadReader
import android.util.SparseArray
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

@UnstableApi
class GoProPreviewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        GoProPreview(context, viewId, messenger)
}

@UnstableApi
private class GoProPreview(context: Context, id: Int, messenger: BinaryMessenger) : PlatformView {
    private val channel = MethodChannel(messenger, "kosmos/preview/$id")
    private var firstFrame = false
    private var failure: String? = null
    private var retries = 0
    private val player = ExoPlayer.Builder(context)
        // Live UDP: keep loading regardless of the (unreliable) buffered
        // duration, start playback on the first decodable frame.
        .setLoadControl(DefaultLoadControl.Builder()
            // min = max = 60 s: the loader never pauses (GoPro TS timestamps
            // make the buffered duration look full); a real-time UDP source
            // cannot run ahead anyway. Play as soon as 200 ms are decodable.
            .setBufferDurationsMs(60_000, 60_000, 200, 200)
            .setTargetBufferBytes(64 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(false)
            .build())
        .build()
    private val playerView = PlayerView(context).apply {
        useController = false
        keepScreenOn = true
        player = this@GoProPreview.player
    }
    init {
        player.volume = 0f
        player.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() { firstFrame = true; Log.i(TAG, "first frame") }
            override fun onPlayerError(error: PlaybackException) {
                // A live stream can stall at start; reconnect a few times
                // before reporting an error.
                if (retries < 5) {
                    retries++
                    player.prepare()
                    player.playWhenReady = true
                    return
                }
                Log.w(TAG, "error ${error.errorCodeName}", error)
                failure = error.errorCodeName + ": " + (error.cause?.message ?: error.message)
            }
        })
        channel.setMethodCallHandler { call, result ->
            if (call.method == "status") {
                result.success(mapOf("firstFrame" to firstFrame, "error" to failure,
                    "playing" to player.isPlaying, "buffering" to (player.playbackState == Player.STATE_BUFFERING)))
            } else { result.notImplemented() }
        }
        val item = MediaItem.Builder().setUri("udp://0.0.0.0:8554").setMimeType(MimeTypes.VIDEO_MP2T).build()
        // GoPro's preview often starts without an IDR frame: let the TS
        // extractor begin at any keyframe and detect access units itself.
        // Only the TS extractor: sniffing ~20 container formats on a live
        // UDP stream that starts mid-GOP never settles on a track.
        val extractors = ExtractorsFactory {
            arrayOf<Extractor>(TsExtractor(
                TsExtractor.MODE_SINGLE_PMT,
                TimestampAdjuster(0),
                VideoOnlyReaders(DefaultTsPayloadReaderFactory(
                    DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
                        DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS))))
        }
        val source = ProgressiveMediaSource.Factory(
            DataSource.Factory { UdpDataSource(65536, 15000) }, extractors)
            .createMediaSource(item)
        player.setMediaSource(source)
        player.prepare()
        player.playWhenReady = true
    }
    override fun getView(): View = playerView
    override fun dispose() {
        channel.setMethodCallHandler(null)
        playerView.player = null
        player.release()
    }
}

private const val TAG = "KosmosPreview"

/**
 * Only the H.264/H.265 video stream. GoPro's preview also carries AAC audio
 * and two private data streams (PMT types 0x80/0x81); those never yield a
 * track format, and the player will not show a frame until every track has
 * one.
 */
@UnstableApi
private class VideoOnlyReaders(private val base: DefaultTsPayloadReaderFactory) : TsPayloadReader.Factory {
    override fun createInitialPayloadReaders(): SparseArray<TsPayloadReader> = base.createInitialPayloadReaders()
    override fun createPayloadReader(streamType: Int, esInfo: TsPayloadReader.EsInfo): TsPayloadReader? =
        if (streamType == TsExtractor.TS_STREAM_TYPE_H265 || streamType == TsExtractor.TS_STREAM_TYPE_H264)
            base.createPayloadReader(streamType, esInfo) else null
}
