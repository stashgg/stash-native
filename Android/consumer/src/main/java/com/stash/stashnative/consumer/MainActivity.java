package com.stash.stashnative.consumer;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.stash.stashnative.StashNative;

/** Minimal Java integration built against the release AAR with R8 enabled. */
public class MainActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    LinearLayout layout = new LinearLayout(this);
    layout.setOrientation(LinearLayout.VERTICAL);
    TextView status = new TextView(this);
    StashNative sdk = StashNative.getInstance();
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onPageLoaded(long milliseconds) {
        status.setText("Checkout loaded");
      }

      @Override public void onCardDismissed() {
        status.setText("Card dismissed");
      }

      @Override public void onScannerDismissed() {
        status.setText("Scanner dismissed");
      }

      @Override public void onBrowserDismissed() {
        status.setText("Browser dismissed");
      }

      @Override public void onScannerError(StashNative.ScannerError error) {
        status.setText(error.name());
      }

      @Override public void onQrCodeScanned(String content) {
        status.setText("QR scanned");
      }
    });
    Button checkout = new Button(this);
    checkout.setText("Open checkout");
    checkout.setOnClickListener(view -> sdk.openCard(
        this, "https://test.stashpreview.com", new StashNative.CardConfig()));
    layout.addView(checkout);
    Button browser = new Button(this);
    browser.setText("Open browser");
    browser.setOnClickListener(view -> sdk.openBrowser(this, "https://test.stashpreview.com"));
    layout.addView(browser);
    Button scanner = new Button(this);
    scanner.setText("Scan QR code");
    scanner.setOnClickListener(view -> sdk.openScanner(this));
    layout.addView(scanner);
    layout.addView(status);
    setContentView(layout);
  }

  @Override
  protected void onDestroy() {
    StashNative.getInstance().resetPresentationState();
    StashNative.getInstance().setListener(null);
    super.onDestroy();
  }
}
