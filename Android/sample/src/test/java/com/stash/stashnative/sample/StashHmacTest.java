package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.nio.charset.StandardCharsets;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/** Pins the v1;appId;millis;base64 header against an independently computed vector. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class StashHmacTest {
  /** HMAC-SHA256 over "1700000000000.{}" with the key bytes "secret-key" (Python hmac). */
  @Test public void signatureMatchesTheReferenceVector() throws Exception {
    String header = StashHmac.signature(
        "app_test", "c2VjcmV0LWtleQ==", "{}".getBytes(StandardCharsets.UTF_8), 1700000000000L);
    assertEquals("v1;app_test;1700000000000;BcQuOn6SZzdxDZnMg0flRAhb9SVL0H2seNBiU2W+Mq4=", header);
  }

  @Test public void clockBasedSignatureKeepsTheFourFieldLayout() throws Exception {
    String header = StashHmac.signature("app_test", "c2VjcmV0LWtleQ==",
        "{}".getBytes(StandardCharsets.UTF_8));
    String[] parts = header.split(";");
    assertEquals(4, parts.length);
    assertEquals("v1", parts[0]);
    assertEquals("app_test", parts[1]);
    assertTrue(Math.abs(Long.parseLong(parts[2]) - System.currentTimeMillis()) < 60_000L);
    assertEquals(44, parts[3].length());
  }

  @Test public void malformedSecretsAreRejectedBeforeSigning() throws Exception {
    assertTrue(MainViewModel.isValidBase64("c2VjcmV0LWtleQ=="));
    assertTrue(MainViewModel.isValidBase64(" " + MainViewModel.DEFAULT_STASH_API_KEY + " "));
    assertFalse(MainViewModel.isValidBase64("abc"));
    assertFalse(MainViewModel.isValidBase64("c2VjcmV0LWtleQ"));
    assertFalse(MainViewModel.isValidBase64("not base64!"));
    assertFalse(MainViewModel.isValidBase64(""));
    assertFalse(MainViewModel.isValidBase64(null));
    try {
      StashHmac.signature("app_test", "not base64!", new byte[0], 1700000000000L);
      fail("invalid secret must not sign");
    } catch (IllegalArgumentException expected) {
      // Base64.decode rejects the input; the sample reports it as a signing failure.
    }
  }
}
