package com.stash.stashsdk;

import androidx.annotation.StringRes;

/**
 * Represents a single row in the settings-style list.
 * Follows Android Settings / preference list pattern.
 */
public final class SettingsItem {

    public static final int TYPE_HEADER = -1;
    public static final int TYPE_SECTION_HEADER = 0;
    public static final int TYPE_SECTION_FOOTER = 1;
    public static final int TYPE_URL_PREFERENCE = 2;
    public static final int TYPE_ACTION_PREFERENCE = 3;
    public static final int TYPE_EXPANDABLE_HEADER = 5;
    public static final int TYPE_SWITCH_PREFERENCE = 6;
    public static final int TYPE_SLIDER_PREFERENCE = 7;

    public final int type;
    @StringRes public final int titleRes;
    @StringRes public final int supportingRes; // 0 if none
    public final String value; // for URL, status text, slider label
    public final boolean checked; // for switch
    public final int progress; // for slider (0-90, display as progress+10 %)
    public final boolean expanded; // for expandable header
    public final int iconRes; // 0 if none
    /** True if this row is the first in a card container (iOS-style bubble). */
    public final boolean firstInCard;
    /** True if this row is the last in a card container. */
    public final boolean lastInCard;

    private SettingsItem(int type, int titleRes, int supportingRes, String value,
                          boolean checked, int progress, boolean expanded, int iconRes,
                          boolean firstInCard, boolean lastInCard) {
        this.type = type;
        this.titleRes = titleRes;
        this.supportingRes = supportingRes;
        this.value = value != null ? value : "";
        this.checked = checked;
        this.progress = progress;
        this.expanded = expanded;
        this.iconRes = iconRes;
        this.firstInCard = firstInCard;
        this.lastInCard = lastInCard;
    }

    public static SettingsItem header() {
        return new SettingsItem(TYPE_HEADER, R.string.header_title, R.string.header_subtitle, null, false, 0, false, 0, false, false);
    }

    public static SettingsItem sectionHeader(@StringRes int titleRes) {
        return new SettingsItem(TYPE_SECTION_HEADER, titleRes, 0, null, false, 0, false, 0, false, false);
    }

    public static SettingsItem sectionHeader(@StringRes int titleRes, boolean firstInCard, boolean lastInCard) {
        return new SettingsItem(TYPE_SECTION_HEADER, titleRes, 0, null, false, 0, false, 0, firstInCard, lastInCard);
    }

    public static SettingsItem sectionFooter(@StringRes int titleRes) {
        return new SettingsItem(TYPE_SECTION_FOOTER, titleRes, 0, null, false, 0, false, 0, false, false);
    }

    public static SettingsItem sectionFooter(@StringRes int titleRes, boolean firstInCard, boolean lastInCard) {
        return new SettingsItem(TYPE_SECTION_FOOTER, titleRes, 0, null, false, 0, false, 0, firstInCard, lastInCard);
    }

    public static SettingsItem urlPreference(@StringRes int titleRes, String value, int iconRes) {
        return new SettingsItem(TYPE_URL_PREFERENCE, titleRes, 0, value, false, 0, false, iconRes, false, false);
    }

    public static SettingsItem urlPreference(@StringRes int titleRes, String value, int iconRes, boolean firstInCard, boolean lastInCard) {
        return new SettingsItem(TYPE_URL_PREFERENCE, titleRes, 0, value, false, 0, false, iconRes, firstInCard, lastInCard);
    }

    public static SettingsItem actionPreference(@StringRes int titleRes, int iconRes) {
        return new SettingsItem(TYPE_ACTION_PREFERENCE, titleRes, 0, null, false, 0, false, iconRes, false, false);
    }

    public static SettingsItem actionPreference(@StringRes int titleRes, int iconRes, boolean firstInCard, boolean lastInCard) {
        return new SettingsItem(TYPE_ACTION_PREFERENCE, titleRes, 0, null, false, 0, false, iconRes, firstInCard, lastInCard);
    }

    public static SettingsItem expandableHeader(@StringRes int titleRes, boolean expanded, int iconRes) {
        return new SettingsItem(TYPE_EXPANDABLE_HEADER, titleRes, 0, null, false, 0, expanded, iconRes, false, false);
    }

    public static SettingsItem expandableHeader(@StringRes int titleRes, boolean expanded, int iconRes, boolean firstInCard, boolean lastInCard) {
        return new SettingsItem(TYPE_EXPANDABLE_HEADER, titleRes, 0, null, false, 0, expanded, iconRes, firstInCard, lastInCard);
    }

    public static SettingsItem switchPreference(@StringRes int titleRes, @StringRes int supportingRes, boolean checked) {
        return new SettingsItem(TYPE_SWITCH_PREFERENCE, titleRes, supportingRes, null, checked, 0, false, 0, false, false);
    }

    public static SettingsItem switchPreference(@StringRes int titleRes, @StringRes int supportingRes, boolean checked, boolean firstInCard, boolean lastInCard) {
        return new SettingsItem(TYPE_SWITCH_PREFERENCE, titleRes, supportingRes, null, checked, 0, false, 0, firstInCard, lastInCard);
    }

    public static SettingsItem sliderPreference(@StringRes int titleRes, int progress) {
        int pct = progress + 10;
        return new SettingsItem(TYPE_SLIDER_PREFERENCE, titleRes, 0, pct + "%", false, progress, false, 0, false, false);
    }

    public static SettingsItem sliderPreference(@StringRes int titleRes, int progress, boolean firstInCard, boolean lastInCard) {
        int pct = progress + 10;
        return new SettingsItem(TYPE_SLIDER_PREFERENCE, titleRes, 0, pct + "%", false, progress, false, 0, firstInCard, lastInCard);
    }
}
