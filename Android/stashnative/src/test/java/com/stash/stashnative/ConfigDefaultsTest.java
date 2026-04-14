package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

public class ConfigDefaultsTest {

  @Test
  public void cardConfigDefaults() {
    StashNativeCard.CardConfig cfg = new StashNativeCard.CardConfig();
    assertFalse(cfg.forcePortrait);
    assertEquals(0.68f, cfg.cardHeightRatioPortrait, 0.001f);
    assertEquals(0.7f, cfg.cardWidthRatioLandscape, 0.01f);
    assertEquals(0.9f, cfg.cardHeightRatioLandscape, 0.01f);
    assertEquals(0.4f, cfg.tabletWidthRatioPortrait, 0.01f);
    assertEquals(0.5f, cfg.tabletHeightRatioPortrait, 0.01f);
    assertEquals(0.3f, cfg.tabletWidthRatioLandscape, 0.01f);
    assertEquals(0.6f, cfg.tabletHeightRatioLandscape, 0.01f);
    assertNull(cfg.backgroundColor);
  }

  @Test
  public void modalConfigDefaults() {
    StashNativeCard.ModalConfig cfg = new StashNativeCard.ModalConfig();
    assertTrue(cfg.allowDismiss);
    assertEquals(0.9f, cfg.phoneWidthRatioPortrait, 0.01f);
    assertEquals(0.50f, cfg.phoneHeightRatioPortrait, 0.01f);
    assertEquals(0.50f, cfg.phoneWidthRatioLandscape, 0.01f);
    assertEquals(0.80f, cfg.phoneHeightRatioLandscape, 0.01f);
    assertEquals(0.40f, cfg.tabletWidthRatioPortrait, 0.01f);
    assertEquals(0.30f, cfg.tabletHeightRatioPortrait, 0.01f);
    assertEquals(0.30f, cfg.tabletWidthRatioLandscape, 0.01f);
    assertEquals(0.40f, cfg.tabletHeightRatioLandscape, 0.01f);
    assertNull(cfg.backgroundColor);
  }

  @Test
  public void popupSizeConfigDefaults() {
    StashNativeCard.PopupSizeConfig cfg = new StashNativeCard.PopupSizeConfig();
    assertTrue(cfg.portraitWidthMultiplier > 0f);
    assertTrue(cfg.portraitHeightMultiplier > 0f);
    assertTrue(cfg.landscapeWidthMultiplier > 0f);
    assertTrue(cfg.landscapeHeightMultiplier > 0f);
  }

  @Test
  public void versionIsNonEmpty() {
    String v = StashNativeCard.getVersion();
    assertNotNull(v);
    assertFalse(v.isEmpty());
    assertTrue(v.contains("."));
  }

  @Test
  public void keepAliveConfigDefaults() {
    StashNativeCard.KeepAliveConfig cfg = new StashNativeCard.KeepAliveConfig();
    assertNull(cfg.notificationTitle);
    assertNull(cfg.notificationText);
    assertEquals(0, cfg.notificationIconResId);
  }
}
