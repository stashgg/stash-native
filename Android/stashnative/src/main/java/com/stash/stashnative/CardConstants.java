package com.stash.stashnative;

/** Shared bridge identifiers and loading behavior. */
final class CardConstants {
  private CardConstants() {}

  public static final String COLOR_OVERLAY_DIM = "#66000000";

  public static final int LOADING_INDICATOR_SIZE_DP = 48;

  public static final long WEBVIEW_RETRY_TIMEOUT_MS = 10000L;

  public static final long WEBVIEW_NETWORK_DEADLINE_MS = 15000L;

  public static final long LOADING_REVEAL_DURATION_MS = 350L;

  public static final int REQUEST_CODE_STASH_CUSTOM_TAB = 0x7374;

  public static final String INTENT_EXTRA_URL = "url";

  static final String INTENT_EXTRA_CODE_LINK = "stash.codeLink";

  static final String BROADCAST_CODE_LINK_SCANNED =
      "com.stash.stashnative.internal.CODE_LINK_SCANNED";

  static final String BROADCAST_CODE_LINK_ERROR =
      "com.stash.stashnative.internal.CODE_LINK_ERROR";

  static final String BROADCAST_EXTRA_CODE_LINK_CONTENT = "stashCodeLinkContent";

  static final String BROADCAST_EXTRA_CODE_LINK_ERROR = "stashCodeLinkError";

  public static final String BROADCAST_CHECKOUT_PAYMENT_SUCCESS =
      "com.stash.stashnative.internal.CHECKOUT_PAYMENT_SUCCESS";

  public static final String BROADCAST_CHECKOUT_PAYMENT_FAILURE =
      "com.stash.stashnative.internal.CHECKOUT_PAYMENT_FAILURE";

  public static final String BROADCAST_CHECKOUT_OPT_IN =
      "com.stash.stashnative.internal.CHECKOUT_OPT_IN";

  public static final String BROADCAST_CHECKOUT_NETWORK_ERROR =
      "com.stash.stashnative.internal.CHECKOUT_NETWORK_ERROR";

  public static final String BROADCAST_CHECKOUT_DIALOG_DISMISSED =
      "com.stash.stashnative.internal.CHECKOUT_DIALOG_DISMISSED";

  public static final String BROADCAST_CHECKOUT_PAGE_LOADED =
      "com.stash.stashnative.internal.CHECKOUT_PAGE_LOADED";

  public static final String BROADCAST_EXTRA_OPTIN_TYPE = "stashOptinType";

  public static final String BROADCAST_EXTRA_PAGE_LOAD_MS = "stashPageLoadMs";

  public static final String BROADCAST_EXTRA_PAYMENT_ORDER = "stashPaymentOrder";

  public static final String BROADCAST_EXTRA_WILL_CLOSE = "stashWillClose";

  public static final String MESSAGE_TYPE_SUCCESS = "success";

  public static final String MESSAGE_TYPE_FAILURE = "failure";

  public static final String MESSAGE_TYPE_OPTIN = "optin";

  public static final String COLOR_BACKGROUND_DIM = COLOR_OVERLAY_DIM;

  public static final String COLOR_DARK_BG = "#1e1e1e";

  public static final String COLOR_DRAG_HANDLE = "#D1D1D6";
}
