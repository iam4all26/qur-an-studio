package com.kainuwa.encoder;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;

import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.BitmapOverlay;
import androidx.media3.effect.OverlaySettings;

/**
 * A text label drawn on the video with a simple entrance animation.
 * kind: "fade", "slide", "pop" or "zoom".
 */
@OptIn(markerClass = UnstableApi.class)
final class AnimatedTextOverlay extends BitmapOverlay {

    private final Bitmap bitmap;
    private final long startUs;
    private final long durationUs;
    private final String kind;

    AnimatedTextOverlay(Bitmap bitmap, long startUs, long durationUs, String kind) {
        this.bitmap = bitmap;
        this.startUs = Math.max(0L, startUs);
        this.durationUs = Math.max(1L, durationUs);
        this.kind = kind == null ? "fade" : kind;
    }

    static Bitmap renderText(String text) {
        Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        textPaint.setColor(Color.WHITE);
        textPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        float size = 54f;
        textPaint.setTextSize(size);
        float textWidth = textPaint.measureText(text);
        if (textWidth > 1100f) {
            size = size * 1100f / textWidth;
            textPaint.setTextSize(size);
            textWidth = textPaint.measureText(text);
        }
        Paint.FontMetrics fm = textPaint.getFontMetrics();
        int padX = 40;
        int padY = 24;
        int w = (int) Math.ceil(textWidth) + padX * 2;
        int h = (int) Math.ceil(fm.descent - fm.ascent) + padY * 2;

        Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bmp);
        RectF rect = new RectF(4f, 4f, w - 4f, h - 4f);

        Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        fill.setColor(0xFF4C1D95);
        canvas.drawRoundRect(rect, 28f, 28f, fill);

        Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(5f);
        stroke.setColor(0xFFF6C101);
        canvas.drawRoundRect(rect, 28f, 28f, stroke);

        canvas.drawText(text, (w - textWidth) / 2f, padY - fm.ascent, textPaint);
        return bmp;
    }

    @Override
    public Bitmap getBitmap(long presentationTimeUs) {
        return bitmap;
    }

    @Override
    public OverlaySettings getOverlaySettings(long presentationTimeUs) {
        float p;
        if (presentationTimeUs <= startUs) {
            p = 0f;
        } else {
            p = Math.min(1f, (presentationTimeUs - startUs) / (float) durationUs);
        }
        float eased = 1f - (1f - p) * (1f - p) * (1f - p);

        float alpha = eased;
        float x = 0f;
        float scale = 1f;
        switch (kind) {
            case "slide":
                x = -0.35f * (1f - eased);
                break;
            case "pop": {
                float q = p - 1f;
                scale = 1f + 2.70158f * q * q * q + 1.70158f * q * q;
                alpha = Math.min(1f, p * 4f);
                break;
            }
            case "zoom":
                scale = 1.6f - 0.6f * eased;
                break;
            default:
                break;
        }
        if (p <= 0f) {
            alpha = 0f;
        }
        scale = Math.max(0.01f, scale);

        return new OverlaySettings.Builder()
                .setBackgroundFrameAnchor(x, -0.62f)
                .setScale(scale, scale)
                .setAlphaScale(Math.max(0f, Math.min(1f, alpha)))
                .build();
    }
}
