package com.stash.stashnative.sample;

import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
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
import org.json.JSONObject;

/**
 * Sample activity demonstrating StashNativeCard integration.
 */
public class MainActivity extends AppCompatActivity {

  private static final String TAG = "StashNativeDemo";
  private static final String CHECKOUT_PATH = "/sdk/server/checkout_links/generate_quick_pay_url";
  private static final String WEBSHOP_PATH = "/sdk/server/generate_url";
  private static final int NETWORK_TIMEOUT_MS = 15000;

  private ActivityMainBinding binding;
  private MainViewModel viewModel;
  private SettingsAdapter adapter;

  private final java.util.concurrent.ExecutorService networkExecutor =
      Executors.newSingleThreadExecutor();

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

      @Override
      public void onOpenWebshopForBrowser() {
        openWebshopForBrowser();
      }

      @Override
      public void onLockLandscapeChanged(boolean on) {
        viewModel.setLockLandscape(on);
        applyOrientationLock();
      }

      @Override
      public void onDeleteInstance() {
        confirmDeleteInstance();
      }
    });

    binding.recyclerView.setLayoutManager(new LinearLayoutManager(this));
    binding.recyclerView.setAdapter(adapter);

    binding.toolbar.setNavigationOnClickListener(v -> {
      MainViewModel.Screen parent = parentOf(viewModel.getCurrentScreen());
      if (parent != null) {
        viewModel.navigateTo(parent);
      }
    });

    binding.toolbar.setOnMenuItemClickListener(item -> {
      int id = item.getItemId();
      if (id == R.id.action_save_payload) {
        viewModel.savePayload();
        android.widget.Toast.makeText(this, R.string.payload_saved,
            android.widget.Toast.LENGTH_SHORT).show();
        return true;
      } else if (id == R.id.action_reset_payload) {
        viewModel.resetPayloadToDefault();
        return true;
      } else if (id == R.id.action_import_export) {
        showImportExportDialog();
        return true;
      } else if (id == R.id.action_add_instance) {
        showAddApiKeyDialog();
        return true;
      }
      return false;
    });

    binding.bottomNav.setOnItemSelectedListener(item -> {
      int id = item.getItemId();
      if (id == R.id.tab_test) {
        viewModel.navigateTo(MainViewModel.Screen.TEST);
      } else if (id == R.id.tab_settings) {
        viewModel.navigateTo(MainViewModel.Screen.SETTINGS);
      } else if (id == R.id.tab_api) {
        viewModel.navigateTo(MainViewModel.Screen.API);
      }
      return true;
    });

    getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
      @Override
      public void handleOnBackPressed() {
        MainViewModel.Screen parent = parentOf(viewModel.getCurrentScreen());
        if (parent != null) {
          viewModel.navigateTo(parent);
        } else {
          setEnabled(false);
          getOnBackPressedDispatcher().onBackPressed();
        }
      }
    });

    viewModel.getItems().observe(this, items -> {
      if (items != null) {
        adapter.submitList(items);
      }
      updateToolbarForScreen();
    });
    applyOrientationLock();

    StashNativeCard stashPayCard = StashNativeCard.getInstance();
    stashPayCard.setActivity(this);
    StashNativeCard.KeepAliveConfig keepAliveConfig = new StashNativeCard.KeepAliveConfig();
    keepAliveConfig.notificationTitle = "Stash sample";
    keepAliveConfig.notificationText = "Tap to return after paying in the browser";
    stashPayCard.setKeepAliveConfig(keepAliveConfig);
    stashPayCard.setKeepAliveEnabled(viewModel.isKeepAliveEnabled());
    stashPayCard.setListener(new StashNativeCard.StashNativeCardListener() {
      @Override
      public void onPaymentSuccess(String order) {
        Log.i(TAG, "Payment successful order=" + order);
        String label = order != null && !order.isEmpty()
            ? "Payment Success · " + order
            : "Payment Success";
        runOnUiThread(() -> addCallbackChip(label));
      }

      @Override
      public void onPaymentFailure() {
        Log.i(TAG, "Payment failed");
        runOnUiThread(() -> addCallbackChip("Payment Failure"));
      }

      @Override
      public void onDialogDismissed() {
        Log.i(TAG, "Dialog dismissed");
        runOnUiThread(() -> addCallbackChip("Dialog Dismissed"));
      }

      @Override
      public void onOptInResponse(String optinType) {
        Log.i(TAG, "Opt-in response: " + optinType);
        runOnUiThread(() -> addCallbackChip("Opt-In: " + optinType));
      }

      @Override
      public void onPageLoaded(long loadTimeMs) {
        Log.i(TAG, "Page loaded in " + loadTimeMs + "ms");
        runOnUiThread(() -> addCallbackChip("Page Loaded · " + loadTimeMs + " ms"));
      }

      @Override
      public void onNetworkError() {
        Log.e(TAG, "Network error");
        runOnUiThread(() -> addCallbackChip("Network Error"));
      }

      @Override
      public void onExternalPayment(String url) {
        Log.i(TAG, "External payment URL: " + url);
        runOnUiThread(() -> addCallbackChip("External Payment"));
      }

      @Override
      public void onBrowserClosed() {
        Log.i(TAG, "Browser closed");
        runOnUiThread(() -> addCallbackChip("Browser Closed"));
      }
    });


    // Handle a stashdemo:// deeplink that cold-started the app. Recreations (config change,
    // process-death restore) redeliver the same intent; do not re-fire the outcome dialog.
    if (savedInstanceState == null) {
      handleDeepLink(getIntent());
    }
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    // singleTask delivers deeplinks here while the app (and in-app browser) is already running.
    setIntent(intent);
    handleDeepLink(intent);
  }

  // Listens for stashdemo:// deeplinks fired from the test card to simulate a payment redirect.
  private void handleDeepLink(Intent intent) {
    if (intent == null) {
      return;
    }
    Uri data = intent.getData();
    if (data == null || !"stashdemo".equalsIgnoreCase(data.getScheme())) {
      return;
    }
    String url = data.toString();
    Log.i(TAG, "Deeplink received: " + url);
    // singleTask already cleared the Custom Tab above us.
    if (url.contains("stash-pay/success")) {
      addCallbackChip("Deeplink · Payment Success");
    } else if (url.contains("stash-pay/failure")) {
      addCallbackChip("Deeplink · Payment Failure");
    } else if (url.contains("stash-pay/cancel")) {
      addCallbackChip("Deeplink · Cancel");
    } else {
      addCallbackChip("Deeplink · " + url);
    }
  }

  // Slider range is 0-90; +10 maps to 10-100%, /100 converts to 0.1-1.0 ratio.
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
    config.autoClose = viewModel.isCardAutoClose();
    String bg = viewModel.getCardBackgroundColorHex();
    if (bg != null && !bg.trim().isEmpty()) {
      config.backgroundColor = bg.trim();
    }
    return config;
  }

  private void syncKeepAlive() {
    StashNativeCard.getInstance().setKeepAliveEnabled(viewModel.isKeepAliveEnabled());
  }

  private void showOutcomeDialog(String title, String message) {
    // Network completions can land after the activity is gone; showing a dialog then
    // throws BadTokenException.
    if (isFinishing() || isDestroyed()) {
      return;
    }
    activeDialog = new AlertDialog.Builder(this)
        .setTitle(title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show();
  }

  /**
   * The dialog on screen, if any. Only orientation is in configChanges, so a dark-mode or
   * font-scale change recreates this activity and would otherwise leak the dialog window.
   */
  private android.app.Dialog activeDialog;

  /** Safety cap; chips also auto-expire after a few seconds. */
  private static final int MAX_CALLBACK_CHIPS = 6;
  private static final long CALLBACK_CHIP_LIFETIME_MS = 5000L;
  private final java.text.SimpleDateFormat callbackTimeFormat =
      new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US);

  /**
   * Every SDK callback (and deeplink outcome) is surfaced the same way: a full-width row with a
   * timestamp. Tap to dismiss, or let it expire.
   */
  private void addCallbackChip(String label) {
    if (binding == null) {
      return;
    }
    LinearLayout container = binding.callbackChipContainer;

    LinearLayout row = new LinearLayout(this);
    row.setOrientation(LinearLayout.HORIZONTAL);
    row.setGravity(Gravity.CENTER_VERTICAL);
    row.setBackgroundResource(R.drawable.bg_callback_chip);
    row.setPadding(dp(16), dp(11), dp(16), dp(11));
    row.setElevation(dp(3));

    TextView text = new TextView(this);
    text.setText(label);
    text.setTextColor(ContextCompat.getColor(this, R.color.on_primary));
    text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f);
    text.setMaxLines(1);
    text.setEllipsize(TextUtils.TruncateAt.END);
    LinearLayout.LayoutParams textLp = new LinearLayout.LayoutParams(
        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
    text.setLayoutParams(textLp);

    TextView time = new TextView(this);
    time.setText(callbackTimeFormat.format(new java.util.Date()));
    time.setTextColor(ContextCompat.getColor(this, R.color.callback_chip_time));
    time.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
    LinearLayout.LayoutParams timeLp = new LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    timeLp.leftMargin = dp(8);
    time.setLayoutParams(timeLp);

    row.addView(text);
    row.addView(time);

    LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    rowLp.topMargin = dp(8);
    row.setLayoutParams(rowLp);
    row.setOnClickListener(v -> removeCallbackChip(container, v));

    // Newest on top; the stack grows downward and oldest falls off the bottom.
    container.addView(row, 0);
    while (container.getChildCount() > MAX_CALLBACK_CHIPS) {
      container.removeViewAt(container.getChildCount() - 1);
    }

    row.setAlpha(0f);
    row.setTranslationY(-dp(8));
    row.animate().alpha(1f).translationY(0f).setDuration(200).start();

    final View expiring = row;
    row.postDelayed(() -> removeCallbackChip(container, expiring), CALLBACK_CHIP_LIFETIME_MS);
  }

  private void removeCallbackChip(LinearLayout container, View chip) {
    if (chip.getParent() != container) {
      return;
    }
    chip.animate().alpha(0f).translationY(dp(8)).setDuration(200)
        .withEndAction(() -> {
          if (chip.getParent() == container) {
            container.removeView(chip);
          }
        }).start();
  }

  private int dp(int value) {
    return Math.round(value * getResources().getDisplayMetrics().density);
  }

  /** The screen a drill-in returns to: payload editors sit under an instance's details, which
   * sits under the Instances tab; card/modal options sit under Settings. Null for a top-level tab. */
  private MainViewModel.Screen parentOf(MainViewModel.Screen screen) {
    switch (screen) {
      case CHECKOUT_PAYLOAD:
      case WEBSHOP_PAYLOAD:
        return MainViewModel.Screen.INSTANCE_DETAILS;
      case INSTANCE_DETAILS:
        return MainViewModel.Screen.API;
      case CARD_OPTIONS:
      case MODAL_OPTIONS:
        return MainViewModel.Screen.SETTINGS;
      default:
        return null;
    }
  }

  /** Each tab titles the toolbar with its own name; Test keeps the app title. Drill-in sub-screens
   * show a back arrow + their title and keep the bottom-nav highlight in sync: card/modal options
   * stay under Settings; instance details and the payload editors stay under Instances. */
  private void updateToolbarForScreen() {
    if (binding == null) {
      return;
    }
    // Test shows the Stash wordmark logo; every other screen uses a text title.
    MainViewModel.Screen screen = viewModel.getCurrentScreen();
    boolean isTest = screen == MainViewModel.Screen.TEST;
    binding.toolbarLogo.setVisibility(isTest ? View.VISIBLE : View.GONE);
    // Save/Reset live in the app bar, and only on the payload editors.
    boolean isPayload = screen == MainViewModel.Screen.CHECKOUT_PAYLOAD
        || screen == MainViewModel.Screen.WEBSHOP_PAYLOAD;
    binding.toolbar.getMenu().clear();
    if (isPayload) {
      binding.toolbar.inflateMenu(R.menu.payload_editor);
    } else if (screen == MainViewModel.Screen.API) {
      binding.toolbar.inflateMenu(R.menu.instances);
    }
    switch (screen) {
      case INSTANCE_DETAILS:
        binding.toolbar.setTitle(R.string.nav_instance_details);
        binding.toolbar.setNavigationIcon(R.drawable.ic_arrow_back_24);
        binding.bottomNav.getMenu().findItem(R.id.tab_api).setChecked(true);
        break;
      case CHECKOUT_PAYLOAD:
        binding.toolbar.setTitle(R.string.nav_checkout_payload);
        binding.toolbar.setNavigationIcon(R.drawable.ic_arrow_back_24);
        binding.bottomNav.getMenu().findItem(R.id.tab_api).setChecked(true);
        break;
      case WEBSHOP_PAYLOAD:
        binding.toolbar.setTitle(R.string.nav_webshop_payload);
        binding.toolbar.setNavigationIcon(R.drawable.ic_arrow_back_24);
        binding.bottomNav.getMenu().findItem(R.id.tab_api).setChecked(true);
        break;
      case CARD_OPTIONS:
        binding.toolbar.setTitle(R.string.nav_card_options);
        binding.toolbar.setNavigationIcon(R.drawable.ic_arrow_back_24);
        binding.bottomNav.getMenu().findItem(R.id.tab_settings).setChecked(true);
        break;
      case MODAL_OPTIONS:
        binding.toolbar.setTitle(R.string.nav_modal_options);
        binding.toolbar.setNavigationIcon(R.drawable.ic_arrow_back_24);
        binding.bottomNav.getMenu().findItem(R.id.tab_settings).setChecked(true);
        break;
      case SETTINGS:
        binding.toolbar.setTitle(R.string.tab_settings);
        binding.toolbar.setNavigationIcon(null);
        binding.bottomNav.getMenu().findItem(R.id.tab_settings).setChecked(true);
        break;
      case API:
        binding.toolbar.setTitle(R.string.tab_api);
        binding.toolbar.setNavigationIcon(null);
        binding.bottomNav.getMenu().findItem(R.id.tab_api).setChecked(true);
        break;
      case TEST:
      default:
        binding.toolbar.setTitle("");
        binding.toolbar.setNavigationIcon(null);
        binding.bottomNav.getMenu().findItem(R.id.tab_test).setChecked(true);
    }
  }

  private void applyOrientationLock() {
    setRequestedOrientation(viewModel.isLockLandscape()
        ? ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        : ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
  }

  /**
   * One text area serves both directions: it opens holding the exported document (copy it out),
   * and Import reads back whatever is in it. The format is shared with the iOS sample.
   */
  private void showImportExportDialog() {
    if (isFinishing() || isDestroyed()) {
      return;
    }
    // Full-screen so a long document is comfortable to edit, matching the iOS sheet.
    android.app.Dialog dialog =
        new android.app.Dialog(this, R.style.Theme_StashNativeDemo_FullScreenDialog);
    dialog.setContentView(R.layout.dialog_import_export);
    android.widget.EditText field = dialog.findViewById(R.id.importExportText);
    field.setText(viewModel.exportInstancesJson());

    com.google.android.material.appbar.MaterialToolbar toolbar =
        dialog.findViewById(R.id.importExportToolbar);
    toolbar.setNavigationOnClickListener(v -> dialog.dismiss());
    toolbar.inflateMenu(R.menu.import_export);
    toolbar.setOnMenuItemClickListener(item -> {
      int id = item.getItemId();
      if (id == R.id.action_copy_instances) {
        android.content.ClipboardManager clipboard =
            (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (clipboard != null) {
          clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
              "Stash instances", field.getText().toString()));
          android.widget.Toast.makeText(
              this, R.string.import_export_copied, android.widget.Toast.LENGTH_SHORT).show();
        }
        return true;
      } else if (id == R.id.action_import_instances) {
        int added = viewModel.importInstancesJson(field.getText().toString());
        String message;
        if (added < 0) {
          message = getString(R.string.import_export_invalid);
        } else if (added == 0) {
          message = getString(R.string.import_export_none);
        } else {
          message = getString(R.string.import_export_added, added);
        }
        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show();
        if (added > 0) {
          dialog.dismiss();
        }
        return true;
      }
      return false;
    });
    dialog.show();
    activeDialog = dialog;
  }

  private void confirmDeleteInstance() {
    if (isFinishing() || isDestroyed()) {
      return;
    }
    activeDialog = new AlertDialog.Builder(this)
        .setTitle(R.string.delete_instance_title)
        .setPositiveButton(R.string.delete_instance_confirm,
            (dialog, which) -> viewModel.deleteEditingInstance())
        .setNegativeButton(android.R.string.cancel, null)
        .show();
  }

  private void showAddApiKeyDialog() {
    if (isFinishing() || isDestroyed()) {
      return;
    }
    View content = getLayoutInflater().inflate(R.layout.dialog_add_api_key, null);
    android.widget.EditText nameField = content.findViewById(R.id.addKeyName);
    android.widget.EditText appIdField = content.findViewById(R.id.addKeyAppId);
    android.widget.EditText valueField = content.findViewById(R.id.addKeyValue);
    com.google.android.material.materialswitch.MaterialSwitch prodSwitch =
        content.findViewById(R.id.addKeyProduction);
    activeDialog = new AlertDialog.Builder(this)
        .setTitle(R.string.add_api_key_title)
        .setView(content)
        .setPositiveButton(android.R.string.ok, (dialog, which) -> {
          String name = nameField.getText() != null ? nameField.getText().toString() : "";
          String appId = appIdField.getText() != null ? appIdField.getText().toString() : "";
          String key = valueField.getText() != null ? valueField.getText().toString() : "";
          if (!viewModel.addApiKey(name, appId, key, prodSwitch.isChecked())) {
            android.widget.Toast.makeText(this, R.string.add_api_key_incomplete,
                android.widget.Toast.LENGTH_SHORT).show();
          }
        })
        .setNegativeButton(android.R.string.cancel, null)
        .show();
  }

  private void openCard() {
    String url = viewModel.getCheckoutUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_checkout_url));
      return;
    }
    url = url.trim();
    Log.i(TAG, "Opening card: " + url);
    StashNativeCard.CardConfig config = buildCardConfig();
    StashNativeCard.getInstance().openCard(url, config);
  }

  private void openBrowser() {
    String url = viewModel.getBrowserUrl();
    if (url == null || url.trim().isEmpty()) {
      showOutcomeDialog("Error", getString(R.string.error_browser_url));
      return;
    }
    syncKeepAlive();
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

  private void generateCheckout() {
    generateAndOpen(CHECKOUT_PATH, viewModel.getActiveCheckoutPayload(), false,
        R.string.error_generate_checkout_url, "checkout URL");
  }

  private void generateCheckoutForBrowser() {
    generateAndOpen(CHECKOUT_PATH, viewModel.getActiveCheckoutPayload(), true,
        R.string.error_generate_checkout_url, "checkout URL");
  }

  private void openWebshop() {
    generateAndOpen(WEBSHOP_PATH, viewModel.getActiveWebshopPayload(), false,
        R.string.error_generate_webshop_url, "authenticated webshop URL");
  }

  private void openWebshopForBrowser() {
    generateAndOpen(WEBSHOP_PATH, viewModel.getActiveWebshopPayload(), true,
        R.string.error_generate_webshop_url, "authenticated webshop URL");
  }

  /**
   * Signs the saved payload, POSTs it, and opens the returned URL in the card or the browser.
   * The body is whatever the user saved in Settings; it is signed and sent byte for byte.
   */
  private void generateAndOpen(String path, final String payload, final boolean openInBrowser,
      final int errorRes, final String label) {
    final String urlString = viewModel.getApiBaseUrl() + path;
    final String appId = viewModel.getActiveAppId();
    final String ingressSecret = viewModel.getActiveApiKey();

    networkExecutor.execute(() -> {
      HttpURLConnection conn = null;
      try {
        // Sign the exact bytes that go on the wire, then send them unchanged.
        byte[] bytes = payload.getBytes(StandardCharsets.UTF_8);
        String signature = StashHmac.signature(appId, ingressSecret, bytes);

        URL url = new URL(urlString);
        conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setRequestProperty("x-stash-hmac-signature", signature);
        conn.setDoOutput(true);
        conn.setConnectTimeout(NETWORK_TIMEOUT_MS);
        conn.setReadTimeout(NETWORK_TIMEOUT_MS);
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
          // org.json coerces an explicit JSON null to the string "null"; isNull covers both.
          String generated = json.isNull("url") ? null : json.optString("url");
          if (generated != null) {
            final String finalUrl = generated.trim();
            // Re-check after trim: a whitespace-only url passes a pre-trim isEmpty guard.
            if (!finalUrl.isEmpty()) {
              runOnUiThread(() -> {
                if (openInBrowser) {
                  syncKeepAlive();
                  Log.i(TAG, "Opening browser (" + label + "): " + finalUrl);
                  StashNativeCard.getInstance().openBrowser(finalUrl);
                } else {
                  Log.i(TAG, "Opening card (" + label + "): " + finalUrl);
                  StashNativeCard.CardConfig config = buildCardConfig();
                  StashNativeCard.getInstance().openCard(finalUrl, config);
                }
              });
              return;
            }
          }
        }
      } catch (Exception e) {
        Log.e(TAG, "Generate " + label + " failed", e);
      } finally {
        if (conn != null) {
          conn.disconnect();
        }
      }
      runOnUiThread(() -> showOutcomeDialog("Error", getString(errorRes)));
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
    config.autoClose = viewModel.isModalAutoClose();
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
    StashNativeCard.getInstance().setKeepAliveEnabled(viewModel.isKeepAliveEnabled());
  }

  @Override
  protected void onDestroy() {
    StashNativeCard.getInstance().setListener(null);
    networkExecutor.shutdown();
    if (activeDialog != null) {
      if (activeDialog.isShowing()) {
        activeDialog.dismiss();
      }
      activeDialog = null;
    }
    binding = null;
    super.onDestroy();
  }
}
