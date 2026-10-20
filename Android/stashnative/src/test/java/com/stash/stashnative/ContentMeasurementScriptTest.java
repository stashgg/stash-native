package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.Assume;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/**
 * Robolectric cannot run this script. iOS hosted tests execute the same body, so this keeps the
 * Android copy textually equal to the iOS copy apart from transport and document-id quoting.
 * Robolectric supplies the real org.json used to quote the document id.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class ContentMeasurementScriptTest {
  private static final String ID = "document-test";

  @Test
  public void scriptMatchesIosMeasurementScript() throws Exception {
    File source =
        new File(
            System.getProperty("user.dir"),
            "../../iOS/StashNative/Sources/StashNative/StashNativeViewUtils.m");
    Assume.assumeTrue("iOS sources are not in this checkout", source.isFile());
    String objc = new String(Files.readAllBytes(source.toPath()), StandardCharsets.UTF_8);
    int start = objc.indexOf("NSString *StashContentMeasurementScript(");
    int end = objc.indexOf("return [source", start);
    assertTrue(start >= 0 && end > start);
    StringBuilder ios = new StringBuilder();
    Matcher literal =
        Pattern.compile("@\"((?:[^\"\\\\]|\\\\.)*)\"").matcher(objc.substring(start, end));
    while (literal.find()) {
      ios.append(unescape(literal.group(1)));
    }
    String expected =
        ios.toString()
            .replace("'__STASH_DOCUMENT_ID__'", "<id>")
            .replaceAll(
                "window\\.webkit\\.messageHandlers\\.stashContentHeight"
                    + "\\.postMessage\\((\\{[^}]*\\})\\)",
                "<send $1>")
            .replace("\n", "");
    String actual =
        StashContentSizeSupport.script(ID)
            .replace("\"" + ID + "\"", "<id>")
            .replaceAll(
                "StashAndroid\\.setContentHeight\\(JSON\\.stringify\\((\\{[^}]*\\})\\)\\)",
                "<send $1>");
    assertEquals(expected, actual);
  }

  @Test
  public void stylesheetScanIsCachedButMatchedOnEveryMeasurement() {
    String script = StashContentSizeSupport.script(ID);
    // The script is one line, so a line comment would disable everything after it.
    assertFalse(script.contains("//"));
    assertTrue(script.contains("if (sheetsChanged()) sheetCache = scanSheets();"));
    assertTrue(script.contains("root.closest(sheetCache.selector) === null"));
    assertTrue(script.contains("if (sheetCache.selector === null) return false;"));
    assertTrue(script.contains("} catch (error) { selectors = null; }"));
    assertTrue(script.contains("if (sheetCache && sheetMutation(records)) sheetCache = null;"));
    assertTrue(script.contains("/^(?:style|link)$/i.test(node.nodeName)"));
    assertTrue(script.contains("sheetCache = null;    if (ro) ro.disconnect();"));
  }

  private static String unescape(String value) {
    StringBuilder out = new StringBuilder();
    for (int index = 0; index < value.length(); index++) {
      char c = value.charAt(index);
      if (c == '\\' && index + 1 < value.length()) {
        char next = value.charAt(++index);
        out.append(next == 'n' ? '\n' : next == 't' ? '\t' : next);
      } else {
        out.append(c);
      }
    }
    return out.toString();
  }
}
