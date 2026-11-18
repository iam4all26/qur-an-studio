package com.kainuwa.encoder;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.media.MediaPlayer;
import android.media.MediaRecorder;
import android.graphics.Bitmap;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.media.MediaScannerConnection;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.view.Surface;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.Effect;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.OverlayEffect;
import androidx.media3.effect.Presentation;
import androidx.media3.effect.TextureOverlay;
import androidx.media3.transformer.Composition;
import androidx.media3.transformer.DefaultEncoderFactory;
import androidx.media3.transformer.VideoEncoderSettings;
import androidx.media3.transformer.EditedMediaItem;
import androidx.media3.transformer.EditedMediaItemSequence;
import androidx.media3.transformer.Effects;
import androidx.media3.transformer.ExportException;
import androidx.media3.transformer.ExportResult;
import androidx.media3.transformer.ProgressHolder;
import androidx.media3.transformer.Transformer;

import com.google.common.collect.ImmutableList;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;

/**
 * Local plugin for Kainuwa Studio: system file picker, image + audio to MP4 export
 * (Media3 Transformer), and saving finished videos into Movies.
 */
@OptIn(markerClass = UnstableApi.class)
public class KainuwaEncoderPlugin
        implements FlutterPlugin,
        MethodChannel.MethodCallHandler,
        ActivityAware,
        PluginRegistry.ActivityResultListener,
        PluginRegistry.RequestPermissionsResultListener {

    private static final String CHANNEL_NAME = "kainuwa_encoder";
    private static final int REQUEST_PICK = 4101;
    private static final int REQUEST_SAVE = 4102;
    private static final int REQUEST_AUDIO_PERMISSION = 4103;
    private static final int REQUEST_STORAGE_PERMISSION = 4104;
    private MethodChannel.Result pendingLegacyResult;
    private String pendingLegacyPath;
    private String pendingLegacyName;

    private MethodChannel channel;
    private Context appContext;
    private TextureRegistry textureRegistry;
    private ExoPlayer exo;
    private TextureRegistry.SurfaceTextureEntry exoEntry;
    private Surface exoSurface;
    private Activity activity;
    private ActivityPluginBinding activityBinding;

    private MethodChannel.Result pendingPick;
    private MethodChannel.Result pendingSave;
    private String pendingSavePath;

    private MediaRecorder recorder;
    private String recordingPath;
    private MethodChannel.Result pendingRecordResult;
    private String pendingRecordPath;
    private boolean pendingReduceNoise;
    private MediaPlayer player;

    private Transformer transformer;
    private MethodChannel.Result exportResult;
    private String exportOutput;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService lessonWorker = Executors.newSingleThreadExecutor();
    private volatile int lessonGen = 0;

    private final Runnable progressTicker = new Runnable() {
        @Override
        public void run() {
            Transformer t = transformer;
            if (t == null) {
                return;
            }
            ProgressHolder holder = new ProgressHolder();
            int state = t.getProgress(holder);
            if (state == Transformer.PROGRESS_STATE_AVAILABLE && channel != null) {
                channel.invokeMethod("progress", holder.progress);
            }
            mainHandler.postDelayed(this, 500);
        }
    };

    // ---- FlutterPlugin ----

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        appContext = binding.getApplicationContext();
        textureRegistry = binding.getTextureRegistry();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
    }

    private void exoClose() {
        try {
            if (exo != null) {
                exo.stop();
                exo.release();
            }
        } catch (Exception ignored) {
        }
        exo = null;
        if (exoSurface != null) {
            exoSurface.release();
            exoSurface = null;
        }
        if (exoEntry != null) {
            exoEntry.release();
            exoEntry = null;
        }
    }

    private void exoOpen(String path, long startMs, MethodChannel.Result result) {
        exoClose();
        if (textureRegistry == null || appContext == null) {
            result.error("video", "No texture registry", null);
            return;
        }
        try {
            int w = 0;
            int h = 0;
            int rot = 0;
            MediaMetadataRetriever r = new MediaMetadataRetriever();
            try {
                r.setDataSource(path);
                String ws = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH);
                String hs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT);
                String rs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
                if (ws != null) w = Integer.parseInt(ws);
                if (hs != null) h = Integer.parseInt(hs);
                if (rs != null) rot = Integer.parseInt(rs);
            } finally {
                r.release();
            }
            if (w <= 0 || h <= 0) {
                result.error("video", "Cannot read video size", null);
                return;
            }
            exoEntry = textureRegistry.createSurfaceTexture();
            exoEntry.surfaceTexture().setDefaultBufferSize(w, h);
            exoSurface = new Surface(exoEntry.surfaceTexture());
            exo = new ExoPlayer.Builder(appContext).build();
            exo.setVideoSurface(exoSurface);
            exo.setVolume(0f);
            exo.setMediaItem(MediaItem.fromUri(Uri.fromFile(new File(path))));
            exo.prepare();
            exo.seekTo(startMs);
            exo.setPlayWhenReady(false);
            final Map<String, Object> out = new HashMap<>();
            out.put("textureId", exoEntry.id());
            boolean swap = rot == 90 || rot == 270;
            out.put("width", swap ? h : w);
            out.put("height", swap ? w : h);
            final ExoPlayer mine = exo;
            final boolean[] replied = new boolean[] {false};
            final Runnable timeout = new Runnable() {
                @Override
                public void run() {
                    if (!replied[0]) {
                        replied[0] = true;
                        result.success(out);
                    }
                }
            };
            mine.addListener(new Player.Listener() {
                @Override
                public void onPlaybackStateChanged(int state) {
                    if (state == Player.STATE_READY && !replied[0]) {
                        replied[0] = true;
                        mainHandler.removeCallbacks(timeout);
                        result.success(out);
                    }
                }
            });
            mainHandler.postDelayed(timeout, 3000);
        } catch (Exception e) {
            exoClose();
            result.error("video", String.valueOf(e.getMessage()), null);
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        lessonGen++;
        exoClose();
        if (transformer != null) {
            transformer.cancel();
        }
        transformer = null;
        exportResult = null;
        mainHandler.removeCallbacks(progressTicker);
        stopPlayerQuietly();
        stopAllClips();
        releaseRecorderQuietly();
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    // ---- ActivityAware ----

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        // Let the app draw into the camera cutout area (no black strip in landscape).
        // Done here so it works even when the build workflow cannot patch the theme.
        try {
            if (Build.VERSION.SDK_INT >= 28 && activity != null) {
                WindowManager.LayoutParams lp = activity.getWindow().getAttributes();
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
                activity.getWindow().setAttributes(lp);
            }
        } catch (Throwable ignored) {
        }
        activityBinding = binding;
        binding.addActivityResultListener(this);
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
    }

    // ---- Method calls ----

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "pick":
                pick((String) call.argument("mime"), result);
                break;
            case "openStore":
                openStore((String) call.argument("package"), (String) call.argument("url"), result);
                break;
            case "exportScene":
                exportScene(call, result);
                break;
            case "exportLesson":
                exportLesson(call, result);
                break;
            case "cancel":
                cancel(result);
                break;
            case "saveFile":
                saveWithPicker(String.valueOf((String) call.argument("path")),
                        String.valueOf((String) call.argument("name")), "application/octet-stream", result);
                break;
            case "playLastVideo":
                playLastVideo(result);
                break;
            case "lastVideoUri":
                result.success(lastSavedUri == null ? null : lastSavedUri.toString());
                break;
            case "viewVideo":
                viewVideo((String) call.argument("uri"), (String) call.argument("mode"), result);
                break;
            case "saveToMovies":
                saveToMovies((String) call.argument("path"), (String) call.argument("name"), result);
                break;
            case "startRecording":
                startRecording((String) call.argument("path"),
                        Boolean.TRUE.equals(call.argument("reduceNoise")), result);
                break;
            case "stopRecording":
                stopRecording(result);
                break;
            case "recordingLevel":
                recordingLevel(result);
                break;
            case "videoOpen":
                exoOpen(String.valueOf((String) call.argument("path")), (long) num(call, "ms", 0), result);
                break;
            case "videoPosition":
                result.success(exo == null ? -1 : (int) exo.getCurrentPosition());
                break;
            case "videoPlay":
                if (exo != null) {
                    exo.seekTo((long) num(call, "ms", 0));
                    exo.setPlayWhenReady(true);
                }
                result.success(null);
                break;
            case "videoSpeed":
                if (exo != null) exo.setPlaybackParameters(new PlaybackParameters((float) num(call, "speed", 1.0)));
                result.success(null);
                break;
            case "videoSeek":
                if (exo != null) exo.seekTo((long) num(call, "ms", 0));
                result.success(null);
                break;
            case "videoClose":
                exoClose();
                result.success(null);
                break;
            case "videoFrame":
                videoFrame(String.valueOf((String) call.argument("path")),
                        (long) num(call, "ms", 0),
                        Boolean.TRUE.equals(call.argument("exact")),
                        Boolean.TRUE.equals(call.argument("bytes")), result);
                break;
            case "audioDuration":
                result.success((int) Math.max(readDurationMs(String.valueOf((String) call.argument("path"))), 0));
                break;
            case "playAudio":
                playAudio((String) call.argument("path"), num(call, "volume", 1.0), num(call, "speed", 1.0), result);
                break;
            case "stopAudio":
                stopPlayerQuietly();
                result.success(null);
                break;
            case "playClip":
                playClip((String) call.argument("id"), (String) call.argument("path"),
                        longOf((Object) call.argument("seekMs"), 0), num(call, "volume", 1.0), num(call, "speed", 1.0), result);
                break;
            case "setClipVolume":
                setClipVolume((String) call.argument("id"), num(call, "volume", 1.0));
                result.success(null);
                break;
            case "stopClip":
                stopClipQuietly((String) call.argument("id"));
                result.success(null);
                break;
            case "stopClips":
                stopAllClips();
                result.success(null);
                break;
            case "audioPeaks":
                audioPeaks((String) call.argument("path"), (int) num(call, "bins", 64), result);
                break;
            case "filesDir":
                result.success(appContext.getFilesDir().getAbsolutePath());
                break;
            default:
                result.notImplemented();
        }
    }

    // ---- File picker ----

    private void pick(String mime, MethodChannel.Result result) {
        if (activity == null) {
            result.error("no_activity", "The app screen is not ready yet.", null);
            return;
        }
        if (pendingPick != null) {
            result.error("busy", "A file picker is already open.", null);
            return;
        }
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(mime == null ? "*/*" : mime);
        pendingPick = result;
        activity.startActivityForResult(intent, REQUEST_PICK);
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQUEST_SAVE) {
            handleSaveResult(resultCode, data);
            return true;
        }
        if (requestCode != REQUEST_PICK) {
            return false;
        }
        final MethodChannel.Result r = pendingPick;
        pendingPick = null;
        if (r == null) {
            return true;
        }
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            r.success(null);
            return true;
        }
        final Uri uri = data.getData();
        worker.execute(() -> {
            try {
                final String path = copyToCache(uri);
                mainHandler.post(() -> r.success(path));
            } catch (Exception e) {
                final String message = String.valueOf(e.getMessage());
                mainHandler.post(() -> r.error("copy_failed", message, null));
            }
        });
        return true;
    }

    private String displayName(Uri uri) {
        String name = null;
        try (Cursor cursor = appContext.getContentResolver()
                .query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                name = cursor.getString(0);
            }
        } catch (Exception ignored) {
            // fall through to the default name
        }
        if (name == null || name.trim().isEmpty()) {
            name = "file";
        }
        return name.replaceAll("[^A-Za-z0-9._-]", "_");
    }

    private String copyToCache(Uri uri) throws IOException {
        File dir = new File(appContext.getFilesDir(), "media");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IOException("Could not create the import folder.");
        }
        File target = new File(dir, System.currentTimeMillis() + "_" + displayName(uri));
        try (InputStream in = appContext.getContentResolver().openInputStream(uri);
             OutputStream out = new FileOutputStream(target)) {
            if (in == null) {
                throw new IOException("Could not open the chosen file.");
            }
            copyStream(in, out);
        }
        return target.getAbsolutePath();
    }

    private static void copyStream(InputStream in, OutputStream out) throws IOException {
        byte[] buffer = new byte[64 * 1024];
        int read;
        while ((read = in.read(buffer)) != -1) {
            out.write(buffer, 0, read);
        }
    }

    // ---- Export ----

    private long readDurationMs(String path) {
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            retriever.setDataSource(path);
            String value = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
            return value == null ? -1 : Long.parseLong(value);
        } catch (Exception e) {
            return -1;
        } finally {
            try {
                retriever.release();
            } catch (Exception ignored) {
                // nothing to do
            }
        }
    }

    private static double num(MethodCall call, String key, double fallback) {
        Object value = call.argument(key);
        return value instanceof Number ? ((Number) value).doubleValue() : fallback;
    }

    private static String str(MethodCall call, String key) {
        Object value = call.argument(key);
        if (value instanceof String) {
            String s = ((String) value).trim();
            return s.isEmpty() ? null : s;
        }
        return null;
    }

    private void exportScene(MethodCall call, MethodChannel.Result result) {
        if (transformer != null) {
            result.error("busy", "An export is already running.", null);
            return;
        }
        String imagePath = str(call, "image");
        String narrationPath = str(call, "narration");
        String musicPath = str(call, "music");
        String outputPath = str(call, "output");
        if (imagePath == null || narrationPath == null || outputPath == null) {
            result.error("bad_arguments", "Image, narration and output paths are required.", null);
            return;
        }
        int width = (int) num(call, "width", 1280);
        int height = (int) num(call, "height", 720);
        float narrationVolume = (float) num(call, "narrationVolume", 1.0);
        float musicVolume = (float) num(call, "musicVolume", 0.3);
        long musicFadeInMs = (long) num(call, "musicFadeInMs", 0);
        long musicFadeOutMs = (long) num(call, "musicFadeOutMs", 0);
        String overlayText = str(call, "overlayText");
        long overlayStartMs = (long) num(call, "overlayStartMs", 1000);
        long overlayDurationMs = (long) num(call, "overlayDurationMs", 800);
        String overlayAnimation = str(call, "overlayAnimation");

        long narrationMs = readDurationMs(narrationPath);
        if (narrationMs <= 0) {
            result.error("bad_audio", "Could not read the length of the narration file.", null);
            return;
        }

        File out = new File(outputPath);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }
        if (out.exists()) {
            out.delete();
        }

        // Picture: the image for the whole narration, plus an optional animated text label.
        MediaItem imageItem = new MediaItem.Builder()
                .setUri(Uri.fromFile(new File(imagePath)))
                .setImageDurationMs(narrationMs)
                .build();
        List<Effect> imageEffects = new ArrayList<>();
        imageEffects.add(Presentation.createForWidthAndHeight(
                width, height, Presentation.LAYOUT_SCALE_TO_FIT));
        if (overlayText != null) {
            Bitmap label = AnimatedTextOverlay.renderText(overlayText);
            imageEffects.add(new OverlayEffect(ImmutableList.<TextureOverlay>of(
                    new AnimatedTextOverlay(label, overlayStartMs * 1000L,
                            overlayDurationMs * 1000L, overlayAnimation))));
        }
        EditedMediaItem editedImage = new EditedMediaItem.Builder(imageItem)
                .setFrameRate(30)
                .setEffects(new Effects(new ArrayList<AudioProcessor>(), imageEffects))
                .build();

        // Narration: only the sound of the file, with its own volume.
        List<AudioProcessor> narrationProcessors = new ArrayList<>();
        if (Math.abs(narrationVolume - 1f) > 0.001f) {
            narrationProcessors.add(new GainAudioProcessor(
                    narrationVolume, 0L, 0L, narrationMs * 1000L));
        }
        EditedMediaItem editedNarration = new EditedMediaItem.Builder(
                MediaItem.fromUri(Uri.fromFile(new File(narrationPath))))
                .setRemoveVideo(true)
                .setEffects(new Effects(narrationProcessors, new ArrayList<Effect>()))
                .build();

        List<EditedMediaItemSequence> sequences = new ArrayList<>();
        sequences.add(new EditedMediaItemSequence(Collections.singletonList(editedImage)));
        sequences.add(new EditedMediaItemSequence(Collections.singletonList(editedNarration)));

        // Background music: cut to the narration length, with volume and fades.
        if (musicPath != null) {
            long musicMs = readDurationMs(musicPath);
            if (musicMs <= 0) {
                result.error("bad_audio", "Could not read the length of the music file.", null);
                return;
            }
            long usedMs = Math.min(musicMs, narrationMs);
            MediaItem.Builder musicBuilder = new MediaItem.Builder()
                    .setUri(Uri.fromFile(new File(musicPath)));
            if (musicMs > narrationMs) {
                musicBuilder.setClippingConfiguration(
                        new MediaItem.ClippingConfiguration.Builder()
                                .setEndPositionMs(narrationMs)
                                .build());
            }
            List<AudioProcessor> musicProcessors = new ArrayList<>();
            musicProcessors.add(new GainAudioProcessor(
                    musicVolume, musicFadeInMs * 1000L, musicFadeOutMs * 1000L, usedMs * 1000L));
            EditedMediaItem editedMusic = new EditedMediaItem.Builder(musicBuilder.build())
                    .setRemoveVideo(true)
                    .setEffects(new Effects(musicProcessors, new ArrayList<Effect>()))
                    .build();
            sequences.add(new EditedMediaItemSequence(Collections.singletonList(editedMusic)));
        }

        List<Effect> compositionVideoEffects = new ArrayList<>();
        compositionVideoEffects.add(Presentation.createForWidthAndHeight(
                width, height, Presentation.LAYOUT_SCALE_TO_FIT));
        Effects compositionEffects =
                new Effects(new ArrayList<AudioProcessor>(), compositionVideoEffects);

        Composition composition = new Composition.Builder(sequences)
                .setEffects(compositionEffects)
                .build();

        exportResult = result;
        exportOutput = outputPath;

        transformer = new Transformer.Builder(appContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(new Transformer.Listener() {
                    @Override
                    public void onCompleted(Composition composition, ExportResult exportResultInfo) {
                        MethodChannel.Result r = exportResult;
                        String path = exportOutput;
                        finishExport();
                        if (r != null) {
                            r.success(path);
                        }
                    }

                    @Override
                    public void onError(Composition composition, ExportResult exportResultInfo,
                                        ExportException exception) {
                        MethodChannel.Result r = exportResult;
                        finishExport();
                        if (r != null) {
                            r.error("export_failed",
                                    exception.getMessage() + " (code " + exception.errorCode + ")",
                                    null);
                        }
                    }
                })
                .build();

        mainHandler.removeCallbacks(progressTicker);
        mainHandler.postDelayed(progressTicker, 500);
        transformer.start(composition, outputPath);
    }

    private void finishExport() {
        setKeepAwake(false);
        transformer = null;
        exportResult = null;
        exportOutput = null;
        mainHandler.removeCallbacks(progressTicker);
    }

    private void cancel(MethodChannel.Result result) {
        lessonGen++;
        Transformer t = transformer;
        MethodChannel.Result pending = exportResult;
        if (t != null) {
            t.cancel();
        }
        finishExport();
        if (pending != null) {
            pending.error("cancelled", "Export cancelled.", null);
        }
        result.success(null);
    }

    // ---- Whole lesson export ----

    private void setKeepAwake(final boolean on) {
        final Activity a = activity;
        if (a == null) {
            return;
        }
        a.runOnUiThread(() -> {
            try {
                if (on) {
                    a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            } catch (Exception ignored) {
                // nothing to do
            }
        });
    }

    private void sendStage(String stage) {
        if (channel != null) {
            channel.invokeMethod("stage", stage);
        }
    }

    private static long longOf(Object v, long fallback) {
        return v instanceof Number ? ((Number) v).longValue() : fallback;
    }

    private static double doubleOf(Object v, double fallback) {
        return v instanceof Number ? ((Number) v).doubleValue() : fallback;
    }

    @SuppressWarnings("unchecked")
    private int lessonBitrate = 0;
    private final List<String> lessonVideoPaths = new ArrayList<>();
    private final List<Long> lessonVideoStarts = new ArrayList<>();
    private final List<Double> lessonVideoScales = new ArrayList<>();
    private final List<Boolean> lessonVideoFills = new ArrayList<>();
    private final List<TransitionEffect.Spec> lessonTransitions = new ArrayList<>();

    // Live preview frames: one reader stays open so each frame is quicker to get.
    private final ExecutorService frameWorker = Executors.newSingleThreadExecutor();
    private MediaMetadataRetriever liveReader;
    private String liveReaderPath;

    private byte[] liveFrame(String path, long ms) {
        try {
            if (liveReader == null || !path.equals(liveReaderPath)) {
                if (liveReader != null) {
                    try {
                        liveReader.release();
                    } catch (Exception ignored) {
                        // nothing to do
                    }
                }
                liveReader = new MediaMetadataRetriever();
                liveReader.setDataSource(path);
                liveReaderPath = path;
            }
            Bitmap b = liveReader.getFrameAtTime(ms * 1000L, MediaMetadataRetriever.OPTION_CLOSEST);
            if (b == null) {
                return null;
            }
            int w = b.getWidth();
            int h = b.getHeight();
            float scale = Math.min(1f, 480f / Math.max(w, h));
            Bitmap small = scale < 1f
                    ? Bitmap.createScaledBitmap(b, Math.round(w * scale), Math.round(h * scale), false)
                    : b;
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            small.compress(Bitmap.CompressFormat.JPEG, 70, bos);
            return bos.toByteArray();
        } catch (Exception e) {
            liveReader = null;
            liveReaderPath = null;
            return null;
        }
    }

    private void videoFrame(final String path, final long ms, final boolean exact,
                            final boolean asBytes, final MethodChannel.Result result) {
        if (asBytes) {
            frameWorker.execute(() -> {
                final byte[] data = liveFrame(path, ms);
                mainHandler.post(() -> result.success(data));
            });
            return;
        }
        new Thread(() -> {
            Object out = null;
            MediaMetadataRetriever r = new MediaMetadataRetriever();
            try {
                r.setDataSource(path);
                Bitmap b = r.getFrameAtTime(ms * 1000L, exact
                        ? MediaMetadataRetriever.OPTION_CLOSEST
                        : MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
                if (b != null) {
                    int w = b.getWidth();
                    int h = b.getHeight();
                    float scale = Math.min(1f, 640f / Math.max(w, h));
                    Bitmap small = scale < 1f
                            ? Bitmap.createScaledBitmap(b, Math.round(w * scale), Math.round(h * scale), true)
                            : b;
                    if (asBytes) {
                        java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
                        small.compress(Bitmap.CompressFormat.JPEG, 80, bos);
                        out = bos.toByteArray();
                    } else {
                        File f = new File(appContext.getCacheDir(),
                                "vf_" + Math.abs((path + "@" + ms).hashCode()) + ".jpg");
                        FileOutputStream fo = new FileOutputStream(f);
                        small.compress(Bitmap.CompressFormat.JPEG, 85, fo);
                        fo.close();
                        out = f.getAbsolutePath();
                    }
                }
            } catch (Exception ignored) {
                out = null;
            } finally {
                try {
                    r.release();
                } catch (Exception ignored) {
                    // nothing to do
                }
            }
            final Object res = out;
            mainHandler.post(() -> result.success(res));
        }).start();
    }

    private void exportLesson(MethodCall call, MethodChannel.Result result) {
        if (transformer != null || exportResult != null) {
            result.error("busy", "An export is already running.", null);
            return;
        }
        final List<Map<String, Object>> scenes = call.argument("scenes");
        final String workDir = str(call, "workDir");
        final String outputPath = str(call, "output");
        final String musicPath = str(call, "music");
        if (scenes == null || scenes.isEmpty() || workDir == null || outputPath == null) {
            result.error("bad_arguments", "Slides, work folder and output path are required.", null);
            return;
        }
        final int width = (int) num(call, "width", 1280);
        final int height = (int) num(call, "height", 720);
        final int fps = (int) num(call, "fps", 30);
        lessonBitrate = (int) num(call, "bitrate", 0);
        final float musicVolume = (float) num(call, "musicVolume", 0.3);
        final long musicFadeMs = (long) num(call, "musicFadeMs", 0);
        final double musicSpeed = num(call, "musicSpeed", 1.0);
        final List<LessonAudioMixer.Clip> clips = new ArrayList<>();
        final List<Map<String, Object>> rawClips = call.argument("clips");
        if (rawClips != null) {
            for (Map<String, Object> m : rawClips) {
                if (!(m.get("path") instanceof String)) {
                    continue;
                }
                LessonAudioMixer.Clip c = new LessonAudioMixer.Clip();
                c.path = (String) m.get("path");
                c.startMs = longOf(m.get("startMs"), 0);
                c.trimMs = longOf(m.get("trimMs"), 0);
                c.durMs = longOf(m.get("durMs"), 0);
                c.volume = (float) doubleOf(m.get("volume"), 1.0);
                c.speed = doubleOf(m.get("speed"), 1.0);
                c.fadeInMs = longOf(m.get("fadeInMs"), 0);
                c.fadeOutMs = longOf(m.get("fadeOutMs"), 0);
                clips.add(c);
            }
        }

        final List<LessonAudioMixer.Spec> specs = new ArrayList<>();
        final List<String> images = new ArrayList<>();
        final List<Long> durations = new ArrayList<>();
        final LessonOverlays overlays = new LessonOverlays();
        lessonVideoPaths.clear();
        lessonVideoStarts.clear();
        lessonVideoScales.clear();
        lessonVideoFills.clear();
        lessonTransitions.clear();
        final List<Map<String, Object>> rawTransitions = call.argument("transitions");
        if (rawTransitions != null) {
            for (Map<String, Object> m : rawTransitions) {
                TransitionEffect.Spec t = new TransitionEffect.Spec();
                t.atMs = longOf(m.get("atMs"), 0);
                t.halfMs = longOf(m.get("halfMs"), 0);
                t.kind = m.get("kind") instanceof String ? (String) m.get("kind") : "none";
                t.dir = m.get("dir") instanceof String ? (String) m.get("dir") : "left";
                t.bg = longOf(m.get("bg"), 0xFF000000L);
                lessonTransitions.add(t);
            }
        }
        long totalMs = 0;
        for (Map<String, Object> sc : scenes) {
            Object img = sc.get("image");
            long dur = longOf(sc.get("durationMs"), 0);
            if (!(img instanceof String) || dur <= 0) {
                result.error("bad_arguments", "A slide has no picture or no length.", null);
                return;
            }
            images.add((String) img);
            Object vid = sc.get("video");
            lessonVideoPaths.add(vid instanceof String && !((String) vid).isEmpty() ? (String) vid : null);
            lessonVideoStarts.add(longOf(sc.get("videoStartMs"), 0));
            lessonVideoFills.add(Boolean.TRUE.equals(sc.get("videoFill")));
            lessonVideoScales.add(sc.get("videoScale") instanceof Number ? ((Number) sc.get("videoScale")).doubleValue() : 1.0);
            durations.add(dur);
            totalMs += dur;

            LessonAudioMixer.Spec spec = new LessonAudioMixer.Spec();
            Object narr = sc.get("narration");
            spec.path = narr instanceof String && !((String) narr).isEmpty() ? (String) narr : null;
            spec.durationMs = dur;
            spec.volume = (float) doubleOf(sc.get("volume"), 1.0);
            spec.speed = doubleOf(sc.get("speed"), 1.0);
            spec.clean = Boolean.TRUE.equals(sc.get("clean"));
            specs.add(spec);

            List<LessonOverlays.Item> items = new ArrayList<>();
            Object raw = sc.get("overlays");
            if (raw instanceof List) {
                for (Object o : (List<Object>) raw) {
                    if (!(o instanceof Map)) {
                        continue;
                    }
                    Map<String, Object> m = (Map<String, Object>) o;
                    if (!(m.get("path") instanceof String)) {
                        continue;
                    }
                    LessonOverlays.Item it = new LessonOverlays.Item();
                    it.path = (String) m.get("path");
                    it.cx = (float) doubleOf(m.get("cx"), 0.5);
                    it.cy = (float) doubleOf(m.get("cy"), 0.5);
                    it.kind = m.get("anim") instanceof String ? (String) m.get("anim") : "none";
                    it.startMs = longOf(m.get("startMs"), 0);
                    it.durMs = longOf(m.get("durMs"), 800);
                    it.showMs = longOf(m.get("showMs"), 0);
                    it.hideMs = m.get("hideMs") != null
                            ? longOf(m.get("hideMs"), Long.MAX_VALUE) : Long.MAX_VALUE;
                    it.outKind = m.get("outAnim") instanceof String
                            ? (String) m.get("outAnim") : "none";
                    it.outStartMs = longOf(m.get("outStartMs"), 0);
                    it.outDurMs = longOf(m.get("outDurMs"), 500);
                    Object lk = m.get("loop");
                    it.loopKind = lk instanceof String ? (String) lk : "none";
                    it.loopMs = longOf(m.get("loopMs"), 1000);
                    Object kr = m.get("keys");
                    if (kr instanceof List && !((List<Object>) kr).isEmpty()) {
                        List<Object> kl = (List<Object>) kr;
                        int kn = kl.size();
                        long[] kt = new long[kn];
                        float[] kx = new float[kn];
                        float[] ky = new float[kn];
                        int kc = 0;
                        for (Object ko : kl) {
                            if (ko instanceof Map) {
                                Map<String, Object> km = (Map<String, Object>) ko;
                                kt[kc] = longOf(km.get("t"), 0);
                                kx[kc] = (float) doubleOf(km.get("x"), 0.5);
                                ky[kc] = (float) doubleOf(km.get("y"), 0.5);
                                kc++;
                            }
                        }
                        if (kc > 0) {
                            it.keyT = java.util.Arrays.copyOf(kt, kc);
                            it.keyX = java.util.Arrays.copyOf(kx, kc);
                            it.keyY = java.util.Arrays.copyOf(ky, kc);
                        }
                    }
                    Object fr = m.get("frames");
                    if (fr instanceof List && !((List<Object>) fr).isEmpty()) {
                        List<Object> fl = (List<Object>) fr;
                        List<String> fp = new ArrayList<>();
                        List<Long> fa = new ArrayList<>();
                        for (Object fo : fl) {
                            if (fo instanceof Map && ((Map<String, Object>) fo).get("path") instanceof String) {
                                Map<String, Object> fm = (Map<String, Object>) fo;
                                fp.add((String) fm.get("path"));
                                fa.add(longOf(fm.get("atMs"), 0));
                            }
                        }
                        if (!fp.isEmpty()) {
                            it.framePaths = fp.toArray(new String[0]);
                            it.frameAt = new long[fa.size()];
                            for (int q = 0; q < fa.size(); q++) {
                                it.frameAt[q] = fa.get(q);
                            }
                        }
                    }
                    items.add(it);
                }
            }
            overlays.addScene(dur, items);
        }
        final long total = totalMs;

        final int gen = ++lessonGen;
        exportResult = result;
        exportOutput = outputPath;
        setKeepAwake(true);
        sendStage("audio");

        lessonWorker.execute(() -> {
            try {
                File dir = new File(workDir);
                if (!dir.exists() && !dir.mkdirs()) {
                    throw new IOException("Could not create the export folder.");
                }
                final File wav = new File(dir, "narration.wav");
                final LessonAudioMixer.Control control = new LessonAudioMixer.Control() {
                    @Override
                    public boolean cancelled() {
                        return gen != lessonGen;
                    }

                    @Override
                    public void progress(final int percent) {
                        mainHandler.post(() -> {
                            if (gen == lessonGen && channel != null) {
                                channel.invokeMethod("audioProgress", percent);
                            }
                        });
                    }
                };
                LessonAudioMixer.mix(specs, wav, control);
                if (!clips.isEmpty()) {
                    LessonAudioMixer.addClips(wav, clips, control);
                }
                String musicUse = musicPath;
                if (musicPath != null && Math.abs(musicSpeed - 1.0) > 0.01) {
                    File sped = new File(dir, "music_speed.wav");
                    LessonAudioMixer.renderSpeed(musicPath, musicSpeed, total, sped, control);
                    musicUse = sped.getAbsolutePath();
                }
                final String musicFinal = musicUse;
                long musicMs = 0;
                if (musicPath != null) {
                    musicMs = readDurationMs(musicFinal);
                    if (musicMs <= 0) {
                        throw new IOException("Could not read the length of the music file.");
                    }
                }
                final long musicLen = musicMs;
                mainHandler.post(() -> {
                    if (gen != lessonGen) {
                        return;
                    }
                    try {
                        startLessonVideo(images, durations, wav, musicFinal, musicLen, musicVolume,
                                musicFadeMs, overlays, width, height, fps, total, outputPath);
                    } catch (Exception e) {
                        failLesson(gen, String.valueOf(e.getMessage()));
                    }
                });
            } catch (Exception e) {
                final String message = String.valueOf(e.getMessage());
                mainHandler.post(() -> failLesson(gen, message));
            }
        });
    }

    private void failLesson(int gen, String message) {
        if (gen != lessonGen) {
            return;
        }
        MethodChannel.Result r = exportResult;
        finishExport();
        if (r != null) {
            r.error("export_failed", message, null);
        }
    }

    private void startLessonVideo(List<String> images, List<Long> durations, File wav,
                                  String musicPath, long musicMs, float musicVolume,
                                  long musicFadeMs, LessonOverlays overlays, int width,
                                  int height, int fps, long totalMs, String outputPath) {
        File out = new File(outputPath);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }
        if (out.exists()) {
            out.delete();
        }

        List<EditedMediaItem> pictures = new ArrayList<>();
        for (int i = 0; i < images.size(); i++) {
            String videoPath = i < lessonVideoPaths.size() ? lessonVideoPaths.get(i) : null;
            MediaItem item;
            if (videoPath != null) {
                long from = lessonVideoStarts.get(i);
                item = new MediaItem.Builder()
                        .setUri(Uri.fromFile(new File(videoPath)))
                        .setClippingConfiguration(new MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(from)
                                .setEndPositionMs(from + durations.get(i))
                                .build())
                        .build();
            } else {
                item = new MediaItem.Builder()
                        .setUri(Uri.fromFile(new File(images.get(i))))
                        .setImageDurationMs(durations.get(i))
                        .build();
            }
            List<Effect> effects = new ArrayList<>();
            double vScale = i < lessonVideoScales.size() ? lessonVideoScales.get(i) : 1.0;
            boolean fillFrame = videoPath != null && i < lessonVideoFills.size()
                    && lessonVideoFills.get(i) && vScale >= 0.999;
            effects.add(Presentation.createForWidthAndHeight(
                    width, height,
                    fillFrame ? Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP : Presentation.LAYOUT_SCALE_TO_FIT));
            if (videoPath != null && vScale > 0.05 && vScale < 0.999) {
                // Phone frame: shrink the video into the phone screen; the frame picture hides the rest.
                effects.add(new androidx.media3.effect.ScaleAndRotateTransformation.Builder()
                        .setScale((float) vScale, (float) vScale)
                        .build());
            }
            EditedMediaItem.Builder pictureBuilder = new EditedMediaItem.Builder(item)
                    .setFrameRate(fps)
                    .setEffects(new Effects(new ArrayList<AudioProcessor>(), effects));
            if (videoPath != null) {
                pictureBuilder.setRemoveAudio(true);
            }
            pictures.add(pictureBuilder.build());
        }

        EditedMediaItem narration = new EditedMediaItem.Builder(
                MediaItem.fromUri(Uri.fromFile(wav)))
                .setRemoveVideo(true)
                .build();

        List<EditedMediaItemSequence> sequences = new ArrayList<>();
        sequences.add(new EditedMediaItemSequence(pictures));
        sequences.add(new EditedMediaItemSequence(Collections.singletonList(narration)));

        if (musicPath != null) {
            long usedMs = Math.min(musicMs, totalMs);
            MediaItem.Builder mb = new MediaItem.Builder().setUri(Uri.fromFile(new File(musicPath)));
            if (musicMs > totalMs) {
                mb.setClippingConfiguration(new MediaItem.ClippingConfiguration.Builder()
                        .setEndPositionMs(totalMs)
                        .build());
            }
            List<AudioProcessor> processors = new ArrayList<>();
            processors.add(new GainAudioProcessor(
                    musicVolume, musicFadeMs * 1000L, musicFadeMs * 1000L, usedMs * 1000L));
            sequences.add(new EditedMediaItemSequence(Collections.singletonList(
                    new EditedMediaItem.Builder(mb.build())
                            .setRemoveVideo(true)
                            .setEffects(new Effects(processors, new ArrayList<Effect>()))
                            .build())));
        }

        List<Effect> compositionVideoEffects = new ArrayList<>();
        compositionVideoEffects.add(Presentation.createForWidthAndHeight(
                width, height, Presentation.LAYOUT_SCALE_TO_FIT));
        if (overlays.slotCount() > 0) {
            compositionVideoEffects.add(new OverlayEffect(overlays.build()));
        }
        if (!lessonTransitions.isEmpty()) {
            compositionVideoEffects.add(new TransitionEffect(new ArrayList<>(lessonTransitions)));
        }
        Composition composition = new Composition.Builder(sequences)
                .setEffects(new Effects(new ArrayList<AudioProcessor>(), compositionVideoEffects))
                .build();

        Transformer.Builder lessonBuilder = new Transformer.Builder(appContext);
        if (lessonBitrate > 0) {
            lessonBuilder.setEncoderFactory(new DefaultEncoderFactory.Builder(appContext)
                    .setRequestedVideoEncoderSettings(
                            new VideoEncoderSettings.Builder().setBitrate(lessonBitrate).build())
                    .setEnableFallback(true)
                    .build());
        }
        transformer = lessonBuilder
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(new Transformer.Listener() {
                    @Override
                    public void onCompleted(Composition c, ExportResult info) {
                        MethodChannel.Result r = exportResult;
                        String path = exportOutput;
                        finishExport();
                        if (r != null) {
                            r.success(path);
                        }
                    }

                    @Override
                    public void onError(Composition c, ExportResult info, ExportException e) {
                        MethodChannel.Result r = exportResult;
                        finishExport();
                        if (r != null) {
                            r.error("export_failed",
                                    e.getMessage() + " (code " + e.errorCode + ")", null);
                        }
                    }
                })
                .build();

        sendStage("video");
        mainHandler.removeCallbacks(progressTicker);
        mainHandler.postDelayed(progressTicker, 500);
        transformer.start(composition, outputPath);
    }

    // ---- Google Play ----

    /** Opens the app page in the Play Store app; falls back to any handler of market:// and then the web page. */
    private void openStore(String pkg, String webUrl, MethodChannel.Result result) {
        final String id = (pkg == null || pkg.isEmpty()) ? "com.kainuwa.quranstudio" : pkg;
        final String web = (webUrl == null || webUrl.isEmpty())
                ? "https://play.google.com/store/apps/details?id=" + id : webUrl;
        final Uri market = Uri.parse("market://details?id=" + id);
        // 1) the Play Store app itself
        if (startView(market, "com.android.vending")) {
            result.success("play");
            return;
        }
        // 2) any app that opens market:// links
        if (startView(market, null)) {
            result.success("market");
            return;
        }
        // 3) the web page in any browser
        if (startView(Uri.parse(web), null)) {
            result.success("web");
            return;
        }
        result.success("failed");
    }

    private boolean startView(Uri uri, String targetPackage) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            if (targetPackage != null) intent.setPackage(targetPackage);
            if (activity != null) {
                activity.startActivity(intent);
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                appContext.startActivity(intent);
            }
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    // ---- Save to Movies ----

    private volatile Uri lastSavedUri;

    /** Opens the last video saved to Movies in the phone's own video player. */
    private void playLastVideo(MethodChannel.Result result) {
        Uri uri = lastSavedUri;
        if (uri == null) {
            result.error("no_video", "There is no saved video to play yet.", null);
            return;
        }
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "video/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            if (activity != null) {
                activity.startActivity(intent);
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                appContext.startActivity(intent);
            }
            result.success(true);
        } catch (Exception e) {
            result.error("play_failed", "No video player was found on this phone.", null);
        }
    }

    /** Plays, shares or opens a saved video (mode: play, open or share). */
    private void viewVideo(String uriText, String mode, MethodChannel.Result result) {
        Uri uri = (uriText == null || uriText.isEmpty()) ? lastSavedUri : Uri.parse(uriText);
        if (uri == null) {
            result.error("no_video", "There is no saved video to open yet.", null);
            return;
        }
        try {
            Intent intent;
            if ("share".equals(mode)) {
                intent = new Intent(Intent.ACTION_SEND);
                intent.setType("video/mp4");
                intent.putExtra(Intent.EXTRA_STREAM, uri);
                intent.setClipData(android.content.ClipData.newRawUri("", uri));
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                intent = Intent.createChooser(intent, "Share video");
            } else {
                intent = new Intent(Intent.ACTION_VIEW);
                intent.setDataAndType(uri, "video/*");
                intent.setClipData(android.content.ClipData.newRawUri("", uri));
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                if ("open".equals(mode)) {
                    intent = Intent.createChooser(intent, "Open with");
                }
            }
            if (activity != null) {
                activity.startActivity(intent);
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                appContext.startActivity(intent);
            }
            result.success(true);
        } catch (Exception e) {
            result.error("view_failed", "The video could not be opened. It may have been moved or deleted.", null);
        }
    }

    private void saveToMovies(String path, String name, MethodChannel.Result result) {
        if (path == null || name == null) {
            result.error("bad_arguments", "Path and name are required.", null);
            return;
        }
        lastSavedUri = null;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            saveLegacy(path, name, result);
            return;
        }
        worker.execute(() -> {
            try {
                ContentResolver resolver = appContext.getContentResolver();
                ContentValues values = new ContentValues();
                values.put(MediaStore.Video.Media.DISPLAY_NAME, name);
                values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
                values.put(MediaStore.Video.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_MOVIES + "/Quran Studio");
                values.put(MediaStore.Video.Media.IS_PENDING, 1);
                Uri uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
                if (uri == null) {
                    throw new IOException("Could not create the file in Movies.");
                }
                try (InputStream in = new FileInputStream(path);
                     OutputStream out = resolver.openOutputStream(uri)) {
                    if (out == null) {
                        throw new IOException("Could not write to Movies.");
                    }
                    copyStream(in, out);
                }
                ContentValues done = new ContentValues();
                done.put(MediaStore.Video.Media.IS_PENDING, 0);
                resolver.update(uri, done, null, null);
                lastSavedUri = uri;
                String finalName = name;
                try (android.database.Cursor c = resolver.query(uri,
                        new String[]{MediaStore.MediaColumns.DISPLAY_NAME}, null, null, null)) {
                    if (c != null && c.moveToFirst() && c.getString(0) != null) {
                        finalName = c.getString(0);
                    }
                } catch (Exception ignored) {
                }
                final String shownName = finalName;
                mainHandler.post(() -> result.success("Movies/Quran Studio/" + shownName));
            } catch (Exception e) {
                final String message = String.valueOf(e.getMessage());
                mainHandler.post(() -> result.error("save_failed", message, null));
            }
        });
    }

    // Android 9 and older: save straight into Movies / Kainuwa Studio when the storage
    // permission is allowed, otherwise let the user choose where to save.
    private void saveLegacy(String path, String name, MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT >= 23
                && appContext.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED) {
            if (activity == null || pendingLegacyResult != null) {
                saveWithPicker(path, name, result);
                return;
            }
            pendingLegacyResult = result;
            pendingLegacyPath = path;
            pendingLegacyName = name;
            activity.requestPermissions(
                    new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQUEST_STORAGE_PERMISSION);
            return;
        }
        writeLegacy(path, name, result);
    }

    private void writeLegacy(String path, String name, MethodChannel.Result result) {
        worker.execute(() -> {
            try {
                File dir = new File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                        "Quran Studio");
                if (!dir.exists() && !dir.mkdirs()) {
                    throw new IOException("Could not create the Quran Studio folder in Movies.");
                }
                File target = new File(dir, name);
                int n = 1;
                String base = name.endsWith(".mp4") ? name.substring(0, name.length() - 4) : name;
                while (target.exists()) {
                    target = new File(dir, base + "_" + n + ".mp4");
                    n++;
                }
                try (InputStream in = new FileInputStream(path);
                     OutputStream out = new FileOutputStream(target)) {
                    copyStream(in, out);
                }
                final File saved = target;
                MediaScannerConnection.scanFile(appContext, new String[]{saved.getAbsolutePath()},
                        new String[]{"video/mp4"}, (scanPath, scanUri) -> lastSavedUri = scanUri);
                mainHandler.post(() -> result.success("Movies/Quran Studio/" + saved.getName()));
            } catch (Exception e) {
                // Could not write there: let the user choose a place instead.
                mainHandler.post(() -> saveWithPicker(path, name, result));
            }
        });
    }

    // Let the user choose where to save (no storage permission needed).
    private void saveWithPicker(String path, String name, MethodChannel.Result result) {
        saveWithPicker(path, name, "video/mp4", result);
    }

    private void saveWithPicker(String path, String name, String mime, MethodChannel.Result result) {
        if (activity == null) {
            result.error("no_activity", "The app screen is not ready yet.", null);
            return;
        }
        if (pendingSave != null) {
            result.error("busy", "A save dialog is already open.", null);
            return;
        }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(mime);
        intent.putExtra(Intent.EXTRA_TITLE, name);
        pendingSave = result;
        pendingSavePath = path;
        activity.startActivityForResult(intent, REQUEST_SAVE);
    }

    private void handleSaveResult(int resultCode, Intent data) {
        final MethodChannel.Result r = pendingSave;
        final String path = pendingSavePath;
        pendingSave = null;
        pendingSavePath = null;
        if (r == null) {
            return;
        }
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null || path == null) {
            r.error("save_cancelled", "Saving was cancelled.", null);
            return;
        }
        final Uri uri = data.getData();
        worker.execute(() -> {
            try (InputStream in = new FileInputStream(path);
                 OutputStream out = appContext.getContentResolver().openOutputStream(uri)) {
                if (out == null) {
                    throw new IOException("Could not write to the chosen location.");
                }
                copyStream(in, out);
                mainHandler.post(() -> r.success("the location you chose"));
            } catch (Exception e) {
                final String message = String.valueOf(e.getMessage());
                mainHandler.post(() -> r.error("save_failed", message, null));
            }
        });
    }

    // ---- Voice recording and playback ----

    private void startRecording(String path, boolean reduceNoise, MethodChannel.Result result) {
        if (path == null) {
            result.error("bad_arguments", "A file path is required.", null);
            return;
        }
        if (recorder != null || pendingRecordResult != null) {
            result.error("busy", "A recording is already running.", null);
            return;
        }
        if (Build.VERSION.SDK_INT >= 23
                && appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            if (activity == null) {
                result.error("no_activity", "The app screen is not ready yet.", null);
                return;
            }
            pendingRecordResult = result;
            pendingRecordPath = path;
            pendingReduceNoise = reduceNoise;
            activity.requestPermissions(
                    new String[]{Manifest.permission.RECORD_AUDIO}, REQUEST_AUDIO_PERMISSION);
            return;
        }
        beginRecording(path, reduceNoise, result);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == REQUEST_STORAGE_PERMISSION) {
            MethodChannel.Result lr = pendingLegacyResult;
            String lp = pendingLegacyPath;
            String ln = pendingLegacyName;
            pendingLegacyResult = null;
            pendingLegacyPath = null;
            pendingLegacyName = null;
            if (lr == null) {
                return true;
            }
            boolean ok = grantResults != null && grantResults.length > 0
                    && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            if (ok) {
                writeLegacy(lp, ln, lr);
            } else {
                saveWithPicker(lp, ln, lr);
            }
            return true;
        }
        if (requestCode != REQUEST_AUDIO_PERMISSION) {
            return false;
        }
        MethodChannel.Result r = pendingRecordResult;
        String path = pendingRecordPath;
        boolean reduceNoise = pendingReduceNoise;
        pendingRecordResult = null;
        pendingRecordPath = null;
        if (r == null) {
            return true;
        }
        boolean granted = grantResults != null && grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        if (granted) {
            beginRecording(path, reduceNoise, r);
        } else {
            r.error("permission_denied", "The microphone permission was not allowed.", null);
        }
        return true;
    }

    private void beginRecording(String path, boolean reduceNoise, MethodChannel.Result result) {
        File parent = new File(path).getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }
        MediaRecorder r = null;
        try {
            r = Build.VERSION.SDK_INT >= 31 ? new MediaRecorder(appContext) : new MediaRecorder();
            // VOICE_COMMUNICATION switches on the phone's own noise suppression where it exists.
            r.setAudioSource(reduceNoise
                    ? MediaRecorder.AudioSource.VOICE_COMMUNICATION
                    : MediaRecorder.AudioSource.MIC);
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            r.setAudioChannels(1);
            r.setAudioSamplingRate(44100);
            r.setAudioEncodingBitRate(128000);
            r.setOutputFile(path);
            r.prepare();
            r.start();
            recorder = r;
            recordingPath = path;
            result.success(true);
        } catch (Exception e) {
            if (r != null) {
                try {
                    r.release();
                } catch (Exception ignored) {
                    // nothing to do
                }
            }
            recorder = null;
            recordingPath = null;
            result.error("record_failed", String.valueOf(e.getMessage()), null);
        }
    }

    private void stopRecording(MethodChannel.Result result) {
        MediaRecorder r = recorder;
        String path = recordingPath;
        recorder = null;
        recordingPath = null;
        if (r == null) {
            result.error("not_recording", "No recording is running.", null);
            return;
        }
        boolean ok = true;
        try {
            r.stop();
        } catch (RuntimeException e) {
            ok = false;
        }
        try {
            r.release();
        } catch (Exception ignored) {
            // nothing to do
        }
        if (!ok || path == null) {
            if (path != null) {
                new File(path).delete();
            }
            result.error("too_short", "The recording was too short.", null);
            return;
        }
        result.success((int) Math.max(readDurationMs(path), 0));
    }

    private void recordingLevel(MethodChannel.Result result) {
        MediaRecorder r = recorder;
        int level = 0;
        if (r != null) {
            try {
                level = r.getMaxAmplitude();
            } catch (Exception ignored) {
                level = 0;
            }
        }
        result.success(level);
    }

    private void releaseRecorderQuietly() {
        MediaRecorder r = recorder;
        recorder = null;
        recordingPath = null;
        if (r != null) {
            try {
                r.stop();
            } catch (Exception ignored) {
                // nothing to do
            }
            try {
                r.release();
            } catch (Exception ignored) {
                // nothing to do
            }
        }
    }

    /** Plays slower or faster with the pitch kept. Needs Android 6 or newer; older phones play at normal speed. */
    private static void applySpeed(MediaPlayer mp, double speed) {
        if (Math.abs(speed - 1.0) < 0.01 || Build.VERSION.SDK_INT < 23) {
            return;
        }
        try {
            mp.setPlaybackParams(mp.getPlaybackParams().setSpeed((float) speed));
        } catch (Exception ignored) {
            // keep normal speed
        }
    }

    private void playAudio(String path, double volume, final double speed, MethodChannel.Result result) {
        stopPlayerQuietly();
        if (path == null) {
            result.error("bad_arguments", "A file path is required.", null);
            return;
        }
        try {
            final MediaPlayer p = new MediaPlayer();
            p.setDataSource(path);
            float v = (float) Math.max(0.0, Math.min(1.0, volume));
            p.setVolume(v, v);
            p.setOnPreparedListener(mp -> {
                mp.start();
                applySpeed(mp, speed);
            });
            p.setOnCompletionListener(mp -> {
                releasePlayer(mp);
                if (channel != null) {
                    channel.invokeMethod("playbackDone", null);
                }
            });
            p.setOnErrorListener((mp, what, extra) -> {
                releasePlayer(mp);
                if (channel != null) {
                    channel.invokeMethod("playbackDone", null);
                }
                return true;
            });
            player = p;
            p.prepareAsync();
            result.success(true);
        } catch (Exception e) {
            player = null;
            result.error("play_failed", String.valueOf(e.getMessage()), null);
        }
    }

    // ---- Extra clips for the editor preview (several can play at once) ----

    private final java.util.Map<String, MediaPlayer> clipPlayers = new java.util.HashMap<>();

    private void playClip(final String id, String path, final long seekMs, double volume,
                          final double speed, MethodChannel.Result result) {
        if (id == null || path == null) {
            result.error("bad_arguments", "A clip id and file path are required.", null);
            return;
        }
        stopClipQuietly(id);
        try {
            final MediaPlayer p = new MediaPlayer();
            p.setDataSource(path);
            float v = (float) Math.max(0.0, Math.min(1.0, volume));
            p.setVolume(v, v);
            p.setOnPreparedListener(mp -> {
                try {
                    if (seekMs > 0) {
                        mp.seekTo((int) seekMs);
                    }
                    mp.start();
                    applySpeed(mp, speed);
                } catch (Exception ignored) {
                    // nothing to do
                }
            });
            p.setOnCompletionListener(mp -> releaseClip(id, mp));
            p.setOnErrorListener((mp, what, extra) -> {
                releaseClip(id, mp);
                return true;
            });
            clipPlayers.put(id, p);
            p.prepareAsync();
            result.success(true);
        } catch (Exception e) {
            result.error("play_failed", String.valueOf(e.getMessage()), null);
        }
    }

    private void releaseClip(String id, MediaPlayer mp) {
        try {
            mp.release();
        } catch (Exception ignored) {
            // nothing to do
        }
        if (clipPlayers.get(id) == mp) {
            clipPlayers.remove(id);
        }
    }

    private void setClipVolume(String id, double volume) {
        MediaPlayer p = id == null ? null : clipPlayers.get(id);
        if (p == null) {
            return;
        }
        float v = (float) Math.max(0.0, Math.min(1.0, volume));
        try {
            p.setVolume(v, v);
        } catch (Exception ignored) {
            // nothing to do
        }
    }

    private void stopClipQuietly(String id) {
        MediaPlayer p = id == null ? null : clipPlayers.remove(id);
        if (p != null) {
            try {
                p.stop();
            } catch (Exception ignored) {
                // nothing to do
            }
            try {
                p.release();
            } catch (Exception ignored) {
                // nothing to do
            }
        }
    }

    private void stopAllClips() {
        for (String id : new java.util.ArrayList<>(clipPlayers.keySet())) {
            stopClipQuietly(id);
        }
    }

    private void audioPeaks(final String path, final int bins, final MethodChannel.Result result) {
        if (path == null) {
            result.error("bad_arguments", "A file path is required.", null);
            return;
        }
        final int count = Math.max(8, Math.min(2000, bins));
        worker.execute(() -> {
            try {
                final float[] values = LessonAudioMixer.peaks(path, count);
                final List<Double> out = new ArrayList<>();
                for (float f : values) {
                    out.add((double) f);
                }
                mainHandler.post(() -> result.success(out));
            } catch (Throwable e) {
                final String message = String.valueOf(e.getMessage());
                mainHandler.post(() -> result.error("peaks_failed", message, null));
            }
        });
    }

    private void releasePlayer(MediaPlayer mp) {
        try {
            mp.release();
        } catch (Exception ignored) {
            // nothing to do
        }
        if (player == mp) {
            player = null;
        }
    }

    private void stopPlayerQuietly() {
        MediaPlayer p = player;
        player = null;
        if (p != null) {
            try {
                p.stop();
            } catch (Exception ignored) {
                // nothing to do
            }
            try {
                p.release();
            } catch (Exception ignored) {
                // nothing to do
            }
        }
    }
}
