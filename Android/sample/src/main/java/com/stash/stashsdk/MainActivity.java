package com.stash.stashsdk;

import android.app.AlertDialog;
import android.os.Bundle;
import android.util.Log;
import androidx.appcompat.app.AppCompatActivity;
import androidx.lifecycle.ViewModelProvider;
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory;
import androidx.recyclerview.widget.LinearLayoutManager;
import com.stash.popup.StashPayCard;
import com.stash.stashsdk.databinding.ActivityMainBinding;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;
import org.json.JSONObject;

/**
 * Sample activity demonstrating StashPayCard SDK integration.
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
    });

    binding.recyclerView.setLayoutManager(new LinearLayoutManager(this));
    binding.recyclerView.setAdapter(adapter);

    viewModel.getItems().observe(this, items -> {
      if (items != null) {
        adapter.submitList(items);
      }
    });

    StashPayCard stashPayCard = StashPayCard.getInstance();
    stashPayCard.setActivity(this);
    stashPayCard.setListener(new StashPayCard.StashPayListener() {
      @Override
      public void onPaymentSuccess() {
        Log.i(TAG, "Payment successful");
        runOnUiThread(() -> showOutcomeDialog("Success", "Purchase Successful"));
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
    });

    viewModel.refreshList();
  }

  private StashPayCard.CardConfig buildCardConfig() {
    StashPayCard.CardConfig config = new StashPayCard.CardConfig();
    config.forcePortrait = viewModel.isForcePortraitOnCheckout();
    config.cardHeightRatioPortrait = (viewModel.getPhoneCardHeight() + 10) / 100f;
    config.cardWidthRatioLandscape = (viewModel.getCheckoutPhoneLandscapeW() + 10) / 100f;
    config.cardHeightRatioLandscape = (viewModel.getCheckoutPhoneLandscapeH() + 10) / 100f;
    config.tabletWidthRatioPortrait = (viewModel.getCheckoutTabletPortraitW() + 10) / 100f;
    config.tabletHeightRatioPortrait = (viewModel.getCheckoutTabletPortraitH() + 10) / 100f;
    config.tabletWidthRatioLandscape = (viewModel.getCheckoutTabletLandscapeW() + 10) / 100f;
    config.tabletHeightRatioLandscape = (viewModel.getCheckoutTabletLandscapeH() + 10) / 100f;
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
    StashPayCard.CardConfig config = buildCardConfig();
    StashPayCard.getInstance().openCard(url.trim(), config);
  }

  private void openBrowser() {
    String url = viewModel.getBrowserUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_checkout_url));
      return;
    }
    StashPayCard.getInstance().openBrowser(url.trim());
  }

  private void openModal() {
    String url = viewModel.getModalUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_modal_url));
      return;
    }
    StashPayCard.ModalConfig config = buildModalConfig();
    StashPayCard.getInstance().openModal(url.trim(), config);
  }

  private void generateCheckout() {
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
        user.put("id", "test.user");
        user.put("validatedEmail", "test@stash.gg");
        user.put("platform", "ANDROID");
        JSONObject item = new JSONObject();
        item.put("id", "test-item");
        item.put("name", "Test Purchase");
        item.put("pricePerItem", "0.99");
        item.put("quantity", 1);
        item.put("imageUrl",
            "https://api.braincloudservers.com/files/portal/g/15152/metadata/products/potion_pack.png");
        item.put("description", "This is a test item purchase.");
        JSONObject body = new JSONObject();
        body.put("user", user);
        body.put("item", item);
        body.put("currency", "USD");

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
            runOnUiThread(() -> {
              StashPayCard.CardConfig config = buildCardConfig();
              StashPayCard.getInstance().openCard(checkoutUrl, config);
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

  private StashPayCard.ModalConfig buildModalConfig() {
    StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();
    config.showDragBar = viewModel.isModalShowDragBar();
    config.allowDismiss = viewModel.isModalAllowDismiss();
    config.phoneWidthRatioPortrait = (viewModel.getModalPhonePortraitW() + 10) / 100f;
    config.phoneHeightRatioPortrait = (viewModel.getModalPhonePortraitH() + 10) / 100f;
    config.phoneWidthRatioLandscape = (viewModel.getModalPhoneLandscapeW() + 10) / 100f;
    config.phoneHeightRatioLandscape = (viewModel.getModalPhoneLandscapeH() + 10) / 100f;
    config.tabletWidthRatioPortrait = (viewModel.getModalTabletPortraitW() + 10) / 100f;
    config.tabletHeightRatioPortrait = (viewModel.getModalTabletPortraitH() + 10) / 100f;
    config.tabletWidthRatioLandscape = (viewModel.getModalTabletLandscapeW() + 10) / 100f;
    config.tabletHeightRatioLandscape = (viewModel.getModalTabletLandscapeH() + 10) / 100f;
    return config;
  }

  @Override
  protected void onResume() {
    super.onResume();
    StashPayCard.getInstance().setActivity(this);
  }

  @Override
  protected void onDestroy() {
    super.onDestroy();
    binding = null;
  }
}
