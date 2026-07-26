package com.stash.stashnative.sample;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * A named Stash app credential: the app ID plus its ingress secret, with a production/test flag.
 * Both are needed to sign requests (see {@link StashHmac}). Each instance also carries its own
 * checkout and webshop request bodies, so payloads can be tailored per instance. Persisted as JSON
 * in SharedPreferences.
 */
final class ApiKeyEntry {

  final String id;
  String name;
  /** Stash app ID (Studio -> Project Settings -> App details); goes in the signature header. */
  String appId;
  /** Base64 ingress secret (Studio -> Project Settings -> API Secrets); the HMAC key. */
  String key;
  boolean production;
  /** Raw JSON body sent to the checkout endpoint for this instance. */
  String checkoutPayload;
  /** Raw JSON body sent to the webshop endpoint for this instance. */
  String webshopPayload;

  ApiKeyEntry(String id, String name, String appId, String key, boolean production,
      String checkoutPayload, String webshopPayload) {
    this.id = id;
    this.name = name != null ? name : "";
    this.appId = appId != null ? appId : "";
    this.key = key != null ? key : "";
    this.production = production;
    this.checkoutPayload = checkoutPayload != null ? checkoutPayload : "";
    this.webshopPayload = webshopPayload != null ? webshopPayload : "";
  }

  JSONObject toJson() throws JSONException {
    JSONObject o = new JSONObject();
    o.put("id", id);
    o.put("name", name);
    o.put("appId", appId);
    o.put("key", key);
    o.put("production", production);
    o.put("checkoutPayload", checkoutPayload);
    o.put("webshopPayload", webshopPayload);
    return o;
  }

  static ApiKeyEntry fromJson(JSONObject o) {
    // Entries saved before HMAC signing carry no appId; entries saved before per-instance payloads
    // carry no bodies -- MainViewModel.loadApiKeys fills empty payloads with the defaults.
    return new ApiKeyEntry(
        o.optString("id"),
        o.optString("name"),
        o.optString("appId"),
        o.optString("key"),
        o.optBoolean("production", false),
        o.optString("checkoutPayload"),
        o.optString("webshopPayload"));
  }
}
