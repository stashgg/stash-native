package com.stash.stashnative.sample;

import android.util.Base64;
import java.nio.charset.StandardCharsets;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Builds the x-stash-hmac-signature header for server-to-server Stash API calls.
 *
 * <p>Format: {@code v1;<appId>;<unixMillis>;<base64 HMAC-SHA256>}, where the signature covers
 * {@code "<unixMillis>." + body} using the base64-decoded ingress secret as the key. Stash rejects
 * requests whose timestamp is more than 5 minutes from its clock.
 *
 * <p>In a real integration this signing happens on your backend -- the ingress secret must never
 * ship inside a client app. The sample does it in-app only so the flow can be exercised on device.
 */
final class StashHmac {

  private StashHmac() {}

  /** Signs the exact body bytes that will be written to the connection. */
  static String signature(String appId, String ingressSecretB64, byte[] body) throws Exception {
    long unixMillis = System.currentTimeMillis();
    byte[] key = Base64.decode(ingressSecretB64, Base64.DEFAULT);
    Mac mac = Mac.getInstance("HmacSHA256");
    mac.init(new SecretKeySpec(key, "HmacSHA256"));
    mac.update((unixMillis + ".").getBytes(StandardCharsets.UTF_8));
    mac.update(body);
    String sig = Base64.encodeToString(mac.doFinal(), Base64.NO_WRAP);
    return "v1;" + appId + ";" + unixMillis + ";" + sig;
  }
}
