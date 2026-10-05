package com.stash.stashnative.sample;

import static org.junit.Assert.*;
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
