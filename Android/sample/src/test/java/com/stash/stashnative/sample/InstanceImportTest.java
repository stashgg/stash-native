package com.stash.stashnative.sample;

import static org.junit.Assert.*;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 21)
public class InstanceImportTest {
  @Test public void invalidLaterEntryDoesNotPartiallyImport() {
    MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
    String before = model.exportInstancesJson();
    assertEquals(-1, model.importInstancesJson("{\"instances\":[{\"appId\":\"fixture\",\"ingressSecret\":\"dummy\"},7]}"));
    assertEquals(before, model.exportInstancesJson());
  }

  @Test public void duplicatesWithinOneDocumentAreImportedOnlyOnce() {
    MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
    String instance = "{\"appId\":\"fixture\",\"ingressSecret\":\"dummy\"}";
    assertEquals(1, model.importInstancesJson("{\"instances\":[" + instance + "," + instance + "]}"));
    assertEquals(0, model.importInstancesJson("{\"instances\":[" + instance + "]}"));
  }

  /**
   * A-119: the checked-in v2 document (also imported by iOS/Sample/Tests) imports field by field,
   * and the exporter emits exactly its key set, so renaming a field on either platform fails.
   */
  @Test public void sharedExportFixtureImportsEveryFieldAndExportsItsKeySet() throws Exception {
    String fixture;
    try (java.io.InputStream in =
            getClass().getClassLoader().getResourceAsStream("instances-export-v2.json");
        java.util.Scanner scanner = new java.util.Scanner(in, "UTF-8").useDelimiter("\\A")) {
      fixture = scanner.next();
    }
    JSONObject expected = new JSONObject(fixture);
    JSONArray wanted = expected.getJSONArray("instances");
    MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
    assertEquals(wanted.length(), model.importInstancesJson(fixture));

    String text = model.exportInstancesJson();
    JSONObject exported = new JSONObject(text);
    assertEquals(keys(expected), keys(exported));
    assertEquals(2, exported.getInt("version"));
    JSONArray instances = exported.getJSONArray("instances");
    // The bundled instance stays first; imports follow in document order.
    assertEquals(wanted.length() + 1, instances.length());
    for (int i = 0; i < instances.length(); i++) {
      assertEquals(keys(wanted.getJSONObject(0)), keys(instances.getJSONObject(i)));
    }
    for (int i = 0; i < wanted.length(); i++) {
      JSONObject want = wanted.getJSONObject(i);
      JSONObject got = instances.getJSONObject(i + 1);
      assertEquals(want.getString("name"), got.getString("name"));
      assertEquals(want.getString("appId"), got.getString("appId"));
      assertEquals(want.getString("ingressSecret"), got.getString("ingressSecret"));
      assertEquals(want.getBoolean("production"), got.getBoolean("production"));
      assertEquals(want.getString("checkoutPayload"), got.getString("checkoutPayload"));
      assertEquals(want.getString("webshopPayload"), got.getString("webshopPayload"));
    }
    assertTrue(wanted.getJSONObject(0).getBoolean("production"));
    assertTrue(wanted.getJSONObject(0).getString("ingressSecret").contains("/"));
    assertNotEquals(MainViewModel.defaultCheckoutPayload(),
        wanted.getJSONObject(0).getString("checkoutPayload"));
    // Like iOS, the export leaves the '/' in base64 secrets unescaped.
    assertTrue(text.contains("\"" + wanted.getJSONObject(0).getString("ingressSecret") + "\""));
  }

  /**
   * The malformed documents iOS/Sample/Tests also imports: a missing or non-string credential
   * rejects the whole document, and null or non-string optional fields count as absent.
   */
  @Test public void sharedMalformedImportsMatchTheIosRules() throws Exception {
    JSONObject cases = new JSONObject(resource("instances-import-cases.json"));
    JSONArray rejected = cases.getJSONArray("rejected");
    assertEquals(4, rejected.length());
    for (int i = 0; i < rejected.length(); i++) {
      MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
      String before = model.exportInstancesJson();
      String document = rejected.getJSONObject(i).toString();
      assertEquals(document, -1, model.importInstancesJson(document));
      assertEquals(document, before, model.exportInstancesJson());
    }
    MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
    assertEquals(1, model.importInstancesJson(cases.getJSONObject("optionalFieldsAbsent").toString()));
    JSONObject imported =
        new JSONObject(model.exportInstancesJson()).getJSONArray("instances").getJSONObject(1);
    assertEquals("Untitled", imported.getString("name"));
    assertFalse(imported.getBoolean("production"));
    assertEquals(MainViewModel.defaultCheckoutPayload(), imported.getString("checkoutPayload"));
    assertEquals(MainViewModel.defaultWebshopPayload(), imported.getString("webshopPayload"));
  }

  private String resource(String name) throws java.io.IOException {
    try (java.io.InputStream in = getClass().getClassLoader().getResourceAsStream(name);
        java.util.Scanner scanner = new java.util.Scanner(in, "UTF-8").useDelimiter("\\A")) {
      return scanner.next();
    }
  }

  private static java.util.Set<String> keys(JSONObject object) {
    java.util.Set<String> keys = new java.util.TreeSet<>();
    java.util.Iterator<String> it = object.keys();
    while (it.hasNext()) {
      keys.add(it.next());
    }
    return keys;
  }

  @Test public void api21MigrationRemovesPlaintextAndKeepsCurrentSession() {
    android.app.Application app = RuntimeEnvironment.getApplication();
    android.content.SharedPreferences prefs = app.getSharedPreferences("StashNativeSample", 0);
    prefs.edit().putString("StashApiKey", "dummy-migration-secret").commit();
    MainViewModel model = new MainViewModel(app);
    assertTrue(model.credentialsAreSessionOnly());
    assertEquals("dummy-migration-secret", model.getActiveApiKey());
    assertFalse(prefs.contains("StashApiKey"));
    assertFalse(prefs.contains("ApiKeysJson"));
  }

  @Test @Config(sdk = 23)
  public void unreadableEncryptedStoreIsPreserved() throws Exception {
    android.app.Application app = RuntimeEnvironment.getApplication();
    java.io.File file = new java.io.File(app.getNoBackupFilesDir(), "credentials.v1");
    byte[] unreadable = "unreadable encrypted data".getBytes(java.nio.charset.StandardCharsets.UTF_8);
    try (java.io.FileOutputStream out = new java.io.FileOutputStream(file)) { out.write(unreadable); }
    CredentialStore store = new CredentialStore(app);
    assertNull(store.read());
    assertTrue(store.isSessionOnly());
    assertFalse(store.write("[]"));
    assertArrayEquals(unreadable, new android.util.AtomicFile(file).readFully());
  }
}
