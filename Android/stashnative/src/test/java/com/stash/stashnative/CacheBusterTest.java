package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

/** The stall retry's cache buster belongs to the query, never to the fragment. */
public class CacheBusterTest {
  private static String bust(String url) {
    return StashCheckoutLoadingSupport.appendCacheBuster(url, 42L);
  }

  @Test public void startsOrExtendsTheQuery() {
    assertEquals("https://pay.example/checkout?_stash_nc=42", bust("https://pay.example/checkout"));
    assertEquals("https://pay.example/checkout?theme=light&_stash_nc=42",
        bust("https://pay.example/checkout?theme=light"));
    assertEquals("https://pay.example/checkout?_stash_nc=42", bust("https://pay.example/checkout?"));
  }

  @Test public void insertsBeforeTheFragmentAndKeepsItExactly() {
    assertEquals("https://pay.example/checkout?theme=light&_stash_nc=42#step2",
        bust("https://pay.example/checkout?theme=light#step2"));
    assertEquals("https://pay.example/checkout?_stash_nc=42#/pay?step=2&x=1",
        bust("https://pay.example/checkout#/pay?step=2&x=1"));
    assertEquals("https://pay.example/checkout?_stash_nc=42#", bust("https://pay.example/checkout#"));
  }

  @Test public void keepsEncodedQueryBytes() {
    assertEquals("https://pay.example/c?sig=a%2Bb%3D&n=%20x&_stash_nc=42#r%2F1",
        bust("https://pay.example/c?sig=a%2Bb%3D&n=%20x#r%2F1"));
  }

  @Test public void emptyInputIsUnchanged() {
    assertNull(bust(null));
    assertEquals("", bust(""));
  }
}
