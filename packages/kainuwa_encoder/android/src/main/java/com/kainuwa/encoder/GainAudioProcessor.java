package com.kainuwa.encoder;

import androidx.annotation.OptIn;
import androidx.media3.common.C;
import androidx.media3.common.audio.BaseAudioProcessor;
import androidx.media3.common.util.UnstableApi;

import java.nio.ByteBuffer;

/**
 * Volume control with optional fade in and fade out for 16-bit PCM audio.
 * Fade times and total length are in microseconds. A value of 0 means no fade.
 */
@OptIn(markerClass = UnstableApi.class)
final class GainAudioProcessor extends BaseAudioProcessor {

    private final float gain;
    private final long fadeInUs;
    private final long fadeOutUs;
    private final long totalUs;
    private long framesSeen;

    GainAudioProcessor(float gain, long fadeInUs, long fadeOutUs, long totalUs) {
        this.gain = gain;
        this.fadeInUs = fadeInUs;
        this.fadeOutUs = fadeOutUs;
        this.totalUs = totalUs;
    }

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat)
            throws UnhandledAudioFormatException {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw new UnhandledAudioFormatException(inputAudioFormat);
        }
        return inputAudioFormat;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        int remaining = inputBuffer.remaining();
        if (remaining == 0) {
            return;
        }
        ByteBuffer output = replaceOutputBuffer(remaining);
        int channels = inputAudioFormat.channelCount;
        int sampleRate = inputAudioFormat.sampleRate;
        int frames = remaining / (2 * channels);

        for (int f = 0; f < frames; f++) {
            long timeUs = framesSeen * 1_000_000L / sampleRate;
            float g = gain;
            if (fadeInUs > 0 && timeUs < fadeInUs) {
                g *= (float) timeUs / (float) fadeInUs;
            }
            if (fadeOutUs > 0 && totalUs > 0 && timeUs > totalUs - fadeOutUs) {
                long left = Math.max(0L, totalUs - timeUs);
                g *= (float) left / (float) fadeOutUs;
            }
            for (int c = 0; c < channels; c++) {
                int sample = Math.round(inputBuffer.getShort() * g);
                if (sample > Short.MAX_VALUE) {
                    sample = Short.MAX_VALUE;
                } else if (sample < Short.MIN_VALUE) {
                    sample = Short.MIN_VALUE;
                }
                output.putShort((short) sample);
            }
            framesSeen++;
        }
        while (inputBuffer.hasRemaining()) {
            output.put(inputBuffer.get());
        }
        output.flip();
    }

    @Override
    protected void onFlush() {
        framesSeen = 0;
    }
}
