package com.stash.stashsdk;

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

    private static final String PREFS_NAME = "StashPaySample";
    private static final String PREF_STASH_API_KEY = "StashApiKey";

    private static final String DEFAULT_CHECKOUT_URL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html";
    private static final String DEFAULT_MODAL_URL = "https://store.howlingwoods.shop/pay/channel-selection";
    public static final String DEFAULT_STASH_API_KEY = "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg";

    private final SharedPreferences prefs;
    private final MutableLiveData<List<SettingsItem>> items = new MutableLiveData<>();

    // URLs (user-edited)
    private String checkoutUrl = DEFAULT_CHECKOUT_URL;
    private String modalUrl = DEFAULT_MODAL_URL;

    // Presentation options: two separate expandables under one category
    private boolean checkoutOptionsExpanded = false;
    private boolean modalOptionsExpanded = false;

    // Checkout generation settings
    private String stashApiKey = DEFAULT_STASH_API_KEY;
    private boolean useTestApi = true;

    // Checkout options
    private boolean webViewMode = false;
    private boolean forcePortraitOnCheckout = false;
    private int phoneCardHeight = 58;       // 68%
    private int checkoutPhoneLandscapeW = 80, checkoutPhoneLandscapeH = 50; // 90%, 60% (progress 0–90 → display 10–100%)
    private int checkoutTabletPortraitW = 30, checkoutTabletPortraitH = 40;  // 40%, 50%
    private int checkoutTabletLandscapeW = 20, checkoutTabletLandscapeH = 50; // 30%, 60%

    // Modal options
    private boolean modalShowDragBar = true;
    private boolean modalAllowDismiss = true;
    private int modalPhonePortraitW = 70, modalPhonePortraitH = 40;   // 80%, 50%
    private int modalPhoneLandscapeW = 40, modalPhoneLandscapeH = 70;  // 50%, 80%
    private int modalTabletPortraitW = 30, modalTabletPortraitH = 20;  // 40%, 30%
    private int modalTabletLandscapeW = 20, modalTabletLandscapeH = 30; // 30%, 40%

    public MainViewModel(Application application) {
        super(application);
        prefs = application.getSharedPreferences(PREFS_NAME, Application.MODE_PRIVATE);
        String saved = prefs.getString(PREF_STASH_API_KEY, null);
        if (saved != null && !saved.isEmpty()) {
            stashApiKey = saved;
        }
        refreshList();
    }

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

    public String getCheckoutUrl() {
        return checkoutUrl;
    }

    public String getModalUrl() {
        return modalUrl;
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

    public void setStashApiKey(String key) {
        this.stashApiKey = key != null && !key.trim().isEmpty() ? key.trim() : DEFAULT_STASH_API_KEY;
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

    public void setWebViewMode(boolean on) {
        webViewMode = on;
        refreshList();
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

    public boolean isWebViewMode() { return webViewMode; }
    public boolean isForcePortraitOnCheckout() { return forcePortraitOnCheckout; }
    public boolean isModalShowDragBar() { return modalShowDragBar; }
    public boolean isModalAllowDismiss() { return modalAllowDismiss; }
    public int getPhoneCardHeight() { return phoneCardHeight; }
    public int getCheckoutTabletPortraitW() { return checkoutTabletPortraitW; }
    public int getCheckoutTabletPortraitH() { return checkoutTabletPortraitH; }
    public int getCheckoutTabletLandscapeW() { return checkoutTabletLandscapeW; }
    public int getCheckoutTabletLandscapeH() { return checkoutTabletLandscapeH; }
    public int getCheckoutPhoneLandscapeW() { return checkoutPhoneLandscapeW; }
    public int getCheckoutPhoneLandscapeH() { return checkoutPhoneLandscapeH; }
    public int getModalPhonePortraitW() { return modalPhonePortraitW; }
    public int getModalPhonePortraitH() { return modalPhonePortraitH; }
    public int getModalPhoneLandscapeW() { return modalPhoneLandscapeW; }
    public int getModalPhoneLandscapeH() { return modalPhoneLandscapeH; }
    public int getModalTabletPortraitW() { return modalTabletPortraitW; }
    public int getModalTabletPortraitH() { return modalTabletPortraitH; }
    public int getModalTabletLandscapeW() { return modalTabletLandscapeW; }
    public int getModalTabletLandscapeH() { return modalTabletLandscapeH; }

    /** Builds the full list from current state (single source of truth). */
    public void refreshList() {
        List<SettingsItem> list = new ArrayList<>();

        // Checkout card (bubble)
        list.add(SettingsItem.sectionHeader(R.string.section_checkout, true, false));
        list.add(SettingsItem.urlPreference(R.string.hint_checkout_url, checkoutUrl, R.drawable.ic_credit_card, false, false));
        list.add(SettingsItem.actionPreference(R.string.open_checkout, R.drawable.ic_credit_card, false, false));
        list.add(SettingsItem.actionPreference(R.string.generate_checkout, R.drawable.ic_credit_card, false, false));
        list.add(SettingsItem.sectionFooter(R.string.footer_checkout, false, true));

        // Modal card (bubble)
        list.add(SettingsItem.sectionHeader(R.string.section_modal, true, false));
        list.add(SettingsItem.urlPreference(R.string.hint_modal_url, modalUrl, R.drawable.ic_layers, false, false));
        list.add(SettingsItem.actionPreference(R.string.open_modal, R.drawable.ic_layers, false, false));
        list.add(SettingsItem.sectionFooter(R.string.footer_modal, false, true));

        // Presentation options card (Checkout options + Modal options under one category; no gap between the two expandables)
        list.add(SettingsItem.sectionHeader(R.string.section_presentation_options, true, false));
        list.add(SettingsItem.expandableHeader(
                checkoutOptionsExpanded ? R.string.hide_checkout_options : R.string.show_checkout_options,
                checkoutOptionsExpanded, R.drawable.ic_tune, false, false));
        if (checkoutOptionsExpanded) {
            list.add(SettingsItem.switchPreference(R.string.option_web_view_mode, R.string.option_web_view_mode_supporting, webViewMode, false, false));
            list.add(SettingsItem.switchPreference(R.string.option_force_portrait_on_checkout, R.string.option_force_portrait_on_checkout_supporting, forcePortraitOnCheckout, false, false));
            list.add(SettingsItem.sliderPreference(R.string.phone_card_height, phoneCardHeight, false, false));
            list.add(SettingsItem.sliderPreference(R.string.checkout_phone_landscape_width, checkoutPhoneLandscapeW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.checkout_phone_landscape_height, checkoutPhoneLandscapeH, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_portrait_width, checkoutTabletPortraitW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_portrait_height, checkoutTabletPortraitH, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_landscape_width, checkoutTabletLandscapeW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_landscape_height, checkoutTabletLandscapeH, false, false));
        }
        list.add(SettingsItem.expandableHeader(
                modalOptionsExpanded ? R.string.hide_modal_options : R.string.show_modal_options,
                modalOptionsExpanded, R.drawable.ic_tune, false, !modalOptionsExpanded));
        if (modalOptionsExpanded) {
            list.add(SettingsItem.switchPreference(R.string.option_show_drag_bar, 0, modalShowDragBar, false, false));
            list.add(SettingsItem.switchPreference(R.string.option_allow_dismiss, R.string.option_allow_dismiss_supporting, modalAllowDismiss, false, false));
            list.add(SettingsItem.sliderPreference(R.string.phone_portrait_width, modalPhonePortraitW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.phone_portrait_height, modalPhonePortraitH, false, false));
            list.add(SettingsItem.sliderPreference(R.string.phone_landscape_width, modalPhoneLandscapeW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.phone_landscape_height, modalPhoneLandscapeH, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_portrait_width_modal, modalTabletPortraitW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_portrait_height_modal, modalTabletPortraitH, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_landscape_width_modal, modalTabletLandscapeW, false, false));
            list.add(SettingsItem.sliderPreference(R.string.tablet_landscape_height_modal, modalTabletLandscapeH, false, true));
        }

        // Checkout Generation Settings card
        list.add(SettingsItem.sectionHeader(R.string.section_checkout_generation_settings, true, false));
        list.add(SettingsItem.switchPreference(R.string.option_use_test_api, 0, useTestApi, false, false));
        list.add(SettingsItem.urlPreference(R.string.hint_api_key, stashApiKey, R.drawable.ic_tune, false, true));

        items.setValue(list);
    }
}
