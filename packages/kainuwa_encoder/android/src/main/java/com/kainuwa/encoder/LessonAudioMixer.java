package com.kainuwa.encoder;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import java.util.Arrays;
import java.util.List;

/**
 * Builds the whole narration track of a lesson as one mono 16-bit WAV file.
 * Every scene gets exactly its own length (cut or padded with silence), so the
 * sound can never drift away from the pictures. Voice cleaning and volume are
 * applied here.
 */
final class LessonAudioMixer {

    static final int RATE = 44100;

    interface Control {
        boolean cancelled();

        void progress(int percent);
    }

    static final class Spec {
        String path;       // null means silence
        long durationMs;
        float volume = 1f;
        double speed = 1.0;
        boolean clean;
    }

    /** An extra sound placed on the lesson timeline (music, sound effect, voice). */
    static final class Clip {
        String path;
        long startMs;     // where it starts on the lesson timeline
        long trimMs;      // how far into the file it starts playing
        long durMs;       // how long it plays
        float volume = 1f;
        double speed = 1.0;
        long fadeInMs;
        long fadeOutMs;
    }

    /** A control that never cancels and ignores progress. */
    static final Control NONE = new Control() {
        @Override
        public boolean cancelled() {
            return false;
        }

        @Override
        public void progress(int percent) {
        }
    };

    private LessonAudioMixer() {
    }

    private static long frames(long ms) {
        return Math.round(ms * RATE / 1000.0);
    }

    /**
     * Adds extra clips into a finished lesson WAV (written by [mix]), each with its
     * own start, volume and fades. The file keeps its length.
     */
    static void addClips(File wav, List<Clip> clips, Control control) throws IOException {
        try (RandomAccessFile raf = new RandomAccessFile(wav, "rw")) {
            long len = raf.length();
            int total = (int) Math.max(0, (len - 44) / 2);
            byte[] data = new byte[total * 2];
            raf.seek(44);
            raf.readFully(data);
            ShortBuffer sb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer();
            for (int c = 0; c < clips.size(); c++) {
                if (control.cancelled()) {
                    throw new IOException("Export cancelled.");
                }
                Clip clip = clips.get(c);
                int trim = (int) frames(Math.max(0, clip.trimMs));
                int dur = (int) frames(Math.max(0, clip.durMs));
                int start = (int) frames(Math.max(0, clip.startMs));
                if (dur <= 0 || start >= total) {
                    continue;
                }
                short[] pcm;
                double sp = clip.speed >= 0.25 && clip.speed <= 4.0 ? clip.speed : 1.0;
                try {
                    long srcNeed = (long) trim + (long) Math.ceil(dur * sp);
                    pcm = decode(clip.path, srcNeed, control);
                    if (Math.abs(sp - 1.0) > 0.01) {
                        int from = Math.min(trim, pcm.length);
                        int to = (int) Math.min((long) pcm.length, srcNeed);
                        pcm = stretch(Arrays.copyOfRange(pcm, from, Math.max(from, to)), sp, control);
                        trim = 0;
                    }
                } catch (IOException e) {
                    if (String.valueOf(e.getMessage()).contains("no sound")) {
                        continue;
                    }
                    throw e;
                } catch (Exception e) {
                    throw new IOException("Could not read an audio clip: " + e.getMessage());
                }
                int n = Math.min(dur, pcm.length - trim);
                if (n <= 0) {
                    continue;
                }
                int fadeIn = (int) frames(Math.max(0, clip.fadeInMs));
                int fadeOut = (int) frames(Math.max(0, clip.fadeOutMs));
                for (int i = 0; i < n; i++) {
                    int idx = start + i;
                    if (idx >= total) {
                        break;
                    }
                    double g = clip.volume;
                    if (fadeIn > 0 && i < fadeIn) {
                        g *= i / (double) fadeIn;
                    }
                    int remaining = dur - i;
                    if (fadeOut > 0 && remaining < fadeOut) {
                        g *= remaining / (double) fadeOut;
                    }
                    int v = sb.get(idx) + (int) Math.round(pcm[trim + i] * g);
                    sb.put(idx, (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, v)));
                }
            }
            raf.seek(44);
            raf.write(data);
        }
    }

    /** Loudness along a file, [bins] values from 0 to 1. Only the first 5 minutes are read. */
    static float[] peaks(String path, int bins) throws IOException {
        short[] pcm = decode(path, RATE * 300L, NONE);
        float[] out = new float[bins];
        if (pcm.length == 0) {
            return out;
        }
        for (int b = 0; b < bins; b++) {
            int from = (int) ((long) pcm.length * b / bins);
            int to = (int) ((long) pcm.length * (b + 1) / bins);
            int max = 0;
            for (int i = from; i < Math.max(to, from + 1) && i < pcm.length; i++) {
                int a = Math.abs((int) pcm[i]);
                if (a > max) {
                    max = a;
                }
            }
            out[b] = Math.min(1f, max / 32768f);
        }
        return out;
    }

    static void mix(List<Spec> specs, File out, Control control) throws IOException {
        long totalMs = 0;
        for (Spec s : specs) {
            totalMs += s.durationMs;
        }
        long totalFrames = Math.round(totalMs * RATE / 1000.0);

        try (OutputStream os = new BufferedOutputStream(new FileOutputStream(out), 256 * 1024)) {
            writeHeader(os, totalFrames);
            long cumMs = 0;
            long written = 0;
            for (int i = 0; i < specs.size(); i++) {
                if (control.cancelled()) {
                    throw new IOException("Export cancelled.");
                }
                Spec spec = specs.get(i);
                cumMs += spec.durationMs;
                long endFrame = Math.round(cumMs * RATE / 1000.0);
                long sceneFrames = endFrame - written;

                short[] pcm = null;
                if (spec.path != null) {
                    try {
                        double sp = spec.speed >= 0.25 && spec.speed <= 4.0 ? spec.speed : 1.0;
                        pcm = decode(spec.path, (long) Math.ceil(sceneFrames * sp) + RATE / 10, control);
                        if (Math.abs(sp - 1.0) > 0.01) {
                            pcm = stretch(pcm, sp, control);
                        }
                    } catch (IOException e) {
                        throw e;
                    } catch (Exception e) {
                        throw new IOException("Could not read the narration of slide " + (i + 1)
                                + ": " + e.getMessage());
                    }
                    if (spec.clean) {
                        cleanVoice(pcm);
                    }
                    applyGain(pcm, spec.volume);
                }
                writeFrames(os, pcm, sceneFrames);
                written = endFrame;
                control.progress((int) ((i + 1) * 100L / specs.size()));
            }
        }
    }

    /**
     * Makes a copy of an audio file that plays at [speed] with the pitch kept, as a mono WAV
     * long enough for [neededMs] of the lesson.
     */
    static void renderSpeed(String path, double speed, long neededMs, File out, Control control)
            throws IOException {
        long needFrames = frames(neededMs);
        short[] pcm = decode(path, (long) Math.ceil(needFrames * speed) + RATE, control);
        short[] fast = stretch(pcm, speed, control);
        int n = (int) Math.min((long) fast.length, needFrames);
        try (OutputStream os = new BufferedOutputStream(new FileOutputStream(out), 256 * 1024)) {
            writeHeader(os, n);
            writeFrames(os, fast, n);
        }
    }

    /**
     * Changes the speed without changing the pitch (overlap-add with the best matching
     * join). speed 2 makes the sound half as long.
     */
    static short[] stretch(short[] in, double speed, Control control) throws IOException {
        if (Math.abs(speed - 1.0) < 0.01) {
            return in;
        }
        final int win = 1764;          // 40 ms
        final int hs = win / 2;        // output step
        final int tol = 441;           // 10 ms search either side
        int outLen = (int) Math.max(0, Math.round(in.length / speed));
        if (in.length < win * 3 || outLen < win) {
            // too short to stretch cleanly: plain resampling
            short[] out = new short[outLen];
            for (int j = 0; j < outLen; j++) {
                double pos = j * speed;
                int i0 = (int) pos;
                if (i0 >= in.length) {
                    break;
                }
                int s1 = i0 + 1 < in.length ? in[i0 + 1] : in[i0];
                out[j] = (short) Math.round(in[i0] + (s1 - in[i0]) * (pos - i0));
            }
            return out;
        }
        double[] hann = new double[win];
        for (int i = 0; i < win; i++) {
            hann[i] = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * i / win));
        }
        double[] acc = new double[outLen + win * 2];
        for (int i = 0; i < win; i++) {
            acc[i] += in[i] * hann[i];
        }
        int prevStart = 0;
        double ha = hs * speed;
        for (int frame = 1; ; frame++) {
            long outPos = (long) frame * hs;
            if (outPos >= outLen) {
                break;
            }
            if ((frame & 255) == 0 && control.cancelled()) {
                throw new IOException("Export cancelled.");
            }
            int center = (int) Math.round(frame * ha);
            int natural = prevStart + hs;
            if (center + win > in.length || natural + hs > in.length) {
                break;
            }
            int best = center;
            double bestC = -Double.MAX_VALUE;
            int lo = Math.max(0, center - tol);
            int hi = Math.min(center + tol, in.length - win);
            for (int cand = lo; cand <= hi; cand += 3) {
                double c = 0;
                for (int k = 0; k < hs; k += 6) {
                    c += (double) in[cand + k] * in[natural + k];
                }
                if (c > bestC) {
                    bestC = c;
                    best = cand;
                }
            }
            int base = (int) outPos;
            for (int i = 0; i < win; i++) {
                acc[base + i] += in[best + i] * hann[i];
            }
            prevStart = best;
        }
        short[] out = new short[outLen];
        for (int i = 0; i < outLen; i++) {
            long v = Math.round(acc[i]);
            out[i] = (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, v));
        }
        return out;
    }

    // ---- WAV output ----

    private static void writeHeader(OutputStream os, long frames) throws IOException {
        long dataBytes = frames * 2;
        ByteBuffer b = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        b.put(new byte[]{'R', 'I', 'F', 'F'});
        b.putInt((int) (36 + dataBytes));
        b.put(new byte[]{'W', 'A', 'V', 'E'});
        b.put(new byte[]{'f', 'm', 't', ' '});
        b.putInt(16);
        b.putShort((short) 1);
        b.putShort((short) 1);
        b.putInt(RATE);
        b.putInt(RATE * 2);
        b.putShort((short) 2);
        b.putShort((short) 16);
        b.put(new byte[]{'d', 'a', 't', 'a'});
        b.putInt((int) dataBytes);
        os.write(b.array());
    }

    private static void writeFrames(OutputStream os, short[] pcm, long frames) throws IOException {
        final int chunk = 32768;
        byte[] bytes = new byte[chunk * 2];
        long done = 0;
        while (done < frames) {
            int n = (int) Math.min(chunk, frames - done);
            for (int i = 0; i < n; i++) {
                long idx = done + i;
                int v = (pcm != null && idx < pcm.length) ? pcm[(int) idx] : 0;
                bytes[i * 2] = (byte) (v & 0xFF);
                bytes[i * 2 + 1] = (byte) ((v >> 8) & 0xFF);
            }
            os.write(bytes, 0, n * 2);
            done += n;
        }
    }

    // ---- Decoding ----

    private static final class ShortList {
        short[] data = new short[1 << 16];
        int size;

        void add(short v) {
            if (size == data.length) {
                data = Arrays.copyOf(data, data.length * 2);
            }
            data[size++] = v;
        }
    }

    /** Decodes any audio file to mono 16-bit PCM at RATE, at most maxOutFrames long. */
    private static short[] decode(String path, long maxOutFrames, Control control)
            throws IOException {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(path);
            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat f = extractor.getTrackFormat(i);
                String mime = f.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    track = i;
                    format = f;
                    break;
                }
            }
            if (track < 0 || format == null) {
                throw new IOException("The file has no sound.");
            }
            extractor.selectTrack(track);
            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
            codec.configure(format, null, null, 0);
            codec.start();

            int srcRate = format.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                    ? format.getInteger(MediaFormat.KEY_SAMPLE_RATE) : RATE;
            int channels = format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                    ? format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : 1;

            ShortList mono = new ShortList();
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inDone = false;
            boolean outDone = false;
            while (!outDone) {
                if (control.cancelled()) {
                    throw new IOException("Export cancelled.");
                }
                if (!inDone) {
                    int ii = codec.dequeueInputBuffer(10000);
                    if (ii >= 0) {
                        ByteBuffer ib = codec.getInputBuffer(ii);
                        int size = ib == null ? -1 : extractor.readSampleData(ib, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(ii, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inDone = true;
                        } else {
                            codec.queueInputBuffer(ii, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int oi = codec.dequeueOutputBuffer(info, 10000);
                if (oi >= 0) {
                    ByteBuffer ob = codec.getOutputBuffer(oi);
                    if (info.size > 0 && ob != null) {
                        ob.position(info.offset);
                        ob.limit(info.offset + info.size);
                        ShortBuffer sb = ob.order(ByteOrder.nativeOrder()).asShortBuffer();
                        int ch = Math.max(1, channels);
                        int frames = sb.remaining() / ch;
                        for (int f = 0; f < frames; f++) {
                            int sum = 0;
                            for (int c = 0; c < ch; c++) {
                                sum += sb.get();
                            }
                            mono.add((short) (sum / ch));
                        }
                    }
                    codec.releaseOutputBuffer(oi, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outDone = true;
                    }
                    long limit = (long) ((maxOutFrames + 2000) * (double) srcRate / RATE) + 1;
                    if (mono.size >= limit) {
                        outDone = true;
                    }
                } else if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat f = codec.getOutputFormat();
                    if (f.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        srcRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    }
                    if (f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    }
                }
            }
            return resample(mono.data, mono.size, srcRate, maxOutFrames);
        } finally {
            if (codec != null) {
                try {
                    codec.stop();
                } catch (Exception ignored) {
                    // nothing to do
                }
                try {
                    codec.release();
                } catch (Exception ignored) {
                    // nothing to do
                }
            }
            extractor.release();
        }
    }

    private static short[] resample(short[] src, int len, int srcRate, long maxOut) {
        if (srcRate <= 0) {
            srcRate = RATE;
        }
        if (srcRate == RATE) {
            return Arrays.copyOf(src, (int) Math.min(len, maxOut));
        }
        long outLen = Math.min((long) len * RATE / srcRate, maxOut);
        short[] out = new short[(int) outLen];
        double step = (double) srcRate / RATE;
        for (int j = 0; j < out.length; j++) {
            double pos = j * step;
            int i0 = (int) pos;
            double frac = pos - i0;
            int s0 = src[i0];
            int s1 = i0 + 1 < len ? src[i0 + 1] : s0;
            out[j] = (short) Math.round(s0 + (s1 - s0) * frac);
        }
        return out;
    }

    private static void applyGain(short[] pcm, float gain) {
        if (Math.abs(gain - 1f) < 0.001f) {
            return;
        }
        for (int i = 0; i < pcm.length; i++) {
            int v = Math.round(pcm[i] * gain);
            pcm[i] = (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, v));
        }
    }

    // ---- Voice cleaning: high-pass about 90 Hz, then a gentle noise gate ----

    private static void cleanVoice(short[] pcm) {
        if (pcm.length < RATE / 5) {
            return;
        }
        highPass(pcm, 90.0);
        gate(pcm);
    }

    private static void highPass(short[] pcm, double fc) {
        double w0 = 2.0 * Math.PI * fc / RATE;
        double cosw = Math.cos(w0);
        double alpha = Math.sin(w0) / (2.0 * 0.7071);
        double a0 = 1.0 + alpha;
        double b0 = ((1.0 + cosw) / 2.0) / a0;
        double b1 = (-(1.0 + cosw)) / a0;
        double b2 = b0;
        double a1 = (-2.0 * cosw) / a0;
        double a2 = (1.0 - alpha) / a0;
        double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
        for (int i = 0; i < pcm.length; i++) {
            double x0 = pcm[i];
            double y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
            x2 = x1;
            x1 = x0;
            y2 = y1;
            y1 = y0;
            long r = Math.round(y0);
            pcm[i] = (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, r));
        }
    }

    private static void gate(short[] pcm) {
        final int win = RATE / 50; // 20 ms
        int count = pcm.length / win;
        if (count < 10) {
            return;
        }
        float[] level = new float[count];
        for (int w = 0; w < count; w++) {
            double sum = 0;
            int base = w * win;
            for (int i = 0; i < win; i++) {
                double v = pcm[base + i];
                sum += v * v;
            }
            level[w] = (float) Math.sqrt(sum / win);
        }
        float[] sorted = level.clone();
        Arrays.sort(sorted);
        float floor = sorted[(int) (count * 0.10f)];
        float loud = sorted[(int) (count * 0.90f)];
        // Not enough difference between quiet and loud parts: leave the voice alone.
        if (loud < floor * 4f || loud < 400f) {
            return;
        }
        float openThr = Math.max(floor * 2.5f, 150f);
        openThr = Math.min(openThr, loud * 0.25f);
        float closeThr = openThr * 0.7f;

        boolean[] open = new boolean[count];
        boolean state = false;
        int hold = 0;
        final int holdWindows = 8; // 160 ms
        for (int w = 0; w < count; w++) {
            if (level[w] >= (state ? closeThr : openThr)) {
                state = true;
                hold = holdWindows;
            } else if (hold > 0) {
                hold--;
            } else {
                state = false;
            }
            open[w] = state;
        }
        // Open one window early so the start of a word is not cut.
        boolean[] target = new boolean[count];
        for (int w = 0; w < count; w++) {
            target[w] = open[w] || (w + 1 < count && open[w + 1]);
        }

        final float closedGain = 0.2f;
        double atk = 1.0 - Math.exp(-1.0 / (0.008 * RATE));
        double rel = 1.0 - Math.exp(-1.0 / (0.15 * RATE));
        double g = 1.0;
        for (int i = 0; i < pcm.length; i++) {
            int w = Math.min(count - 1, i / win);
            double t = target[w] ? 1.0 : closedGain;
            g += (t - g) * (t > g ? atk : rel);
            pcm[i] = (short) Math.round(pcm[i] * g);
        }
    }
}
