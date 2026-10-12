package com.stash.stashnative.consumer;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.stash.stashnative.StashNativeCard;

/** Minimal Java integration built against the release AAR with R8 enabled. */
public class MainActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    LinearLayout layout = new LinearLayout(this);
    layout.setOrientation(LinearLayout.VERTICAL);
    TextView status = new TextView(this);
    StashNativeCard sdk = StashNativeCard.getInstance();
    sdk.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onPageLoaded(long milliseconds) {
        status.setText("Checkout loaded");
      }

      @Override public void onCodeLinkError(StashNativeCard.CodeLinkError error) {
        status.setText(error.name());
      }

      @Override public void onQrCodeScanned(String content) {
        status.setText("QR scanned");
      }
    });
    Button checkout = new Button(this);
    checkout.setText("Open checkout");
    checkout.setOnClickListener(view -> sdk.openCard(
        this, "https://test.stashpreview.com", new StashNativeCard.CardConfig()));
    layout.addView(checkout);
    Button browser = new Button(this);
    browser.setText("Open browser");
    browser.setOnClickListener(view -> sdk.openBrowser(this, "https://test.stashpreview.com"));
    layout.addView(browser);
    Button scanner = new Button(this);
    scanner.setText("Scan QR code");
    scanner.setOnClickListener(view -> sdk.codeLink(this));
    layout.addView(scanner);
    layout.addView(status);
    setContentView(layout);
  }

  @Override
  protected void onDestroy() {
    StashNativeCard.getInstance().resetPresentationState();
    StashNativeCard.getInstance().setListener(null);
    super.onDestroy();
  }
}
