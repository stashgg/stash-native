package com.stash.stashnative.sample;

import android.content.Context;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Device-local sample credentials. API 21/22 deliberately keep credentials only in memory. */
final class CredentialStore {
  private static final String ALIAS = "stash.sample.credentials.v1";
  private final AtomicFile file;
  private boolean unavailable;

  CredentialStore(Context context) {
    file = new AtomicFile(new File(context.getNoBackupFilesDir(), "credentials.v1"));
  }

  String read() {
    if (Build.VERSION.SDK_INT < 23 || (!file.getBaseFile().exists()
        && !new File(file.getBaseFile().getPath() + ".bak").exists())) {
      return null;
    }
    try {
      ByteBuffer data = ByteBuffer.wrap(file.readFully());
      byte[] iv = new byte[12];
      data.get(iv);
      byte[] encrypted = new byte[data.remaining()];
      data.get(encrypted);
      Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
      cipher.init(Cipher.DECRYPT_MODE, key(false), new GCMParameterSpec(128, iv));
      return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
    } catch (Exception e) {
      // Preserve unreadable data; do not overwrite it with defaults or fall back to plaintext.
      unavailable = true;
      return null;
    }
  }

  boolean write(String json) {
    if (Build.VERSION.SDK_INT < 23) {
      return true; // Deliberate session-only policy.
    }
    if (unavailable) {
      return false;
    }
    FileOutputStream output = null;
    try {
      Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
      cipher.init(Cipher.ENCRYPT_MODE, key(true));
      byte[] encrypted = cipher.doFinal(json.getBytes(StandardCharsets.UTF_8));
      output = file.startWrite();
      output.write(cipher.getIV());
      output.write(encrypted);
      file.finishWrite(output);
      return true;
    } catch (Exception e) {
      if (output != null) {
        file.failWrite(output);
      }
      unavailable = true;
      return false;
    }
  }

  boolean isSessionOnly() {
    return Build.VERSION.SDK_INT < 23 || unavailable;
  }

  @android.annotation.TargetApi(23)
  private static SecretKey key(boolean create) throws Exception {
    KeyStore store = KeyStore.getInstance("AndroidKeyStore");
    store.load(null);
    if (!store.containsAlias(ALIAS) && create) {
      KeyGenerator generator = KeyGenerator.getInstance("AES", "AndroidKeyStore");
      generator.init(new KeyGenParameterSpec.Builder(ALIAS,
          KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
          .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
          .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
      return generator.generateKey();
    }
    return (SecretKey) store.getKey(ALIAS, null);
  }
}
