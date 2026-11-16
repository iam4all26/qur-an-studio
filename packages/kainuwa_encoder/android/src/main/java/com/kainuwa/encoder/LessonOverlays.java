package com.kainuwa.encoder;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.BitmapOverlay;
import androidx.media3.effect.OverlaySettings;
import androidx.media3.effect.TextureOverlay;

import com.google.common.collect.ImmutableList;

import java.util.ArrayList;
import java.util.List;

/**
 * Animated items of a whole lesson. One set of "slots" is shared by all scenes:
 * at any moment slot k shows the k-th animated item of the scene that is playing.
 * Times are on the composition (whole lesson) timeline.
 */
@OptIn(markerClass = UnstableApi.class)
final class LessonOverlays {

    static final class Item {
        String path;
        float cx;
        float cy;
        String kind;
        long startMs;
        long durMs;
        /** On screen from showMs until hideMs (milliseconds into the scene). */
        long showMs = 0;
        long hideMs = Long.MAX_VALUE;
        String outKind = "none";
        long outStartMs = 0;
        long outDurMs = 500;
        /** Overall animation (spin, shake, ...) and the time of one round. */
        String loopKind = "none";
        long loopMs = 1000;
        /** Optional picture series (text animations): the last frame whose time has come is shown. */
        String[] framePaths = null;
        long[] frameAt = null;

        /** Optional moving position: times (scene ms) with the centre as fractions of the slide. */
        long[] keyT = null;
        float[] keyX = null;
        float[] keyY = null;

        float[] positionAt(double localMs) {
            if (keyT == null || keyT.length == 0) {
                return new float[]{cx, cy};
            }
            if (localMs <= keyT[0]) {
                return new float[]{keyX[0], keyY[0]};
            }
            int last = keyT.length - 1;
            if (localMs >= keyT[last]) {
                return new float[]{keyX[last], keyY[last]};
            }
            for (int i = 0; i < last; i++) {
                if (localMs < keyT[i + 1]) {
                    double span = Math.max(1, keyT[i + 1] - keyT[i]);
                    float f = (float) ((localMs - keyT[i]) / span);
                    return new float[]{
                            keyX[i] + (keyX[i + 1] - keyX[i]) * f,
                            keyY[i] + (keyY[i + 1] - keyY[i]) * f};
                }
            }
            return new float[]{keyX[last], keyY[last]};
        }

        int frameIndex(double localMs) {
            if (framePaths == null || framePaths.length == 0) {
                return -1;
            }
            int idx = 0;
            for (int i = 0; i < frameAt.length; i++) {
                if (localMs >= frameAt[i]) {
                    idx = i;
                } else {
                    break;
                }
            }
            return idx;
        }
    }

    private final List<Long> sceneStartUs = new ArrayList<>();
    private final List<List<Item>> perScene = new ArrayList<>();
    private long cursorMs = 0;
    private int slots = 0;

    void addScene(long durationMs, List<Item> items) {
        sceneStartUs.add(cursorMs * 1000L);
        perScene.add(items);
        cursorMs += durationMs;
        slots = Math.max(slots, items.size());
    }

    int slotCount() {
        return slots;
    }

    private int sceneAt(long timeUs) {
        int idx = 0;
        for (int i = 0; i < sceneStartUs.size(); i++) {
            if (timeUs >= sceneStartUs.get(i)) {
                idx = i;
            } else {
                break;
            }
        }
        return idx;
    }

    ImmutableList<TextureOverlay> build() {
        ImmutableList.Builder<TextureOverlay> list = ImmutableList.builder();
        for (int k = 0; k < slots; k++) {
            list.add(new Slot(k));
        }
        return list.build();
    }

    private static final Bitmap BLANK = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
    private static final OverlaySettings HIDDEN =
            new OverlaySettings.Builder().setAlphaScale(0f).build();

    private final class Slot extends BitmapOverlay {
        private final int slot;
        private int cachedScene = -1;
        private int cachedFrame = -2;
        private Bitmap cachedBitmap = BLANK;

        Slot(int slot) {
            this.slot = slot;
        }

        private Item itemAt(int scene) {
            List<Item> items = perScene.get(scene);
            return slot < items.size() ? items.get(slot) : null;
        }

        @Override
        public Bitmap getBitmap(long presentationTimeUs) {
            int scene = sceneAt(presentationTimeUs);
            Item item = itemAt(scene);
            if (item == null) {
                return BLANK;
            }
            double localMs = (presentationTimeUs - sceneStartUs.get(scene)) / 1000.0;
            int frame = item.frameIndex(localMs);
            if (scene != cachedScene || frame != cachedFrame) {
                String file = frame >= 0 ? item.framePaths[frame] : item.path;
                Bitmap decoded = BitmapFactory.decodeFile(file);
                cachedBitmap = decoded == null ? BLANK : decoded;
                cachedScene = scene;
                cachedFrame = frame;
            }
            return cachedBitmap;
        }

        @Override
        public OverlaySettings getOverlaySettings(long presentationTimeUs) {
            int scene = sceneAt(presentationTimeUs);
            Item item = itemAt(scene);
            if (item == null) {
                return HIDDEN;
            }
            double localMs = (presentationTimeUs - sceneStartUs.get(scene)) / 1000.0;
            double[] f = fullFrame(item, localMs);
            float[] pos = item.positionAt(localMs);
            // The encoder only accepts anchors from -1 to 1 (anything else stops the export).
            float x = (float) Math.max(-1.0, Math.min(1.0, pos[0] * 2f - 1f + f[1] * 2.0));
            float y = (float) Math.max(-1.0, Math.min(1.0, 1f - pos[1] * 2f - f[5] * 2.0));
            return new OverlaySettings.Builder()
                    .setBackgroundFrameAnchor(x, y)
                    .setRotationDegrees((float) -f[4])
                    .setScale((float) (f[2] * f[3]), (float) f[2])
                    .setAlphaScale((float) Math.max(0.0, Math.min(1.0, f[0])))
                    .build();
        }
    }

    /** Timing, entrance and exit together. Returns alpha, dx, scale, scaleX, rotation, dy. */
    static double[] fullFrame(Item item, double timeMs) {
        if (timeMs < item.showMs || timeMs >= item.hideMs) {
            return new double[]{0, 0, 1, 1, 0, 0};
        }
        double[] in = frame(item.kind, timeMs, item.startMs, item.durMs);
        double a = in[0];
        double dx = in[1];
        double sc = in[2];
        double sx = in[3];
        double rot = 0;
        double dy = in[4];
        if (item.outKind != null && !item.outKind.equals("none")) {
            double[] out = exitFrame(item.outKind, timeMs, item.outStartMs, item.outDurMs);
            a *= out[0];
            dx += out[1];
            sc *= out[2];
            sx *= out[3];
            dy += out[4];
        }
        if (item.loopKind != null && !item.loopKind.equals("none")) {
            double[] lp = loopFrame(item.loopKind, timeMs - item.showMs, item.loopMs);
            a *= lp[0];
            dx += lp[1];
            sc *= lp[2];
            sx *= lp[3];
            rot += lp[4];
            dy += lp[5];
        }
        return new double[]{a, dx, sc, sx, rot, dy};
    }

    /**
     * Overall animations. Same maths as loopFrame in animation_math.dart.
     * Returns alpha, dx, scale, scaleX, rotation (degrees, clockwise), dy (down is positive).
     */
    static double[] loopFrame(String kind, double timeMs, long periodMs) {
        if (timeMs < 0) {
            return new double[]{1, 0, 1, 1, 0, 0};
        }
        double period = Math.max(100, periodMs);
        double phase = (timeMs - Math.floor(timeMs / period) * period) / period;
        double s = Math.sin(2 * Math.PI * phase);
        switch (kind) {
            case "spin":
                return new double[]{1, 0, 1, 1, 360 * phase, 0};
            case "spinback":
                return new double[]{1, 0, 1, 1, -360 * phase, 0};
            case "swing":
                return new double[]{1, 0, 1, 1, 15 * s, 0};
            case "wobble":
                return new double[]{1, 0, 1 + 0.04 * Math.cos(2 * Math.PI * phase), 1, 6 * s, 0};
            case "shake":
                return new double[]{1, 0.012 * s, 1, 1, 2 * s, 0};
            case "pulse":
                return new double[]{1, 0, 1 + 0.08 * s, 1, 0, 0};
            case "heartbeat": {
                double beat = phase < 0.5 ? Math.max(0.0, Math.sin(4 * Math.PI * phase)) : 0.0;
                return new double[]{1, 0, 1 + 0.12 * beat, 1, 0, 0};
            }
            case "float":
                return new double[]{1, 0, 1, 1, 0, 0.02 * s};
            case "bounce":
                return new double[]{1, 0, 1, 1, 0, -0.05 * Math.abs(Math.sin(Math.PI * phase))};
            case "blink":
                return new double[]{0.35 + 0.65 * (0.5 + 0.5 * Math.cos(2 * Math.PI * phase)), 0, 1, 1, 0, 0};
            case "flip":
                return new double[]{1, 0, 1, Math.max(0.03, Math.abs(Math.cos(2 * Math.PI * phase))), 0, 0};
            default:
                return new double[]{1, 0, 1, 1, 0, 0};
        }
    }

    /** Direction part of a kind such as slide:up (the movement direction, default right). */
    private static String dirOf(String kind) {
        int i = kind == null ? -1 : kind.indexOf(':');
        return i < 0 ? "right" : kind.substring(i + 1);
    }

    private static String baseOf(String kind) {
        int i = kind == null ? -1 : kind.indexOf(':');
        return i < 0 ? kind : kind.substring(0, i);
    }

    private static final double SLIDE_X = 0.175;
    private static final double SLIDE_Y = 0.31;

    /** Same formulas as lib/animation_math.dart. Returns alpha, dx (slide width fraction), scale, scaleX, dy. */
    static double[] frame(String fullKind, double timeMs, long startMs, long durMs) {
        String kind = baseOf(fullKind);
        if (kind == null || kind.equals("none")) {
            return new double[]{1, 0, 1, 1, 0};
        }
        double duration = Math.max(1, durMs);
        double progress = timeMs <= startMs ? 0.0 : Math.min(1.0, (timeMs - startMs) / duration);
        if (kind.equals("appear")) {
            return new double[]{progress > 0 ? 1 : 0, 0, 1, 1, 0};
        }
        double eased = 1 - Math.pow(1 - progress, 3);
        double alpha = eased;
        double dx = 0;
        double dy = 0;
        double scale = 1;
        double scaleX = 1;
        switch (kind) {
            case "slide":
                switch (dirOf(fullKind)) {
                    case "left":
                        dx = SLIDE_X * (1 - eased);
                        break;
                    case "up":
                        dy = SLIDE_Y * (1 - eased);
                        break;
                    case "down":
                        dy = -SLIDE_Y * (1 - eased);
                        break;
                    default:
                        dx = -SLIDE_X * (1 - eased);
                        break;
                }
                break;
            case "pop": {
                double q = progress - 1;
                scale = 1 + 2.70158 * q * q * q + 1.70158 * q * q;
                alpha = Math.min(1.0, progress * 4);
                break;
            }
            case "zoom":
                scale = 1.6 - 0.6 * eased;
                break;
            case "draw":
                alpha = 1;
                scaleX = Math.max(0.01, eased);
                break;
            default:
                break;
        }
        if (progress <= 0) {
            alpha = 0;
        }
        return new double[]{alpha, dx, Math.max(0.01, scale), scaleX, dy};
    }

    /** Exit animation. Returns alpha, dx, scale, scaleX, dy (same formulas as the editor). */
    static double[] exitFrame(String fullKind, double timeMs, long outStartMs, long outDurMs) {
        String kind = baseOf(fullKind);
        double duration = Math.max(1, outDurMs);
        double p = timeMs <= outStartMs ? 0.0 : Math.min(1.0, (timeMs - outStartMs) / duration);
        double e = p * p;
        switch (kind) {
            case "fade":
                return new double[]{1 - e, 0, 1, 1, 0};
            case "slide":
                switch (dirOf(fullKind)) {
                    case "left":
                        return new double[]{1 - e, -SLIDE_X * e, 1, 1, 0};
                    case "up":
                        return new double[]{1 - e, 0, 1, 1, -SLIDE_Y * e};
                    case "down":
                        return new double[]{1 - e, 0, 1, 1, SLIDE_Y * e};
                    default:
                        return new double[]{1 - e, SLIDE_X * e, 1, 1, 0};
                }
            case "pop":
                return new double[]{1 - e, 0, Math.max(0.01, 1 - 0.5 * e), 1, 0};
            case "zoom":
                return new double[]{1 - e, 0, 1 + 0.6 * e, 1, 0};
            case "draw":
                return new double[]{1, 0, 1, Math.max(0.01, 1 - e), 0};
            default:
                return new double[]{1, 0, 1, 1, 0};
        }
    }
}
