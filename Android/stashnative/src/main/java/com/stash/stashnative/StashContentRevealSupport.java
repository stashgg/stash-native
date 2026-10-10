package com.stash.stashnative;

import android.annotation.SuppressLint;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.webkit.WebView;

/** Keeps the initial cover until checkout has applied its theme and painted real content. */
final class StashContentRevealSupport {
  private static final long WAIT_MS = 15000;
  private static final long POLL_MS = 100;
  private static final String READY_SCRIPT =
      "(function(){try{"
          + "var u=new URL(document.URL);"
          + "if(u.username||u.password||"
          + "(u.origin!=='https://checkout.stash.gg'&&"
          + "u.origin!=='https://checkout.stashstaging.com'))return true;"
          + "var themes=u.searchParams.getAll('theme');"
          + "if(themes.length===1&&(themes[0]==='light'||themes[0]==='dark')&&"
          + "document.documentElement.getAttribute('data-color-scheme')!==themes[0])return false;"
          + "var nodes=document.querySelectorAll('.animate-skeletonOpacityFluctuation');"
          + "for(var i=0;i<nodes.length;i++){var e=nodes[i],r=e.getBoundingClientRect();"
          + "if(r.width<=0||r.height<=0||r.bottom<=0||r.right<=0||"
          + "r.top>=innerHeight||r.left>=innerWidth)continue;"
          + "var visible=true;for(var p=e;p;p=p.parentElement){var s=getComputedStyle(p);"
          + "if(s.display==='none'||s.visibility!=='visible'||Number(s.opacity)===0){"
          + "visible=false;break;}}if(visible)return false;}return true;"
          + "}catch(e){return null;}})()";

  private final StashCheckoutActivity activity;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final Runnable poll = this::check;
  private long elapsed;
  private long foregroundStart = -1;
  private int generation;
  private boolean started;
  private boolean finished;
  private boolean pending;
  private boolean done;
  private boolean disposed;

  StashContentRevealSupport(StashCheckoutActivity activity) {
    this.activity = activity;
  }

  void navigationStarted() {
    if (disposed || activity.webViewLoadingRevealComplete) {
      return;
    }
    generation++;
    pending = false;
    finished = false;
    done = false;
    started = true;
    if (activity.webViewRevealAnimationRunning) {
      StashCheckoutWebViewSupport.cancelLoadingRevealAnimation(activity);
    }
    check();
  }

  void documentFinished() {
    finished = true;
    check();
  }

  void check() {
    handler.removeCallbacks(poll);
    if (!active() || !started || activity.isActivityPaused) {
      return;
    }
    long now = SystemClock.uptimeMillis();
    if (foregroundStart < 0) {
      foregroundStart = now;
    }
    if (elapsed + now - foregroundStart >= WAIT_MS && activity.mainFrameNavigationCommitted) {
      reveal();
      return;
    }
    handler.postDelayed(poll, POLL_MS);
    if (pending || !finished || !activity.mainFrameNavigationCommitted) {
      return;
    }
    pending = true;
    probe(activity.webView, generation, true);
  }

  private boolean active() {
    return !disposed && !done && !activity.isDismissing && !activity.networkErrorHandled
        && !activity.mainFrameErrorReceived && activity.webView != null
        && !activity.webViewLoadingRevealComplete;
  }

  private boolean current(WebView web, int token) {
    return active() && !activity.isActivityPaused && web == activity.webView && token == generation;
  }

  private void probe(WebView web, int token, boolean waitForPaint) {
    try {
      web.evaluateJavascript(READY_SCRIPT, result -> {
        if (!current(web, token)) {
          return;
        }
        if ("false".equals(result)) {
          pending = false;
        } else if (waitForPaint) {
          afterPaint(web, token);
        } else {
          reveal();
        }
      });
    } catch (RuntimeException ignored) {
      if (current(web, token)) {
        reveal();
      }
    }
  }

  // Keep the older-provider fallback usable by AAR-only hosts without AndroidX WebKit.
  @SuppressLint("WebViewApiAvailability")
  private void afterPaint(WebView web, int token) {
    Runnable verify = () -> {
      if (current(web, token)) {
        probe(web, token, false);
      }
    };
    if (Build.VERSION.SDK_INT >= 23) {
      try {
        web.postVisualStateCallback(token, new WebView.VisualStateCallback() {
          @Override
          public void onComplete(long requestId) {
            verify.run();
          }
        });
        return;
      } catch (RuntimeException ignored) {
        // Older providers may not implement the platform's paint callback.
      }
    }
    handler.postDelayed(verify, 50);
  }

  private void reveal() {
    done = true;
    generation++;
    pending = false;
    handler.removeCallbacks(poll);
    StashCheckoutWebViewSupport.revealWebViewAndRemoveLoading(activity);
  }

  void pause() {
    if (foregroundStart >= 0) {
      elapsed += SystemClock.uptimeMillis() - foregroundStart;
      foregroundStart = -1;
    }
    generation++;
    pending = false;
    handler.removeCallbacks(poll);
  }

  void dispose() {
    disposed = true;
    generation++;
    handler.removeCallbacksAndMessages(null);
  }
}
