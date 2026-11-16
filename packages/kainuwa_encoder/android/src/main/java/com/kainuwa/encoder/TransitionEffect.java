package com.kainuwa.encoder;

import android.content.Context;
import android.opengl.GLES20;

import androidx.media3.common.VideoFrameProcessingException;
import androidx.media3.common.util.GlProgram;
import androidx.media3.common.util.GlUtil;
import androidx.media3.common.util.Size;
import androidx.media3.effect.BaseGlShaderProgram;
import androidx.media3.effect.GlEffect;
import androidx.media3.effect.GlShaderProgram;

import java.util.List;

/**
 * Slide to slide transitions (push, zoom push, zoom, fade, glitch push) for the whole video.
 * The maths mirrors lib/transition_math.dart: keep them the same.
 */
public final class TransitionEffect implements GlEffect {

    public static final class Spec {
        public long atMs;
        public String kind = "none";
        public String dir = "left";
        public long halfMs;
        /** Colour behind the slides during the transition, 0xAARRGGBB. */
        public long bg = 0xFF000000L;
    }

    private final List<Spec> specs;

    public TransitionEffect(List<Spec> specs) {
        this.specs = specs;
    }

    @Override
    public GlShaderProgram toGlShaderProgram(Context context, boolean useHdr)
            throws VideoFrameProcessingException {
        return new Program(specs, useHdr);
    }

    private static double ease(double t) {
        double x = Math.max(0.0, Math.min(1.0, t));
        return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
    }

    /** Returns {scale, dx, dy, alpha, split, bgR, bgG, bgB} for the given time. */
    static double[] frameAt(List<Spec> specs, long tMs) {
        for (Spec s : specs) {
            if (s.halfMs <= 0 || "none".equals(s.kind)) {
                continue;
            }
            if (tMs >= s.atMs - s.halfMs && tMs < s.atMs) {
                return withBg(s, half(s, (tMs - (s.atMs - s.halfMs)) / (double) s.halfMs, true));
            }
            if (tMs >= s.atMs && tMs < s.atMs + s.halfMs) {
                return withBg(s, half(s, (tMs - s.atMs) / (double) s.halfMs, false));
            }
        }
        return new double[]{1, 0, 0, 1, 0, 0, 0, 0};
    }

    private static double[] withBg(Spec s, double[] f) {
        return new double[]{f[0], f[1], f[2], f[3], f[4],
                ((s.bg >> 16) & 0xFF) / 255.0, ((s.bg >> 8) & 0xFF) / 255.0, (s.bg & 0xFF) / 255.0};
    }

    private static double[] half(Spec s, double p, boolean exiting) {
        double e = ease(p);
        double a = exiting ? e : 1 - e;
        double vx = -1;
        double vy = 0;
        if ("right".equals(s.dir)) {
            vx = 1;
        } else if ("up".equals(s.dir)) {
            vx = 0;
            vy = 1;
        } else if ("down".equals(s.dir)) {
            vx = 0;
            vy = -1;
        }
        double sign = exiting ? 1.0 : -1.0;
        switch (s.kind) {
            case "push":
                return new double[]{1, vx * sign * a, vy * sign * a, 1, 0};
            case "zoompush":
                return new double[]{1 - 0.18 * a, vx * sign * a, vy * sign * a, 1, 0};
            case "glitch":
                return new double[]{1 - 0.08 * a, vx * sign * a, vy * sign * a, 1, 0.03 * 4 * a * (1 - a)};
            case "zoom":
                return new double[]{exiting ? 1 + 0.6 * a : 1 - 0.3 * a, 0, 0, 1 - a, 0};
            case "fade":
                return new double[]{1, 0, 0, 1 - a, 0};
            default:
                return new double[]{1, 0, 0, 1, 0};
        }
    }

    private static final class Program extends BaseGlShaderProgram {
        private static final String VERTEX =
                "attribute vec4 aFramePosition;\n"
                        + "varying vec2 vUv;\n"
                        + "void main() {\n"
                        + "  gl_Position = aFramePosition;\n"
                        + "  vUv = aFramePosition.xy * 0.5 + 0.5;\n"
                        + "}\n";
        private static final String FRAGMENT =
                "precision mediump float;\n"
                        + "uniform sampler2D uTexSampler;\n"
                        + "uniform float uScale;\n"
                        + "uniform vec2 uOffset;\n"
                        + "uniform float uAlpha;\n"
                        + "uniform float uSplit;\n"
                        + "uniform vec3 uBg;\n"
                        + "varying vec2 vUv;\n"
                        + "vec4 pick(vec2 uv) {\n"
                        + "  vec2 p = (uv - 0.5 - uOffset) / uScale + 0.5;\n"
                        + "  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return vec4(uBg, 1.0);\n"
                        + "  return texture2D(uTexSampler, p);\n"
                        + "}\n"
                        + "void main() {\n"
                        + "  vec4 c = pick(vUv);\n"
                        + "  if (uSplit > 0.0) {\n"
                        + "    float r = pick(vUv + vec2(uSplit, 0.0)).r;\n"
                        + "    float b = pick(vUv - vec2(uSplit, 0.0)).b;\n"
                        + "    c = vec4(r, c.g, b, 1.0);\n"
                        + "  }\n"
                        + "  gl_FragColor = vec4(mix(uBg, c.rgb, uAlpha), 1.0);\n"
                        + "}\n";

        private final List<Spec> specs;
        private final GlProgram program;

        Program(List<Spec> specs, boolean useHdr) throws VideoFrameProcessingException {
            super(useHdr, 1);
            this.specs = specs;
            try {
                program = new GlProgram(VERTEX, FRAGMENT);
                program.setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(),
                        GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE);
            } catch (GlUtil.GlException e) {
                throw new VideoFrameProcessingException(e);
            }
        }

        @Override
        public Size configure(int inputWidth, int inputHeight) {
            return new Size(inputWidth, inputHeight);
        }

        @Override
        public void drawFrame(int inputTexId, long presentationTimeUs) throws VideoFrameProcessingException {
            double[] f = frameAt(specs, presentationTimeUs / 1000);
            try {
                program.use();
                program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0);
                program.setFloatUniform("uScale", (float) Math.max(0.05, f[0]));
                program.setFloatsUniform("uOffset", new float[]{(float) f[1], (float) f[2]});
                program.setFloatUniform("uAlpha", (float) Math.max(0.0, Math.min(1.0, f[3])));
                program.setFloatUniform("uSplit", (float) f[4]);
                program.setFloatsUniform("uBg", new float[]{(float) f[5], (float) f[6], (float) f[7]});
                program.bindAttributesAndUniforms();
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
            } catch (GlUtil.GlException e) {
                throw new VideoFrameProcessingException(e, presentationTimeUs);
            }
        }

        @Override
        public void release() throws VideoFrameProcessingException {
            super.release();
            try {
                program.delete();
            } catch (GlUtil.GlException e) {
                throw new VideoFrameProcessingException(e);
            }
        }
    }
}
