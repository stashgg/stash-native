package com.stash.stashnative;

import android.webkit.WebView;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import java.util.Collections;

/** Keeps checkout interactions consistent with a native form while retaining editable controls. */
final class StashWebInteractionSupport {
  private StashWebInteractionSupport() {}

  static final String SCRIPT =
      "(function(){"
          + "if(window.__stashNativeInteractions)return;window.__stashNativeInteractions=true;var"
          + " viewport='width=device-width,initial-scale=1,minimum-scale=1,"
          + "maximum-scale=1,user-scalable=no,viewport-fit=cover';var"
          + " css='html{-webkit-touch-callout:none;touch-action:manipulation}'"
          + "+'body{-webkit-user-select:none;user-select:none}'"
          + "+'input,textarea,[contenteditable]:not([contenteditable=false])'"
          + "+'{-webkit-user-select:text;user-select:text;-webkit-touch-callout:default}'"
          + "+'[contenteditable=false]{-webkit-user-select:none;user-select:none;"
          + "-webkit-touch-callout:none}'"
          + "+'a,img{-webkit-user-drag:none}';function"
          + " apply(){if(!document.head)return;if(window===window.top){var"
          + " metas=document.querySelectorAll('meta[name=viewport]');if(!metas.length){var"
          + " meta=document.createElement('meta');meta.name='viewport';"
          + "meta.content=viewport;document.head.appendChild(meta);}else for(var"
          + " i=0;i<metas.length;i++)if(metas[i].content!==viewport)metas[i].content=viewport;}var"
          + " style=document.getElementById('__stash_native_interactions');"
          + "if(!style){style=document.createElement('style');"
          + "style.id='__stash_native_interactions';"
          + "style.textContent=css;document.head.appendChild(style);}else"
          + " if(style.textContent!==css)style.textContent=css;}apply();new"
          + " MutationObserver(function(records){for(var i=0;i<records.length;i++){var"
          + " target=records[i].target;if(target===document||target===document.documentElement||"
          + "(document.head&&document.head.contains(target))){apply();break;}}})"
          + ".observe(document,{childList:true,subtree:true,attributes:true,"
          + "attributeFilter:['name','content','id'],characterData:true});"
          + "document.addEventListener('contextmenu',function(event){var"
          + " target=event.composedPath?event.composedPath()[0]:event.target;"
          + "if(target&&target.nodeType!==1)target=target.parentElement;"
          + "if(target&&(target.isContentEditable||target.closest('input,textarea,select')))return;"
          + "event.preventDefault();},true);"
          + "var focusQueued=false,focusForced=false;function revealFocus(){focusQueued=false;"
          + "var force=focusForced;focusForced=false;if(force&&!document.hasFocus())return;"
          + "var element=document.activeElement;"
          + "while(element&&element.shadowRoot&&element.shadowRoot.activeElement)"
          + "element=element.shadowRoot.activeElement;"
          + "if(!element||!(element.isContentEditable||"
          + "/^(INPUT|TEXTAREA|SELECT|IFRAME)$/.test(element.tagName)))return;"
          + "var rect=element.getBoundingClientRect();if(rect.height<=0)return;"
          + "if(element.tagName==='IFRAME'){"
          + "if(rect.height<=innerHeight)"
          + "element.scrollIntoView({block:(rect.top<0||rect.bottom>innerHeight)"
          + "?'center':'nearest',inline:'nearest'});"
          + "if(element.contentWindow)"
          + "element.contentWindow.postMessage('__stash_focus_resize__','*');return;}"
          + "element.scrollIntoView({block:(rect.top<0||rect.bottom>innerHeight)"
          + "?'center':'nearest',inline:'nearest'});}"
          + "function scheduleFocus(force){focusForced=focusForced||force===true;"
          + "if(!focusQueued){focusQueued=true;"
          + "requestAnimationFrame(revealFocus);}}"
          + "addEventListener('message',function(event){if(window!==top&&event.source===parent&&"
          + "event.data==='__stash_focus_resize__'&&document.hasFocus())scheduleFocus(true);});"
          + "addEventListener('resize',scheduleFocus);"
          + "document.addEventListener('focusin',scheduleFocus,true);})();";

  static void install(WebView webView) {
    webView.setHorizontalScrollBarEnabled(false);
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
        WebViewCompat.addDocumentStartJavaScript(webView, SCRIPT, Collections.singleton("*"));
      }
    } catch (Throwable ignored) {
      // Older WebView providers use the navigation callback fallback.
    }
  }

  static void apply(WebView webView) {
    webView.evaluateJavascript(SCRIPT, null);
  }
}
