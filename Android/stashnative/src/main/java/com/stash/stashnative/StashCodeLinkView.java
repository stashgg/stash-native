package com.stash.stashnative;

import android.animation.ValueAnimator;
import android.annotation.SuppressLint;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.RenderEffect;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.provider.Settings;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.accessibility.AccessibilityManager;
import android.view.animation.OvershootInterpolator;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import androidx.camera.view.PreviewView;

/** Camera chrome inside the shared card; all controls avoid its bottom system inset. */
@SuppressLint("ViewConstructor") // Created by the card; never inflated from XML.
final class StashCodeLinkView extends FrameLayout {
  final PreviewView preview;
  private final Guide guide;
  private final TextView heading;
  private final Symbol close;
  private final LinearLayout callout;
  private final LinearLayout status;
  private final TextView statusText;
  private final ProgressBar spinner;
  private final Button settings;
  private final RectF scanFrame = new RectF();
  private LinearLayout confirmation;
  private ImageView frozenPreview;
  private Bitmap frozenImage;
  private int bottomInset;
  private Runnable geometryListener;

  StashCodeLinkView(Context context, Runnable dismiss, Runnable openSettings) {
    super(context);
    setBackgroundColor(Color.BLACK);
    preview = new PreviewView(context);
    preview.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
    preview.setScaleType(PreviewView.ScaleType.FILL_CENTER);
    addView(preview, new LayoutParams(-1, -1));
    guide = new Guide(context);
    addView(guide, new LayoutParams(-1, -1));
    heading = label(R.string.stash_code_link_heading, 20, false);
    addView(heading);
    close = new Symbol(context, Symbol.CLOSE);
    close.setContentDescription(context.getString(R.string.stash_code_link_close));
    close.setBackground(new RippleDrawable(ColorStateList.valueOf(0x44ffffff),
        rounded(0x66747478, 24), null));
    close.setOnClickListener(view -> dismiss.run());
    close.setFocusable(true);
    addView(close);
    callout = new LinearLayout(context);
    callout.setGravity(Gravity.CENTER_VERTICAL);
    callout.setPadding(dp(14), dp(14), dp(14), dp(14));
    callout.setBackground(rounded(0xee1c1c1e, 16));
    Symbol symbol = new Symbol(context, Symbol.SCAN);
    symbol.setBackground(rounded(0xff2c2c2e, 12));
    callout.addView(symbol, new LinearLayout.LayoutParams(dp(44), dp(44)));
    LinearLayout text = new LinearLayout(context);
    text.setOrientation(LinearLayout.VERTICAL);
    TextView title = label(R.string.stash_code_link_callout, 16, true);
    text.addView(title);
    TextView subtitle = label(R.string.stash_code_link_instruction, 13, false);
    subtitle.setTextColor(0xffb7b7bd);
    subtitle.setPadding(0, dp(4), 0, 0);
    text.addView(subtitle);
    LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(0, -2, 1);
    textParams.leftMargin = dp(12);
    callout.addView(text, textParams);
    addView(callout);
    status = new LinearLayout(context);
    status.setOrientation(LinearLayout.VERTICAL);
    status.setGravity(Gravity.CENTER);
    spinner = new ProgressBar(context);
    spinner.setIndeterminateTintList(ColorStateList.valueOf(Color.WHITE));
    status.addView(spinner, new LinearLayout.LayoutParams(dp(28), dp(28)));
    statusText = label(R.string.stash_code_link_starting, 15, false);
    statusText.setGravity(Gravity.CENTER);
    statusText.setPadding(0, dp(12), 0, dp(8));
    status.addView(statusText);
    settings = new Button(context);
    settings.setText(R.string.stash_code_link_settings);
    settings.setTextColor(Color.WHITE);
    settings.setBackground(new RippleDrawable(ColorStateList.valueOf(0x44ffffff),
        rounded(0xff3a3a3c, 20), null));
    settings.setPadding(dp(24), dp(8), dp(24), dp(8));
    settings.setMinHeight(dp(48));
    settings.setOnClickListener(view -> openSettings.run());
    settings.setVisibility(GONE);
    status.addView(settings, new LinearLayout.LayoutParams(-2, -2));
    addView(status);
  }

  RectF scanFrame() {
    return new RectF(scanFrame);
  }

  void setGeometryListener(Runnable listener) {
    geometryListener = listener;
  }

  void setBottomInset(int inset) {
    if (bottomInset != inset) {
      bottomInset = inset;
      requestLayout();
    }
  }

  void showStatus(int message, boolean loading, boolean showSettings) {
    statusText.setText(message);
    spinner.setVisibility(loading ? VISIBLE : GONE);
    settings.setVisibility(showSettings ? VISIBLE : GONE);
    status.setVisibility(VISIBLE);
    guide.setVisibility(loading ? VISIBLE : INVISIBLE);
    requestLayout();
  }

  void cameraReady() {
    status.setVisibility(GONE);
    guide.setVisibility(VISIBLE);
  }

  long showConnected() {
    frozenImage = preview.getBitmap();
    if (frozenImage != null) {
      frozenPreview = new ImageView(getContext());
      frozenPreview.setImageBitmap(frozenImage);
      frozenPreview.setScaleType(ImageView.ScaleType.FIT_XY);
      if (Build.VERSION.SDK_INT >= 31) {
        frozenPreview.setRenderEffect(
            RenderEffect.createBlurEffect(dp(16), dp(16), Shader.TileMode.CLAMP));
      }
      addView(frozenPreview, 1, new LayoutParams(-1, -1));
    }
    heading.setVisibility(INVISIBLE);
    close.setVisibility(INVISIBLE);
    callout.setVisibility(INVISIBLE);
    guide.setVisibility(INVISIBLE);
    status.setVisibility(GONE);
    confirmation = new LinearLayout(getContext());
    confirmation.setOrientation(LinearLayout.VERTICAL);
    confirmation.setGravity(Gravity.CENTER);
    confirmation.setBackgroundColor(0xd91c1c1e);
    confirmation.setClickable(true);
    Symbol check = new Symbol(getContext(), Symbol.CHECK);
    confirmation.addView(check, new LinearLayout.LayoutParams(dp(80), dp(80)));
    TextView title = label(R.string.stash_code_link_connected, 22, true);
    title.setGravity(Gravity.CENTER);
    title.setPadding(0, dp(12), 0, 0);
    confirmation.addView(title);
    addView(confirmation, new LayoutParams(-1, -1));
    if (animationsEnabled()) {
      confirmation.setAlpha(0);
      confirmation.animate().alpha(1).setDuration(200).start();
      check.setScaleX(0.82f);
      check.setScaleY(0.82f);
      check.animate().scaleX(1).scaleY(1).setDuration(400)
          .setInterpolator(new OvershootInterpolator(0.7f)).start();
    }
    performHapticFeedback(Build.VERSION.SDK_INT >= 30
        ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY);
    announceForAccessibility(getContext().getString(R.string.stash_code_link_connected));
    AccessibilityManager accessibility =
        (AccessibilityManager) getContext().getSystemService(Context.ACCESSIBILITY_SERVICE);
    int delay = accessibility != null && accessibility.isTouchExplorationEnabled() ? 1400 : 850;
    if (Build.VERSION.SDK_INT >= 29 && accessibility != null) {
      delay = accessibility.getRecommendedTimeoutMillis(
          delay, AccessibilityManager.FLAG_CONTENT_TEXT);
    }
    return delay;
  }

  void dispose() {
    geometryListener = null;
    if (confirmation != null) {
      confirmation.animate().cancel();
      for (int index = 0; index < confirmation.getChildCount(); index++) {
        confirmation.getChildAt(index).animate().cancel();
      }
    }
    if (frozenPreview != null) {
      frozenPreview.setImageDrawable(null);
    }
    // RenderThread may still use the bitmap this frame; let it release the pixel storage.
    frozenImage = null;
  }

  private boolean animationsEnabled() {
    return Build.VERSION.SDK_INT >= 26 ? ValueAnimator.areAnimatorsEnabled()
        : Settings.Global.getFloat(getContext().getContentResolver(),
            Settings.Global.ANIMATOR_DURATION_SCALE, 1) != 0;
  }

  @Override
  protected void onMeasure(int widthSpec, int heightSpec) {
    super.onMeasure(widthSpec, heightSpec);
    int width = getMeasuredWidth();
    heading.measure(MeasureSpec.makeMeasureSpec(Math.max(0, width - dp(104)), MeasureSpec.AT_MOST),
        MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
    close.measure(MeasureSpec.makeMeasureSpec(dp(48), MeasureSpec.EXACTLY),
        MeasureSpec.makeMeasureSpec(dp(48), MeasureSpec.EXACTLY));
    int available = Math.max(0, width - dp(32));
    callout.measure(MeasureSpec.makeMeasureSpec(available, MeasureSpec.EXACTLY),
        MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
    status.measure(MeasureSpec.makeMeasureSpec(Math.max(0, width - dp(48)), MeasureSpec.EXACTLY),
        MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
  }

  @Override
  protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
    super.onLayout(changed, left, top, right, bottom);
    int width = getWidth();
    int height = getHeight();
    int headerTop = dp(24);
    close.layout(width - dp(64), headerTop, width - dp(16), headerTop + dp(48));
    int headingTop = headerTop + Math.max(0, (dp(48) - heading.getMeasuredHeight()) / 2);
    heading.layout(dp(20), headingTop, dp(20) + heading.getMeasuredWidth(),
        headingTop + heading.getMeasuredHeight());
    int calloutBottom = height - bottomInset - dp(16);
    int calloutTop = Math.max(headerTop + dp(48), calloutBottom - callout.getMeasuredHeight());
    callout.layout(dp(16), calloutTop, width - dp(16), calloutBottom);
    float start = Math.max(heading.getBottom(), close.getBottom()) + dp(20);
    float end = calloutTop - dp(20);
    float side = Math.max(0, Math.min((width - dp(32)) * 0.84f, end - start));
    final RectF previousFrame = new RectF(scanFrame);
    scanFrame.set((width - side) / 2, start + Math.max(0, (end - start - side) / 2),
        (width + side) / 2, start + Math.max(0, (end - start - side) / 2) + side);
    int statusTop = Math.round((start + end - status.getMeasuredHeight()) / 2);
    status.layout(dp(24), statusTop, width - dp(24), statusTop + status.getMeasuredHeight());
    guide.invalidate();
    if (geometryListener != null && (changed || !previousFrame.equals(scanFrame))) {
      geometryListener.run();
    }
  }

  private TextView label(int text, int size, boolean bold) {
    TextView label = new TextView(getContext());
    label.setText(text);
    label.setTextColor(Color.WHITE);
    label.setTextSize(size);
    if (bold) {
      label.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
    }
    return label;
  }

  private GradientDrawable rounded(int color, int radius) {
    GradientDrawable drawable = new GradientDrawable();
    drawable.setColor(color);
    drawable.setCornerRadius(dp(radius));
    return drawable;
  }

  private int dp(float value) {
    return Math.round(value * getResources().getDisplayMetrics().density);
  }

  private final class Guide extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path shade = new Path();

    Guide(Context context) {
      super(context);
      setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    @Override protected void onDraw(Canvas canvas) {
      float radius = Math.min(dp(28), scanFrame.width() / 8);
      shade.reset();
      shade.setFillType(Path.FillType.EVEN_ODD);
      shade.addRect(0, 0, getWidth(), getHeight(), Path.Direction.CW);
      shade.addRoundRect(scanFrame, radius, radius, Path.Direction.CW);
      paint.setStyle(Paint.Style.FILL);
      paint.setColor(0x44000000);
      canvas.drawPath(shade, paint);
      paint.setStyle(Paint.Style.STROKE);
      paint.setStrokeWidth(dp(2));
      paint.setColor(Color.WHITE);
      canvas.drawRoundRect(scanFrame, radius, radius, paint);
    }
  }

  private static final class Symbol extends View {
    static final int CLOSE = 0;
    static final int SCAN = 1;
    static final int CHECK = 2;
    private final int kind;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();

    Symbol(Context context, int kind) {
      super(context);
      this.kind = kind;
      setImportantForAccessibility(kind == CLOSE
          ? IMPORTANT_FOR_ACCESSIBILITY_YES : IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    @Override protected void onDraw(Canvas canvas) {
      canvas.save();
      canvas.scale(getWidth() / 48f, getHeight() / 48f);
      paint.setColor(Color.WHITE);
      paint.setStyle(Paint.Style.STROKE);
      paint.setStrokeWidth(kind == CHECK ? 1.5f : 1.8f);
      paint.setStrokeCap(Paint.Cap.ROUND);
      paint.setStrokeJoin(Paint.Join.ROUND);
      path.reset();
      if (kind == CHECK) {
        canvas.drawCircle(24, 24, 19, paint);
        path.moveTo(15, 24);
        path.lineTo(21, 30);
        path.lineTo(33, 18);
      } else if (kind == CLOSE) {
        path.moveTo(18, 18);
        path.lineTo(30, 30);
        path.moveTo(30, 18);
        path.lineTo(18, 30);
      } else {
        for (int index = 0; index < 4; index++) {
          canvas.save();
          canvas.rotate(index * 90, 24, 24);
          canvas.drawLine(14, 20, 14, 14, paint);
          canvas.drawLine(14, 14, 20, 14, paint);
          canvas.restore();
        }
        path.moveTo(19, 24);
        path.lineTo(29, 24);
      }
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }
}
