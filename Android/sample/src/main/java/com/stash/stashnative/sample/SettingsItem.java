package com.stash.stashnative.sample;

import androidx.annotation.StringRes;

/** One row in the settings-style list. */
public final class SettingsItem {

  public static final int TYPE_SECTION_HEADER = 0;
  public static final int TYPE_URL_PREFERENCE = 2;
  public static final int TYPE_ACTION_PREFERENCE = 3;
  public static final int TYPE_SWITCH_PREFERENCE = 6;
  public static final int TYPE_SLIDER_PREFERENCE = 7;
  public static final int TYPE_API_KEY = 8;
  public static final int TYPE_INFO_PREFERENCE = 9;
  public static final int TYPE_PAYLOAD_EDITOR = 10;

  public final int type;
  @StringRes public final int titleRes;
  @StringRes public final int supportingRes; // 0 if none
  public final String value; // for URL, slider label
  public final boolean checked; // for switch; for API key = selected
  public final int progress; // for slider (0-90, display as progress+10 %)
  public final int iconRes; // 0 if none
  /** True if this row is the first in a card container (iOS-style bubble). */
  public final boolean firstInCard;
  /** True if this row is the last in a card container. */
  public final boolean lastInCard;
  // API key row fields (TYPE_API_KEY only).
  public final String stringId;
  public final String name;
  public final boolean production;

  /** Internal constructor; use static factory methods. */
  private SettingsItem(int type, int titleRes, int supportingRes, String value,
      boolean checked, int progress, int iconRes,
      boolean firstInCard, boolean lastInCard) {
    this.type = type;
    this.titleRes = titleRes;
    this.supportingRes = supportingRes;
    this.value = value != null ? value : "";
    this.checked = checked;
    this.progress = progress;
    this.iconRes = iconRes;
    this.firstInCard = firstInCard;
    this.lastInCard = lastInCard;
    this.stringId = null;
    this.name = null;
    this.production = false;
  }

  /** Internal constructor for API key rows. */
  private SettingsItem(String stringId, String name, boolean production,
      boolean selected, boolean firstInCard, boolean lastInCard) {
    this.type = TYPE_API_KEY;
    this.titleRes = 0;
    this.supportingRes = 0;
    this.value = "";
    this.checked = selected;
    this.progress = 0;
    this.iconRes = 0;
    this.firstInCard = firstInCard;
    this.lastInCard = lastInCard;
    this.stringId = stringId;
    this.name = name;
    this.production = production;
  }

  /** API key row: name + production/test toggle + selected indicator. */
  public static SettingsItem apiKey(String id, String name, boolean production,
      boolean selected, boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(id, name, production, selected, firstInCard, lastInCard);
  }

  /** Section header row. */
  public static SettingsItem sectionHeader(
      @StringRes int titleRes, boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(
        TYPE_SECTION_HEADER, titleRes, 0, null, false, 0, 0, firstInCard, lastInCard);
  }

  /** URL/edit preference row. */
  public static SettingsItem urlPreference(
      @StringRes int titleRes, String value, int iconRes,
      boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(
        TYPE_URL_PREFERENCE, titleRes, 0, value, false, 0, iconRes, firstInCard, lastInCard);
  }

  /** Action row. */
  public static SettingsItem actionPreference(
      @StringRes int titleRes, boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(
        TYPE_ACTION_PREFERENCE, titleRes, 0, null, false, 0, 0, firstInCard, lastInCard);
  }

  /** Switch/toggle preference row. */
  public static SettingsItem switchPreference(
      @StringRes int titleRes, @StringRes int supportingRes, boolean checked,
      boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(
        TYPE_SWITCH_PREFERENCE, titleRes, supportingRes, null, checked, 0, 0,
        firstInCard, lastInCard);
  }

  /** Free-form JSON editor row holding the current draft text. */
  public static SettingsItem payloadEditor(
      String value, boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(
        TYPE_PAYLOAD_EDITOR, 0, 0, value, false, 0, 0, firstInCard, lastInCard);
  }

  /** Read-only info row: title on the left, value on the right. */
  public static SettingsItem infoPreference(
      @StringRes int titleRes, String value, boolean firstInCard, boolean lastInCard) {
    return new SettingsItem(
        TYPE_INFO_PREFERENCE, titleRes, 0, value, false, 0, 0, firstInCard, lastInCard);
  }

  /** Slider row. */
  public static SettingsItem sliderPreference(
      @StringRes int titleRes, int progress, boolean firstInCard, boolean lastInCard) {
    int pct = progress + 10;
    return new SettingsItem(
        TYPE_SLIDER_PREFERENCE, titleRes, 0, pct + "%", false, progress, 0,
        firstInCard, lastInCard);
  }
}
