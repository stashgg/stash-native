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

  /**
   * Shared with iOS/Sample/Tests/HmacVector.swift.template; both samples apply one rule. Trimming
   * covers Unicode spaces and line separators (NBSP, U+2028), not other control characters.
   */
  private static final String[] ACCEPTED_SECRETS = {
    "c2VjcmV0LWtleQ==", "c2VjcmV0LWtleQ", " c2VjcmV0LWtleQ\n", "abc", "abc=", "aQ==", "Pz8/Pj4+",
    " c2VjcmV0LWtleQ\u00A0", "c2VjcmV0LWtleQ\u2028", "\u200Bc2VjcmV0LWtleQ"
  };
  private static final String[] REJECTED_SECRETS = {
    "", " \n", "a", "abcde", "abcd=", "c2VjcmV0LWtleQ=", "ab=c", "====", "not base64!",
    "c2Vj cmV0LWtleQ", "abcd====", "c2VjcmV0LWtleQ\u0001", "c2VjcmV0LWtleQ\uFEFF",
    "c2VjcmV0LWtleQ\u180E"
  };

  /** Swift's whitespacesAndNewlines, enumerated on macOS; HmacVector.swift.template pins it too. */
  private static final int[] SWIFT_WHITESPACE = {
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
    0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x200B, 0x2028, 0x2029, 0x202F,
    0x205F, 0x3000
  };

  @Test public void secretTrimmingMatchesSwiftWhitespaceExactly() {
    java.util.Set<Integer> expected = new java.util.HashSet<>();
    for (int c : SWIFT_WHITESPACE) {
      expected.add(c);
    }
    for (int c = 0; c <= 0xFFFF; c++) {
      String trimmed = MainViewModel.trimSecret("a" + (char) c);
      assertEquals(String.format("U+%04X", c), expected.contains(c), trimmed.equals("a"));
    }
  }

  @Test public void sharedSecretVectorsMatchTheIosRule() throws Exception {
    for (String secret : ACCEPTED_SECRETS) {
      assertTrue(secret, MainViewModel.isValidBase64(secret));
      // Accepted secrets must also sign; generation passes the trimmed value.
      StashHmac.signature("app_test", MainViewModel.trimSecret(secret), new byte[0], 1700000000000L);
    }
    for (String secret : REJECTED_SECRETS) {
      assertFalse(secret, MainViewModel.isValidBase64(secret));
    }
    assertFalse(MainViewModel.isValidBase64(null));
    assertTrue(MainViewModel.isValidBase64(" " + MainViewModel.DEFAULT_STASH_API_KEY + " "));
    assertEquals(
        StashHmac.signature("app_test", "c2VjcmV0LWtleQ==", new byte[0], 1700000000000L),
        StashHmac.signature("app_test", "c2VjcmV0LWtleQ", new byte[0], 1700000000000L));
    try {
      StashHmac.signature("app_test", "not base64!", new byte[0], 1700000000000L);
      fail("invalid secret must not sign");
    } catch (IllegalArgumentException expected) {
      // Base64.decode rejects the input; the sample reports it as a signing failure.
    }
  }
}
