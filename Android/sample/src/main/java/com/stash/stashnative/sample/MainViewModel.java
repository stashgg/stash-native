package com.stash.stashnative.sample;

import android.app.Application;
import android.content.SharedPreferences;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import java.util.ArrayList;
import java.util.List;

/**
 * ViewModel for the main screen. Holds all UI state and survives configuration changes.
 * Single source of truth for the settings-style list (Google architecture best practice).
 */
public class MainViewModel extends AndroidViewModel {

  private static final String PREFS_NAME = "StashNativeSample";
  private static final String PREF_STASH_API_KEY = "StashApiKey";

  /** Default URL for the Card section (manual open + baseline testing). */
  private static final String DEFAULT_CARD_URL = "https://test.stashpreview.com/";
  /** Default URL for the Browser section (htmlpreview wrapper for legacy popup test page). */
  private static final String DEFAULT_BROWSER_URL =
      "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/"
      + "refs/heads/main/.github/Stash.Popup.Test/index.html";
  private static final String DEFAULT_MODAL_URL =
      "https://checkout.stash.gg/pay/channel-selection";
  public static final String DEFAULT_STASH_API_KEY =
      "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg";

  private final SharedPreferences prefs;
  private final MutableLiveData<List<SettingsItem>> items = new MutableLiveData<>();

  // URLs (user-edited)
  private String checkoutUrl = DEFAULT_CARD_URL;
  private String browserUrl = DEFAULT_BROWSER_URL;
  private String modalUrl = DEFAULT_MODAL_URL;

  // Presentation options: two separate expandables under one category
  private boolean checkoutOptionsExpanded = false;
  private boolean modalOptionsExpanded = false;

  // Checkout generation settings
  private String stashApiKey = DEFAULT_STASH_API_KEY;
  private boolean useTestApi = true;

  // Checkout options
  private boolean forcePortraitOnCheckout = false;
  private int phoneCardHeight = 58;
  private int checkoutPhoneLandscapeW = 80;
  private int checkoutPhoneLandscapeH = 50;
  private int checkoutTabletPortraitW = 30;
  private int checkoutTabletPortraitH = 40;
  private int checkoutTabletLandscapeW = 20;
  private int checkoutTabletLandscapeH = 50;

  // Modal options
  private boolean modalShowDragBar = true;
  private boolean modalAllowDismiss = true;
  private int modalPhonePortraitW = 70;
  private int modalPhonePortraitH = 40;
  private int modalPhoneLandscapeW = 40;
  private int modalPhoneLandscapeH = 70;
  private int modalTabletPortraitW = 30;
  private int modalTabletPortraitH = 20;
  private int modalTabletLandscapeW = 20;
  private int modalTabletLandscapeH = 30;

  /** Creates the ViewModel and restores persisted API key from SharedPreferences. */
  public MainViewModel(Application application) {
    super(application);
    prefs = application.getSharedPreferences(PREFS_NAME, Application.MODE_PRIVATE);
    String saved = prefs.getString(PREF_STASH_API_KEY, null);
    if (saved != null && !saved.isEmpty()) {
      stashApiKey = saved;
    }
    refreshList();
  }

  /** Observable list of settings items for the RecyclerView. */
  public LiveData<List<SettingsItem>> getItems() {
    return items;
  }

  public void setCheckoutUrl(String url) {
    this.checkoutUrl = url != null ? url : "";
    // Don't refresh list on every keystroke
  }

  public void setModalUrl(String url) {
    this.modalUrl = url != null ? url : "";
    // Don't refresh list on every keystroke
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

  public void toggleCheckoutOptions() {
    checkoutOptionsExpanded = !checkoutOptionsExpanded;
    refreshList();
  }

  public void toggleModalOptions() {
    modalOptionsExpanded = !modalOptionsExpanded;
    refreshList();
  }

  public boolean isCheckoutOptionsExpanded() {
    return checkoutOptionsExpanded;
  }

  public boolean isModalOptionsExpanded() {
    return modalOptionsExpanded;
  }

  /** Persists and applies the Stash API key for checkout generation. */
  public void setStashApiKey(String key) {
    this.stashApiKey = (key != null && !key.trim().isEmpty())
        ? key.trim()
        : DEFAULT_STASH_API_KEY;
    prefs.edit().putString(PREF_STASH_API_KEY, this.stashApiKey).apply();
  }

  public String getStashApiKey() {
    return stashApiKey;
  }

  public void setUseTestApi(boolean useTest) {
    this.useTestApi = useTest;
    refreshList();
  }

  public boolean isUseTestApi() {
    return useTestApi;
  }

  public void setForcePortraitOnCheckout(boolean on) {
    forcePortraitOnCheckout = on;
    refreshList();
  }

  public void setModalShowDragBar(boolean on) {
    modalShowDragBar = on;
    refreshList();
  }

  public void setModalAllowDismiss(boolean on) {
    modalAllowDismiss = on;
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

  public boolean isModalShowDragBar() {
    return modalShowDragBar;
  }

  public boolean isModalAllowDismiss() {
    return modalAllowDismiss;
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

  /** Builds the full list from current state (single source of truth). */
  public void refreshList() {
    List<SettingsItem> list = new ArrayList<>();

    // Card section
    list.add(SettingsItem.sectionHeader(R.string.section_card, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_checkout_url, checkoutUrl,
        android.R.drawable.sym_contact_card, false, false));
    list.add(SettingsItem.actionPreference(
        R.string.open_card, android.R.drawable.sym_contact_card, false, false));
    list.add(SettingsItem.actionPreference(
        R.string.generate_checkout, android.R.drawable.sym_contact_card, false, false));
    list.add(SettingsItem.sectionFooter(R.string.footer_card, false, true));

    // Modal section
    list.add(SettingsItem.sectionHeader(R.string.section_modal, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_modal_url, modalUrl,
        android.R.drawable.ic_menu_sort_by_size, false, false));
    list.add(SettingsItem.actionPreference(
        R.string.open_modal, android.R.drawable.ic_menu_sort_by_size, false, false));
    list.add(SettingsItem.sectionFooter(R.string.footer_modal, false, true));

    // Browser section (under Modal)
    list.add(SettingsItem.sectionHeader(R.string.section_browser, true, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_browser_url, browserUrl,
        android.R.drawable.ic_menu_compass, false, false));
    list.add(SettingsItem.actionPreference(
        R.string.open_browser, android.R.drawable.ic_menu_compass, false, false));
    list.add(SettingsItem.actionPreference(
        R.string.generate_checkout_for_browser, android.R.drawable.ic_menu_compass, false, false));
    list.add(SettingsItem.sectionFooter(R.string.footer_browser, false, true));

    // Presentation options (Checkout + Modal under one category)
    list.add(SettingsItem.sectionHeader(R.string.section_presentation_options, true, false));
    list.add(SettingsItem.expandableHeader(
        checkoutOptionsExpanded ? R.string.hide_checkout_options : R.string.show_checkout_options,
        checkoutOptionsExpanded, android.R.drawable.ic_menu_preferences, false, false));
    if (checkoutOptionsExpanded) {
      list.add(SettingsItem.switchPreference(
          R.string.option_force_portrait_on_checkout,
          R.string.option_force_portrait_on_checkout_supporting,
          forcePortraitOnCheckout, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.phone_card_height, phoneCardHeight, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.checkout_phone_landscape_width, checkoutPhoneLandscapeW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.checkout_phone_landscape_height, checkoutPhoneLandscapeH, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_portrait_width, checkoutTabletPortraitW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_portrait_height, checkoutTabletPortraitH, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_landscape_width, checkoutTabletLandscapeW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_landscape_height, checkoutTabletLandscapeH, false, false));
    }
    list.add(SettingsItem.expandableHeader(
        modalOptionsExpanded ? R.string.hide_modal_options : R.string.show_modal_options,
        modalOptionsExpanded, android.R.drawable.ic_menu_preferences, false,
        !modalOptionsExpanded));
    if (modalOptionsExpanded) {
      list.add(SettingsItem.switchPreference(
          R.string.option_show_drag_bar, 0, modalShowDragBar, false, false));
      list.add(SettingsItem.switchPreference(
          R.string.option_allow_dismiss, R.string.option_allow_dismiss_supporting,
          modalAllowDismiss, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.phone_portrait_width, modalPhonePortraitW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.phone_portrait_height, modalPhonePortraitH, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.phone_landscape_width, modalPhoneLandscapeW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.phone_landscape_height, modalPhoneLandscapeH, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_portrait_width_modal, modalTabletPortraitW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_portrait_height_modal, modalTabletPortraitH, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_landscape_width_modal, modalTabletLandscapeW, false, false));
      list.add(SettingsItem.sliderPreference(
          R.string.tablet_landscape_height_modal, modalTabletLandscapeH, false, true));
    }

    // Checkout Generation Settings card
    list.add(SettingsItem.sectionHeader(
        R.string.section_checkout_generation_settings, true, false));
    list.add(SettingsItem.switchPreference(
        R.string.option_use_test_api, 0, useTestApi, false, false));
    list.add(SettingsItem.urlPreference(
        R.string.hint_api_key, stashApiKey,
        android.R.drawable.ic_lock_lock, false, false));
    list.add(SettingsItem.sectionFooter(
        R.string.footer_checkout_generation_settings, false, true));

    items.setValue(list);
  }
}
