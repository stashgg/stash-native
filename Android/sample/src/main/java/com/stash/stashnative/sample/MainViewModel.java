package com.stash.stashnative.sample;

import android.app.Application;
import android.content.SharedPreferences;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import com.stash.stashnative.StashNativeCard;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Holds UI state for MainActivity and builds the row list for each screen. */
public class MainViewModel extends AndroidViewModel {

  private static final String PREFS_NAME = "StashNativeSample";
  private static final String PREF_STASH_API_KEY = "StashApiKey";
  private static final String PREF_API_KEYS = "ApiKeysJson";
  private static final String PREF_SELECTED_API_KEY = "SelectedApiKeyId";
  private static final String PREF_CARD_BACKGROUND_HEX = "CardBackgroundColorHex";
  private static final String PREF_MODAL_BACKGROUND_HEX = "ModalBackgroundColorHex";

  /** Default URL for the Card section (manual open + baseline testing). */
  private static final String DEFAULT_CARD_URL = "https://test.stashpreview.com/";
  /** Default URL for the Browser section (same test card as iOS). */
  private static final String DEFAULT_BROWSER_URL = "https://test.stashpreview.com/";
  private static final String DEFAULT_MODAL_URL =
      "https://checkout.stash.gg/pay/channel-selection";
  private static final String API_BASE_PROD = "https://api.stash.gg";
  private static final String API_BASE_TEST = "https://test-api.stash.gg";
  /** Demo ingress secret (base64) used as the HMAC key when no key is configured. */
  public static final String DEFAULT_STASH_API_KEY =
      "VDBsMm5zRU9weHk5RTZ6X0p2Y3hnLVhrMHVvS21QMG5wYTBJcmhHUHdWTV93Y0dDWVluV0hQd1ZYWHRiYWk2UA==";
  /** Demo app ID that pairs with the secret above; required by the signature header. */
  public static final String DEFAULT_STASH_APP_ID = "4fe1c1a4-b136-4187-82f2-61c9983eedf2";
  /** Display name of the bundled credential. */
  public static final String DEFAULT_STASH_KEY_NAME = "Howling Woods";
  /** Secrets previously shipped as the bundled credential. */
  private static final String[] SUPERSEDED_BUNDLED_SECRETS = {
      "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg"
  };

  private final SharedPreferences prefs;
  private final MutableLiveData<List<SettingsItem>> items = new MutableLiveData<>();

  /** Which list the RecyclerView currently shows: a bottom-nav tab or an options sub-screen. */
  public enum Screen { TEST, SETTINGS, API, CARD_OPTIONS, MODAL_OPTIONS,
      INSTANCE_DETAILS, CHECKOUT_PAYLOAD, WEBSHOP_PAYLOAD }

  private Screen currentScreen = Screen.TEST;

  // URLs (user-edited)
  private String checkoutUrl = DEFAULT_CARD_URL;
  private String browserUrl = DEFAULT_BROWSER_URL;
  private String modalUrl = DEFAULT_MODAL_URL;

  // Lock the whole app (not just the checkout) to landscape.
  private boolean lockLandscape = false;

  // API keys: named, each production or test; persisted as JSON so Auto Backup restores them.
  private final List<ApiKeyEntry> apiKeys = new ArrayList<>();
  private String selectedApiKeyId;
  /** Instance whose details screen (and its payload editors) is currently open. */
  private String editingInstanceId;

  // Browser options
  private boolean keepAliveEnabled = true;

  // Payloads are per-instance (see ApiKeyEntry). This is the live edit buffer for whichever
  // payload screen is open; committed to the editing instance by savePayload().
  private String payloadDraft = "";

  // Checkout options
  private boolean forcePortraitOnCheckout = false;
  private boolean cardAutoClose = true;
  private int phoneCardHeight = 58;
  private int checkoutPhoneLandscapeW = 60;
  private int checkoutPhoneLandscapeH = 80;
  private int checkoutTabletPortraitW = 30;
  private int checkoutTabletPortraitH = 40;
  private int checkoutTabletLandscapeW = 20;
  private int checkoutTabletLandscapeH = 50;

  /** Optional `#RRGGBB` etc.; empty = SDK default (system theme). */
  private String cardBackgroundColorHex = "";
  private String modalBackgroundColorHex = "";

  // Modal options
  private boolean modalAllowDismiss = true;
  private boolean modalAutoClose = true;
  private int modalPhonePortraitW = 70;
  private int modalPhonePortraitH = 40;
  private int modalPhoneLandscapeW = 40;
  private int modalPhoneLandscapeH = 70;
  private int modalTabletPortraitW = 30;
  private int modalTabletPortraitH = 20;
  private int modalTabletLandscapeW = 20;
  private int modalTabletLandscapeH = 30;

  /** Restores saved keys, colors and payloads from prefs. */
  public MainViewModel(Application application) {
    super(application);
    prefs = application.getSharedPreferences(PREFS_NAME, Application.MODE_PRIVATE);
    loadApiKeys();
    String cardBg = prefs.getString(PREF_CARD_BACKGROUND_HEX, "");
    if (cardBg != null) {
      cardBackgroundColorHex = cardBg;
    }
    String modalBg = prefs.getString(PREF_MODAL_BACKGROUND_HEX, "");
    if (modalBg != null) {
      modalBackgroundColorHex = modalBg;
    }
    refreshList();
  }

  /** Observable list of settings items for the RecyclerView. */
  public LiveData<List<SettingsItem>> getItems() {
    return items;
  }

  // ---- Request payloads -------------------------------------------------------------------
  // The editor sends whatever text the user saves, verbatim. Defaults are the test fixtures,
  // pretty-printed so they are pleasant to edit.

  /** Default body for /sdk/server/checkout_links/generate_quick_pay_url. */
  public static String defaultCheckoutPayload() {
    try {
      JSONObject user = new JSONObject();
      user.put("id", "7849fbc5-87fd-446d-8d9c-de25298f1092");
      user.put("validatedEmail", "test@stash.gg");
      user.put("displayName", "Test User");
      user.put("profileImageUrl", "https://storage.googleapis.com/stash-demo-f9550"
          + ".firebasestorage.app/avatars/6564ced3-c163-4b0d-aa4e-c1a19e42aa65.png");
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
      return prettyJson(body);
    } catch (JSONException e) {
      return "{}";
    }
  }

  /** org.json escapes forward slashes; undo that so URLs read normally in the editor. */
  private static String prettyJson(JSONObject body) throws JSONException {
    return body.toString(2).replace("\\/", "/");
  }

  /** Default body for /sdk/server/generate_url. */
  public static String defaultWebshopPayload() {
    try {
      JSONObject user = new JSONObject();
      user.put("id", "7849fbc5-87fd-446d-8d9c-de25298f1092");
      user.put("validatedEmail", "test@stash.gg");
      user.put("displayName", "Test User");
      user.put("platform", "ANDROID");
      JSONObject body = new JSONObject();
      body.put("user", user);
      body.put("target", "STORE");
      return prettyJson(body);
    } catch (JSONException e) {
      return "{}";
    }
  }

  /** Checkout body the active instance signs and sends, verbatim. */
  public String getActiveCheckoutPayload() {
    return activeEntry().checkoutPayload;
  }

  /** Webshop body the active instance signs and sends, verbatim. */
  public String getActiveWebshopPayload() {
    return activeEntry().webshopPayload;
  }

  /** Called on every keystroke, so it must not refresh the list. */
  public void setPayloadDraft(String text) {
    payloadDraft = text != null ? text : "";
  }

  /** Commits the draft for the open payload screen to the editing instance and persists it. */
  public void savePayload() {
    ApiKeyEntry entry = editingInstance();
    if (entry == null) {
      return;
    }
    if (currentScreen == Screen.CHECKOUT_PAYLOAD) {
      entry.checkoutPayload = payloadDraft;
      saveApiKeys();
    } else if (currentScreen == Screen.WEBSHOP_PAYLOAD) {
      entry.webshopPayload = payloadDraft;
      saveApiKeys();
    }
  }

  /** Restores the open payload screen to its default and rebinds the editor. */
  public void resetPayloadToDefault() {
    payloadDraft = currentScreen == Screen.WEBSHOP_PAYLOAD
        ? defaultWebshopPayload() : defaultCheckoutPayload();
    refreshList();
  }

  public void setCheckoutUrl(String url) {
    this.checkoutUrl = url != null ? url : "";
  }

  public void setModalUrl(String url) {
    this.modalUrl = url != null ? url : "";
  }

  public void setBrowserUrl(String url) {
    this.browserUrl = url != null ? url : "";
  }

  public String getCheckoutUrl() {
    return checkoutUrl;
  }

  public String getModalUrl() {
    return modalUrl;
  }

  public String getBrowserUrl() {
    return browserUrl;
  }

  public void setCardBackgroundColorHex(String hex) {
    this.cardBackgroundColorHex = hex != null ? hex : "";
    prefs.edit().putString(PREF_CARD_BACKGROUND_HEX, this.cardBackgroundColorHex).apply();
  }

  public String getCardBackgroundColorHex() {
    return cardBackgroundColorHex;
  }

  public void setModalBackgroundColorHex(String hex) {
    this.modalBackgroundColorHex = hex != null ? hex : "";
    prefs.edit().putString(PREF_MODAL_BACKGROUND_HEX, this.modalBackgroundColorHex).apply();
  }

  public String getModalBackgroundColorHex() {
    return modalBackgroundColorHex;
  }

  public Screen getCurrentScreen() {
    return currentScreen;
  }

  /** Switches the visible list to a bottom-nav tab or a dedicated drill-in screen. */
  public void navigateTo(Screen screen) {
    currentScreen = screen != null ? screen : Screen.TEST;
    // Entering a payload screen starts a fresh draft from the editing instance's saved body.
    ApiKeyEntry editing = editingInstance();
    if (currentScreen == Screen.CHECKOUT_PAYLOAD) {
      payloadDraft = editing != null ? editing.checkoutPayload : defaultCheckoutPayload();
    } else if (currentScreen == Screen.WEBSHOP_PAYLOAD) {
      payloadDraft = editing != null ? editing.webshopPayload : defaultWebshopPayload();
    }
    refreshList();
  }

  public void setLockLandscape(boolean on) {
    lockLandscape = on;
  }

  public boolean isLockLandscape() {
    return lockLandscape;
  }

  private void loadApiKeys() {
    apiKeys.clear();
    String json = prefs.getString(PREF_API_KEYS, null);
    if (json != null && !json.isEmpty()) {
      try {
        JSONArray arr = new JSONArray(json);
        for (int i = 0; i < arr.length(); i++) {
          apiKeys.add(ApiKeyEntry.fromJson(arr.getJSONObject(i)));
        }
      } catch (JSONException ignored) {
      }
    }
    if (apiKeys.isEmpty()) {
      // Seed with the bundled credential, migrating a previously saved single key if present.
      String legacy = prefs.getString(PREF_STASH_API_KEY, null);
      String seedKey = (legacy != null && !legacy.isEmpty()) ? legacy : DEFAULT_STASH_API_KEY;
      apiKeys.add(newInstance(DEFAULT_STASH_KEY_NAME, DEFAULT_STASH_APP_ID, seedKey, false));
    }
    // Migrate instances still holding a SUPERSEDED bundled secret up to the current demo
    // credential (name, app ID and secret have each changed at least once, and stored copies
    // survive reinstalls). Only superseded secrets migrate, so name/app ID/secret edits the user
    // makes to the current bundled instance in its details screen are preserved across launches.
    for (ApiKeyEntry entry : apiKeys) {
      if (isSupersededBundledSecret(entry.key)) {
        entry.name = DEFAULT_STASH_KEY_NAME;
        entry.appId = DEFAULT_STASH_APP_ID;
        entry.key = DEFAULT_STASH_API_KEY;
      }
      // Entries saved before per-instance payloads have none; seed them with the defaults.
      if (entry.checkoutPayload.isEmpty()) {
        entry.checkoutPayload = defaultCheckoutPayload();
      }
      if (entry.webshopPayload.isEmpty()) {
        entry.webshopPayload = defaultWebshopPayload();
      }
    }
    selectedApiKeyId = prefs.getString(PREF_SELECTED_API_KEY, null);
    if (selectedApiKeyId == null || findApiKey(selectedApiKeyId) == null) {
      selectedApiKeyId = apiKeys.get(0).id;
    }
    saveApiKeys();
  }

  /** True if the key is a superseded bundled secret that should migrate to the current one. */
  private static boolean isSupersededBundledSecret(String key) {
    for (String superseded : SUPERSEDED_BUNDLED_SECRETS) {
      if (superseded.equals(key)) {
        return true;
      }
    }
    return false;
  }

  private void saveApiKeys() {
    try {
      JSONArray arr = new JSONArray();
      for (ApiKeyEntry e : apiKeys) {
        arr.put(e.toJson());
      }
      prefs.edit()
          .putString(PREF_API_KEYS, arr.toString())
          .putString(PREF_SELECTED_API_KEY, selectedApiKeyId)
          .apply();
    } catch (JSONException ignored) {
    }
  }

  private ApiKeyEntry findApiKey(String id) {
    for (ApiKeyEntry e : apiKeys) {
      if (e.id.equals(id)) {
        return e;
      }
    }
    return null;
  }

  private static String newId() {
    return UUID.randomUUID().toString();
  }

  /** A new instance carrying the current default payloads, so every instance starts editable. */
  private ApiKeyEntry newInstance(String name, String appId, String key, boolean production) {
    return new ApiKeyEntry(newId(), name, appId, key, production,
        defaultCheckoutPayload(), defaultWebshopPayload());
  }

  public ApiKeyEntry getSelectedApiKey() {
    return findApiKey(selectedApiKeyId);
  }

  public void selectApiKey(String id) {
    if (findApiKey(id) != null) {
      selectedApiKeyId = id;
      saveApiKeys();
      refreshList();
    }
  }

  /** Opens the details screen for one instance (name/app ID/secret/environment + payloads). */
  public void openInstanceDetails(String id) {
    editingInstanceId = id;
    navigateTo(Screen.INSTANCE_DETAILS);
  }

  /** Deletes the instance whose details are open and returns to the Instances list. */
  public void deleteEditingInstance() {
    if (editingInstanceId != null) {
      deleteApiKey(editingInstanceId);
      editingInstanceId = null;
    }
    navigateTo(Screen.API);
  }

  private ApiKeyEntry editingInstance() {
    return findApiKey(editingInstanceId);
  }

  // Detail fields commit live (like the URL rows) and must not refresh the list, or the rebind
  // would move the caret while the user is still typing.
  public void setEditingName(String name) {
    ApiKeyEntry e = editingInstance();
    if (e != null) {
      e.name = name != null ? name : "";
      saveApiKeys();
    }
  }

  public void setEditingAppId(String appId) {
    ApiKeyEntry e = editingInstance();
    if (e != null) {
      e.appId = appId != null ? appId : "";
      saveApiKeys();
    }
  }

  public void setEditingSecret(String secret) {
    ApiKeyEntry e = editingInstance();
    if (e != null) {
      e.key = secret != null ? secret : "";
      saveApiKeys();
    }
  }

  public void setEditingProduction(boolean production) {
    ApiKeyEntry e = editingInstance();
    if (e != null) {
      e.production = production;
      saveApiKeys();
    }
  }

  /** Returns false when the entry cannot sign; both app ID and secret are required. */
  public boolean addApiKey(String name, String appId, String key, boolean production) {
    String cleanAppId = appId != null ? appId.trim() : "";
    String cleanKey = key != null ? key.trim() : "";
    if (cleanAppId.isEmpty() || cleanKey.isEmpty()) {
      return false;
    }
    String cleanName = (name != null && !name.trim().isEmpty()) ? name.trim() : "Untitled";
    ApiKeyEntry entry = newInstance(cleanName, cleanAppId, cleanKey, production);
    apiKeys.add(entry);
    selectedApiKeyId = entry.id;
    saveApiKeys();
    refreshList();
    return true;
  }

  public void deleteApiKey(String id) {
    ApiKeyEntry entry = findApiKey(id);
    if (entry == null) {
      return;
    }
    apiKeys.remove(entry);
    if (apiKeys.isEmpty()) {
      apiKeys.add(newInstance(
          DEFAULT_STASH_KEY_NAME, DEFAULT_STASH_APP_ID, DEFAULT_STASH_API_KEY, false));
    }
    if (id.equals(selectedApiKeyId)) {
      selectedApiKeyId = apiKeys.get(0).id;
    }
    saveApiKeys();
    refreshList();
  }

  // ---- Instance import/export -------------------------------------------------------------
  // Deliberately platform-neutral: same field names and types as the iOS sample, so instances
  // exported on either platform import on the other, per-instance payloads included. Key order
  // and colon spacing differ between the two serializers -- both importers read by name and
  // tolerate missing payload fields. Local ids are omitted; they are per-device and regenerated
  // on import.

  private static final int INSTANCES_EXPORT_VERSION = 2;

  /** Every instance as a portable JSON document. */
  public String exportInstancesJson() {
    try {
      JSONArray arr = new JSONArray();
      for (ApiKeyEntry entry : apiKeys) {
        JSONObject o = new JSONObject();
        o.put("name", entry.name);
        o.put("appId", entry.appId);
        o.put("ingressSecret", entry.key);
        o.put("production", entry.production);
        o.put("checkoutPayload", entry.checkoutPayload);
        o.put("webshopPayload", entry.webshopPayload);
        arr.put(o);
      }
      JSONObject root = new JSONObject();
      root.put("version", INSTANCES_EXPORT_VERSION);
      root.put("instances", arr);
      // Secrets are base64 and may contain '/', which org.json escapes; undo that so the
      // document matches what iOS emits.
      return root.toString(2).replace("\\/", "/");
    } catch (JSONException e) {
      return "{}";
    }
  }

  /**
   * Adds instances from an exported document, skipping any already present.
   * Returns the number added, or -1 if the document could not be read.
   */
  public int importInstancesJson(String text) {
    try {
      JSONArray arr = new JSONObject(text != null ? text : "").getJSONArray("instances");
      int added = 0;
      for (int i = 0; i < arr.length(); i++) {
        JSONObject o = arr.getJSONObject(i);
        String appId = o.optString("appId").trim();
        String secret = o.optString("ingressSecret").trim();
        if (appId.isEmpty() || secret.isEmpty() || findByCredentials(appId, secret) != null) {
          continue;
        }
        String name = o.optString("name").trim();
        String checkout = o.optString("checkoutPayload");
        String webshop = o.optString("webshopPayload");
        apiKeys.add(new ApiKeyEntry(newId(), name.isEmpty() ? "Untitled" : name, appId, secret,
            o.optBoolean("production", false),
            checkout.isEmpty() ? defaultCheckoutPayload() : checkout,
            webshop.isEmpty() ? defaultWebshopPayload() : webshop));
        added++;
      }
      if (added > 0) {
        saveApiKeys();
        refreshList();
      }
      return added;
    } catch (JSONException e) {
      return -1;
    }
  }

  private ApiKeyEntry findByCredentials(String appId, String secret) {
    for (ApiKeyEntry entry : apiKeys) {
      if (entry.appId.equals(appId) && entry.key.equals(secret)) {
        return entry;
      }
    }
    return null;
  }

  /**
   * Credential the API calls sign with: the selected entry, or the bundled demo one if the
   * entry cannot sign (e.g. saved before HMAC signing, so it has no app ID). Secret, app ID
   * and environment all come from one entry so they can never be mixed across credentials.
   */
  private ApiKeyEntry activeEntry() {
    ApiKeyEntry entry = getSelectedApiKey();
    if (entry == null || entry.appId == null || entry.appId.trim().isEmpty()
        || entry.key == null || entry.key.trim().isEmpty()) {
      return newInstance(DEFAULT_STASH_KEY_NAME, DEFAULT_STASH_APP_ID, DEFAULT_STASH_API_KEY, false);
    }
    return entry;
  }

  /** Active ingress secret used to sign requests. */
  public String getActiveApiKey() {
    return activeEntry().key.trim();
  }

  /** Active app ID carried in the signature header. */
  public String getActiveAppId() {
    return activeEntry().appId.trim();
  }

  /** Stash API host for the active key's environment. */
  public String getApiBaseUrl() {
    return isActiveKeyProduction() ? API_BASE_PROD : API_BASE_TEST;
  }

  public boolean isActiveKeyProduction() {
    return activeEntry().production;
  }

  public void setKeepAliveEnabled(boolean on) {
    keepAliveEnabled = on;
  }

  public boolean isKeepAliveEnabled() {
    return keepAliveEnabled;
  }

  public void setForcePortraitOnCheckout(boolean on) {
    forcePortraitOnCheckout = on;
    refreshList();
  }

  public void setModalAllowDismiss(boolean on) {
    modalAllowDismiss = on;
    refreshList();
  }

  public void setCardAutoClose(boolean on) {
    cardAutoClose = on;
    refreshList();
  }

  public void setModalAutoClose(boolean on) {
    modalAutoClose = on;
    refreshList();
  }

  public void setPhoneCardHeight(int progress) {
    phoneCardHeight = progress;
    refreshList();
  }

  public void setCheckoutTabletPortraitWidth(int progress) {
    checkoutTabletPortraitW = progress;
    refreshList();
  }

  public void setCheckoutTabletPortraitHeight(int progress) {
    checkoutTabletPortraitH = progress;
    refreshList();
  }

  public void setCheckoutTabletLandscapeWidth(int progress) {
    checkoutTabletLandscapeW = progress;
    refreshList();
  }

  public void setCheckoutTabletLandscapeHeight(int progress) {
    checkoutTabletLandscapeH = progress;
    refreshList();
  }

  public void setCheckoutPhoneLandscapeWidth(int progress) {
    checkoutPhoneLandscapeW = progress;
    refreshList();
  }

  public void setCheckoutPhoneLandscapeHeight(int progress) {
    checkoutPhoneLandscapeH = progress;
    refreshList();
  }

  public void setModalPhonePortraitWidth(int progress) {
    modalPhonePortraitW = progress;
    refreshList();
  }

  public void setModalPhonePortraitHeight(int progress) {
    modalPhonePortraitH = progress;
    refreshList();
  }

  public void setModalPhoneLandscapeWidth(int progress) {
    modalPhoneLandscapeW = progress;
    refreshList();
  }

  public void setModalPhoneLandscapeHeight(int progress) {
    modalPhoneLandscapeH = progress;
    refreshList();
  }

  public void setModalTabletPortraitWidth(int progress) {
    modalTabletPortraitW = progress;
    refreshList();
  }

  public void setModalTabletPortraitHeight(int progress) {
    modalTabletPortraitH = progress;
    refreshList();
  }

  public void setModalTabletLandscapeWidth(int progress) {
    modalTabletLandscapeW = progress;
    refreshList();
  }

  public void setModalTabletLandscapeHeight(int progress) {
    modalTabletLandscapeH = progress;
    refreshList();
  }

  public boolean isForcePortraitOnCheckout() {
    return forcePortraitOnCheckout;
  }

  public boolean isModalAllowDismiss() {
    return modalAllowDismiss;
  }

  public boolean isCardAutoClose() {
    return cardAutoClose;
  }

  public boolean isModalAutoClose() {
    return modalAutoClose;
  }

  public int getPhoneCardHeight() {
    return phoneCardHeight;
  }

  public int getCheckoutTabletPortraitW() {
    return checkoutTabletPortraitW;
  }

  public int getCheckoutTabletPortraitH() {
    return checkoutTabletPortraitH;
  }

  public int getCheckoutTabletLandscapeW() {
    return checkoutTabletLandscapeW;
  }

  public int getCheckoutTabletLandscapeH() {
    return checkoutTabletLandscapeH;
  }

  public int getCheckoutPhoneLandscapeW() {
    return checkoutPhoneLandscapeW;
  }

  public int getCheckoutPhoneLandscapeH() {
    return checkoutPhoneLandscapeH;
  }

  public int getModalPhonePortraitW() {
    return modalPhonePortraitW;
  }

  public int getModalPhonePortraitH() {
    return modalPhonePortraitH;
  }

  public int getModalPhoneLandscapeW() {
    return modalPhoneLandscapeW;
  }

  public int getModalPhoneLandscapeH() {
    return modalPhoneLandscapeH;
  }

  public int getModalTabletPortraitW() {
    return modalTabletPortraitW;
  }

  public int getModalTabletPortraitH() {
    return modalTabletPortraitH;
  }

  public int getModalTabletLandscapeW() {
    return modalTabletLandscapeW;
  }

  public int getModalTabletLandscapeH() {
    return modalTabletLandscapeH;
  }

  /** Builds the list for the current screen. */
  public void refreshList() {
    switch (currentScreen) {
      case CARD_OPTIONS:
        items.setValue(buildCardOptionsList());
        return;
      case MODAL_OPTIONS:
        items.setValue(buildModalOptionsList());
        return;
      case INSTANCE_DETAILS:
        items.setValue(buildInstanceDetailsList());
        return;
      case CHECKOUT_PAYLOAD:
      case WEBSHOP_PAYLOAD:
        items.setValue(buildPayloadEditorList());
        return;
      case SETTINGS:
        items.setValue(buildSettingsList());
        return;
      case API:
        items.setValue(buildApiList());
        return;
      case TEST:
      default:
        items.setValue(buildTestList());
    }
  }

  /** Test tab: the three presentation surfaces (card, modal, browser). */
  private List<SettingsItem> buildTestList() {
    List<SettingsItem> list = new ArrayList<>();

    // Card section (URL row carries an inline Open button)
    list.add(SettingsItem.sectionHeader(R.string.section_card, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_checkout_url, checkoutUrl,
        R.drawable.ic_ms_link_24, false, false));
    list.add(SettingsItem.actionPreference(R.string.generate_checkout, false, false));
    list.add(SettingsItem.actionPreference(R.string.open_webshop, false, true));

    // Browser section
    list.add(SettingsItem.sectionHeader(R.string.section_browser, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_browser_url, browserUrl,
        R.drawable.ic_ms_link_24, false, false));
    list.add(SettingsItem.actionPreference(R.string.generate_checkout_for_browser, false, false));
    list.add(SettingsItem.actionPreference(R.string.open_webshop_for_browser, false, true));

    // Modal section
    list.add(SettingsItem.sectionHeader(R.string.section_modal, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_modal_url, modalUrl,
        R.drawable.ic_ms_link_24, false, true));

    // Deeplink test: opens the card against a bundled harness page.
    list.add(SettingsItem.sectionHeader(R.string.section_deeplink_test, true, false));
    list.add(SettingsItem.actionPreference(R.string.open_deeplink_test, false, true));

    return list;
  }

  /** Settings tab: orientation lock + navigation to per-mode option screens. */
  private List<SettingsItem> buildSettingsList() {
    List<SettingsItem> list = new ArrayList<>();
    list.add(SettingsItem.sectionHeader(R.string.section_presentation_options, true, false));
    list.add(SettingsItem.actionPreference(R.string.nav_card_options, false, false));
    list.add(SettingsItem.actionPreference(R.string.nav_modal_options, false, true));
    // Other
    list.add(SettingsItem.sectionHeader(R.string.section_other, true, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_lock_landscape, 0, lockLandscape, false, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_keep_alive, R.string.option_keep_alive_supporting,
        keepAliveEnabled, false, true));
    // About: SDK version read straight from the library.
    list.add(SettingsItem.sectionHeader(R.string.section_about, true, false));
    list.add(SettingsItem.infoPreference(
        R.string.option_sdk_version, StashNativeCard.getVersion(), false, true));
    return list;
  }

  /** API tab: named API keys (each production/test), selectable, plus an Add row. */
  private List<SettingsItem> buildApiList() {
    List<SettingsItem> list = new ArrayList<>();
    list.add(SettingsItem.sectionHeader(R.string.section_api_keys, true, false));
    for (int i = 0; i < apiKeys.size(); i++) {
      ApiKeyEntry entry = apiKeys.get(i);
      boolean last = i == apiKeys.size() - 1;
      list.add(SettingsItem.apiKey(
          entry.id, entry.name, entry.production,
          entry.id.equals(selectedApiKeyId), false, last));
    }
    return list;
  }

  /** Instance details: editable name/app ID/secret/environment, then per-instance payloads. */
  private List<SettingsItem> buildInstanceDetailsList() {
    List<SettingsItem> list = new ArrayList<>();
    ApiKeyEntry e = editingInstance();
    if (e == null) {
      return list;
    }
    list.add(SettingsItem.sectionHeader(R.string.section_instance, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.instance_name, e.name, R.drawable.ic_ms_tune_24, false, false));
    list.add(SettingsItem.urlPreference(
        R.string.instance_app_id, e.appId, R.drawable.ic_ms_credit_card_24, false, false));
    list.add(SettingsItem.urlPreference(
        R.string.instance_secret, e.key, R.drawable.ic_ms_key_24, false, false));
    list.add(SettingsItem.switchPreference(
        R.string.instance_production, 0, e.production, false, true));
    list.add(SettingsItem.sectionHeader(R.string.section_payloads, true, false));
    list.add(SettingsItem.actionPreference(R.string.nav_checkout_payload, false, false));
    list.add(SettingsItem.actionPreference(R.string.nav_webshop_payload, false, true));
    list.add(SettingsItem.actionPreference(R.string.nav_delete_instance, true, true));
    return list;
  }

  /** Free-form JSON editor for the open payload screen. */
  private List<SettingsItem> buildPayloadEditorList() {
    List<SettingsItem> list = new ArrayList<>();
    list.add(SettingsItem.payloadEditor(payloadDraft, true, true));
    return list;
  }

  private List<SettingsItem> buildCardOptionsList() {
    List<SettingsItem> list = new ArrayList<>();
    // General
    list.add(SettingsItem.sectionHeader(R.string.section_general, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_card_background_color, cardBackgroundColorHex,
        R.drawable.ic_ms_tune_24, false, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_force_portrait_on_checkout,
        R.string.option_force_portrait_on_checkout_supporting,
        forcePortraitOnCheckout, false, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_card_auto_close,
        R.string.option_card_auto_close_supporting,
        cardAutoClose, false, true));
    // Phone
    list.add(SettingsItem.sectionHeader(R.string.section_phone, true, false));
    list.add(SettingsItem.sliderPreference(
        R.string.phone_card_height, phoneCardHeight, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.checkout_phone_landscape_width, checkoutPhoneLandscapeW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.checkout_phone_landscape_height, checkoutPhoneLandscapeH, false, true));
    // Tablet
    list.add(SettingsItem.sectionHeader(R.string.section_tablet, true, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_portrait_width, checkoutTabletPortraitW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_portrait_height, checkoutTabletPortraitH, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_landscape_width, checkoutTabletLandscapeW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_landscape_height, checkoutTabletLandscapeH, false, true));
    return list;
  }

  private List<SettingsItem> buildModalOptionsList() {
    List<SettingsItem> list = new ArrayList<>();
    // General
    list.add(SettingsItem.sectionHeader(R.string.section_general, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_modal_background_color, modalBackgroundColorHex,
        R.drawable.ic_ms_tune_24, false, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_allow_dismiss, R.string.option_allow_dismiss_supporting,
        modalAllowDismiss, false, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_modal_auto_close,
        R.string.option_modal_auto_close_supporting,
        modalAutoClose, false, true));
    // Phone
    list.add(SettingsItem.sectionHeader(R.string.section_phone, true, false));
    list.add(SettingsItem.sliderPreference(
        R.string.phone_portrait_width, modalPhonePortraitW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.phone_portrait_height, modalPhonePortraitH, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.phone_landscape_width, modalPhoneLandscapeW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.phone_landscape_height, modalPhoneLandscapeH, false, true));
    // Tablet
    list.add(SettingsItem.sectionHeader(R.string.section_tablet, true, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_portrait_width_modal, modalTabletPortraitW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_portrait_height_modal, modalTabletPortraitH, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_landscape_width_modal, modalTabletLandscapeW, false, false));
    list.add(SettingsItem.sliderPreference(
        R.string.tablet_landscape_height_modal, modalTabletLandscapeH, false, true));
    return list;
  }
}
