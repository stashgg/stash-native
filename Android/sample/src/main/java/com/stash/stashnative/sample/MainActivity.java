package com.stash.stashnative.sample;

import android.app.AlertDialog;
import android.os.Bundle;
import android.util.Log;
import androidx.appcompat.app.AppCompatActivity;
import androidx.lifecycle.ViewModelProvider;
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory;
import androidx.recyclerview.widget.LinearLayoutManager;
import com.stash.stashnative.StashNativeCard;
import com.stash.stashnative.sample.databinding.ActivityMainBinding;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Sample activity demonstrating StashNativeCard SDK integration.
 * Uses ViewBinding, ViewModel, RecyclerView (Settings pattern).
 */
public class MainActivity extends AppCompatActivity {

  private static final String TAG = "StashNativeDemo";

  private ActivityMainBinding binding;
  private MainViewModel viewModel;
  private SettingsAdapter adapter;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    binding = ActivityMainBinding.inflate(getLayoutInflater());
    setContentView(binding.getRoot());

    viewModel = new ViewModelProvider(
        this, AndroidViewModelFactory.getInstance(getApplication())).get(MainViewModel.class);
    adapter = new SettingsAdapter(viewModel, new SettingsAdapter.Callbacks() {
      @Override
      public void onOpenCard() {
        openCard();
      }

      @Override
      public void onOpenBrowser() {
        openBrowser();
      }

      @Override
      public void onOpenModal() {
        openModal();
      }

      @Override
      public void onGenerateCheckout() {
        generateCheckout();
      }

      @Override
      public void onOpenWebshop() {
        openWebshop();
      }

      @Override
      public void onGenerateCheckoutForBrowser() {
        generateCheckoutForBrowser();
      }
    });

    binding.recyclerView.setLayoutManager(new LinearLayoutManager(this));
    binding.recyclerView.setAdapter(adapter);

    viewModel.getItems().observe(this, items -> {
      if (items != null) {
        adapter.submitList(items);
      }
    });

    StashNativeCard stashPayCard = StashNativeCard.getInstance();
    stashPayCard.setActivity(this);
    stashPayCard.setListener(new StashNativeCard.StashNativeCardListener() {
      @Override
      public void onPaymentSuccess(String order) {
        Log.i(TAG, "Payment successful order=" + order);
        String msg = order != null && !order.isEmpty()
            ? "Purchase Successful\n\nOrder:\n" + order
            : "Purchase Successful";
        runOnUiThread(() -> showOutcomeDialog("Success", msg));
      }

      @Override
      public void onPaymentFailure() {
        Log.i(TAG, "Payment failed");
        runOnUiThread(() -> showOutcomeDialog("Payment Failed", "Purchase Failed"));
      }

      @Override
      public void onDialogDismissed() {
        Log.i(TAG, "Dialog dismissed");
      }

      @Override
      public void onOptInResponse(String optinType) {
        Log.i(TAG, "Opt-in response: " + optinType);
        runOnUiThread(() -> showOutcomeDialog("Opt-in", "Opt-in Selected: " + optinType));
      }

      @Override
      public void onPageLoaded(long loadTimeMs) {
        Log.i(TAG, "Page loaded in " + loadTimeMs + "ms");
      }

      @Override
      public void onNetworkError() {
        Log.e(TAG, "Network error");
      }

      @Override
      public void onExternalPayment(String url) {
        Log.i(TAG, "External payment URL: " + url);
        runOnUiThread(() -> showOutcomeDialog(
            "External payment",
            "Opening in browser:\n" + (url != null ? url : "")));
      }
    });

    viewModel.refreshList();
  }

  private StashNativeCard.CardConfig buildCardConfig() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.forcePortrait = viewModel.isForcePortraitOnCheckout();
    config.cardHeightRatioPortrait = (viewModel.getPhoneCardHeight() + 10) / 100f;
    config.cardWidthRatioLandscape = (viewModel.getCheckoutPhoneLandscapeW() + 10) / 100f;
    config.cardHeightRatioLandscape = (viewModel.getCheckoutPhoneLandscapeH() + 10) / 100f;
    config.tabletWidthRatioPortrait = (viewModel.getCheckoutTabletPortraitW() + 10) / 100f;
    config.tabletHeightRatioPortrait = (viewModel.getCheckoutTabletPortraitH() + 10) / 100f;
    config.tabletWidthRatioLandscape = (viewModel.getCheckoutTabletLandscapeW() + 10) / 100f;
    config.tabletHeightRatioLandscape = (viewModel.getCheckoutTabletLandscapeH() + 10) / 100f;
    String bg = viewModel.getCardBackgroundColorHex();
    if (bg != null && !bg.trim().isEmpty()) {
      config.backgroundColor = bg.trim();
    }
    return config;
  }

  private void showOutcomeDialog(String title, String message) {
    new AlertDialog.Builder(this)
        .setTitle(title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show();
  }

  private void openCard() {
    String url = viewModel.getCheckoutUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_checkout_url));
      return;
    }
    url = url.trim();
    // The browser section still defaults to htmlpreview.github.io (iframe wrapper); card defaults to
    // test.stashpreview.com. Main-frame onPageFinished can fire early for iframe wrappers, so
    // WebView/GPU timing can differ from a direct checkout URL (see generateCheckout()).
    Log.i(TAG, "Opening card (manual URL): " + url);
    StashNativeCard.CardConfig config = buildCardConfig();
    StashNativeCard.getInstance().openCard(url, config);
  }

  private void openBrowser() {
    String url = viewModel.getBrowserUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_checkout_url));
      return;
    }
    StashNativeCard.getInstance().openBrowser(url.trim());
  }

  private void openModal() {
    String url = viewModel.getModalUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_modal_url));
      return;
    }
    StashNativeCard.ModalConfig config = buildModalConfig();
    StashNativeCard.getInstance().openModal(url.trim(), config);
  }

  /**
   * Fetches a real checkout URL from the Stash API and opens it in the card. This is the most
   * representative end-to-end path and the best way to reproduce WebView/Chromium issues on an
   * emulator (e.g. GLES init failure in gl_version_info.cc) because the checkout SPA loads in the
   * main frame—unlike the default htmlpreview.github.io test URL, which may finish the main
   * document early while the real page loads in a subframe.
   */
  private void generateCheckout() {
    generateQuickPayCheckout(false);
  }

  private void generateCheckoutForBrowser() {
    generateQuickPayCheckout(true);
  }

  private void openWebshop() {
    generateAuthenticatedWebshopUrl();
  }

  /**
   * POSTs to generate_quick_pay_url and opens the returned URL in the card or in the browser.
   */
  private void generateQuickPayCheckout(boolean openInBrowser) {
    String baseUrl = viewModel.isUseTestApi() ? "https://test-api.stash.gg" : "https://api.stash.gg";
    String urlString = baseUrl + "/sdk/server/checkout_links/generate_quick_pay_url";
    String rawKey = viewModel.getStashApiKey() != null ? viewModel.getStashApiKey().trim() : "";
    final String apiKey = rawKey.isEmpty() ? MainViewModel.DEFAULT_STASH_API_KEY : rawKey;

    Executors.newSingleThreadExecutor().execute(() -> {
      HttpURLConnection conn = null;
      try {
        URL url = new URL(urlString);
        conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setRequestProperty("x-stash-api-key", apiKey);
        conn.setDoOutput(true);
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(15000);

        JSONObject user = new JSONObject();
        user.put("id", "7849fbc5-87fd-446d-8d9c-de25298f1092");
        user.put("validatedEmail", "test@stash.gg");
        user.put("displayName", "Test User");
        user.put("profileImageUrl",
            "https://storage.googleapis.com/stash-demo-f9550.firebasestorage.app/avatars/6564ced3-c163-4b0d-aa4e-c1a19e42aa65.png");
        user.put("platform", "ANDROID");
        JSONObject item = new JSONObject();
        item.put("id", "realMoneyProduct_gems_001");
        item.put("name", "Handful of Blackstone");
        item.put("pricePerItem", "1.99");
        item.put("quantity", 1);
        item.put("imageUrl", "https://static.stash.gg/stash_logo_128.png");
        JSONObject bonusItem = new JSONObject();
        bonusItem.put("id", "196492b7-78f1-4875-bfb5-ff612b46c1f9");
        bonusItem.put("name", "Bonus Item");
        bonusItem.put("imageUrl", "https://static.stash.gg/stash_logo_128.png");
        bonusItem.put("quantity", 1);
        JSONArray bonusItems = new JSONArray();
        bonusItems.put(bonusItem);
        JSONObject body = new JSONObject();
        body.put("user", user);
        body.put("item", item);
        body.put("currency", "USD");
        body.put("createPaymentIntent", true);
        body.put("transactionId", "6ef37116-e16f-43c6-ac72-8741c0bbd2b5");
        body.put("regionCode", "US");
        body.put("bonusItems", bonusItems);

        byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
        conn.setFixedLengthStreamingMode(bytes.length);
        try (OutputStream os = conn.getOutputStream()) {
          os.write(bytes);
        }

        int code = conn.getResponseCode();
        if (code >= 200 && code < 300) {
          java.util.Scanner scanner = new java.util.Scanner(
              conn.getInputStream(), StandardCharsets.UTF_8.name()).useDelimiter("\\A");
          String response = scanner.hasNext() ? scanner.next() : "";
          scanner.close();
          JSONObject json = new JSONObject(response);
          String checkoutUrl = json.optString("url", null);
          if (checkoutUrl != null && !checkoutUrl.isEmpty()) {
            final String finalUrl = checkoutUrl;
            runOnUiThread(() -> {
              if (openInBrowser) {
                Log.i(TAG, "Opening browser (generate checkout URL): " + finalUrl);
                StashNativeCard.getInstance().openBrowser(finalUrl.trim());
              } else {
                Log.i(TAG, "Opening card (generate checkout URL): " + finalUrl);
                StashNativeCard.CardConfig config = buildCardConfig();
                StashNativeCard.getInstance().openCard(finalUrl, config);
              }
            });
            return;
          }
        }
      } catch (Exception e) {
        Log.e(TAG, "Generate checkout failed", e);
      } finally {
        if (conn != null) {
          conn.disconnect();
        }
      }
      runOnUiThread(() -> showOutcomeDialog(
          "Error", getString(R.string.error_generate_checkout_url)));
    });
  }

  /**
   * POSTs to /sdk/server/generate_url and opens the returned authenticated webshop URL in card.
   */
  private void generateAuthenticatedWebshopUrl() {
    String baseUrl = viewModel.isUseTestApi() ? "https://test-api.stash.gg" : "https://api.stash.gg";
    String urlString = baseUrl + "/sdk/server/generate_url";
    String rawKey = viewModel.getStashApiKey() != null ? viewModel.getStashApiKey().trim() : "";
    final String apiKey = rawKey.isEmpty() ? MainViewModel.DEFAULT_STASH_API_KEY : rawKey;

    Executors.newSingleThreadExecutor().execute(() -> {
      HttpURLConnection conn = null;
      try {
        URL url = new URL(urlString);
        conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setRequestProperty("x-stash-api-key", apiKey);
        conn.setDoOutput(true);
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(15000);

        JSONObject user = new JSONObject();
        user.put("id", "7849fbc5-87fd-446d-8d9c-de25298f1092");
        user.put("validatedEmail", "test@stash.gg");
        user.put("displayName", "Test User");
        user.put("platform", "ANDROID");

        JSONObject body = new JSONObject();
        body.put("user", user);
        body.put("target", "STORE");

        byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
        conn.setFixedLengthStreamingMode(bytes.length);
        try (OutputStream os = conn.getOutputStream()) {
          os.write(bytes);
        }

        int code = conn.getResponseCode();
        if (code >= 200 && code < 300) {
          java.util.Scanner scanner = new java.util.Scanner(
              conn.getInputStream(), StandardCharsets.UTF_8.name()).useDelimiter("\\A");
          String response = scanner.hasNext() ? scanner.next() : "";
          scanner.close();
          JSONObject json = new JSONObject(response);
          String webshopUrl = json.optString("url", null);
          if (webshopUrl != null && !webshopUrl.isEmpty()) {
            final String finalUrl = webshopUrl.trim();
            runOnUiThread(() -> {
              Log.i(TAG, "Opening card (authenticated webshop URL): " + finalUrl);
              StashNativeCard.CardConfig config = buildCardConfig();
              StashNativeCard.getInstance().openCard(finalUrl, config);
            });
            return;
          }
        }
      } catch (Exception e) {
        Log.e(TAG, "Generate authenticated webshop URL failed", e);
      } finally {
        if (conn != null) {
          conn.disconnect();
        }
      }
      runOnUiThread(() -> showOutcomeDialog(
          "Error", getString(R.string.error_generate_webshop_url)));
    });
  }

  private StashNativeCard.ModalConfig buildModalConfig() {
    StashNativeCard.ModalConfig config = new StashNativeCard.ModalConfig();
    config.allowDismiss = viewModel.isModalAllowDismiss();
    config.phoneWidthRatioPortrait = (viewModel.getModalPhonePortraitW() + 10) / 100f;
    config.phoneHeightRatioPortrait = (viewModel.getModalPhonePortraitH() + 10) / 100f;
    config.phoneWidthRatioLandscape = (viewModel.getModalPhoneLandscapeW() + 10) / 100f;
    config.phoneHeightRatioLandscape = (viewModel.getModalPhoneLandscapeH() + 10) / 100f;
    config.tabletWidthRatioPortrait = (viewModel.getModalTabletPortraitW() + 10) / 100f;
    config.tabletHeightRatioPortrait = (viewModel.getModalTabletPortraitH() + 10) / 100f;
    config.tabletWidthRatioLandscape = (viewModel.getModalTabletLandscapeW() + 10) / 100f;
    config.tabletHeightRatioLandscape = (viewModel.getModalTabletLandscapeH() + 10) / 100f;
    String bg = viewModel.getModalBackgroundColorHex();
    if (bg != null && !bg.trim().isEmpty()) {
      config.backgroundColor = bg.trim();
    }
    return config;
  }

  @Override
  protected void onResume() {
    super.onResume();
    StashNativeCard.getInstance().setActivity(this);
  }

  @Override
  protected void onDestroy() {
    StashNativeCard.getInstance().setListener(null);
    binding = null;
    super.onDestroy();
  }
}
