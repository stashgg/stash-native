# Responsive presentation in 3.0

Stash sizes checkout against the current app window, its safe area, keyboard overlap, and separating folds. Phone/tablet identity and portrait/landscape are not sizing inputs. Dimensions are points on iOS and density-independent pixels on Android.

## Configuration

| Property | iOS card | Android card |
|---|---:|---:|
| `preferredContentWidth` | 400 | 400 |
| `preferredContentHeight` | 560 | 560 |
| `maximumContentHeight` | 720 | 720 |
| `edgeMargin` | 16 | 16 |

Preferred width is bounded by usable space. Preferred height is the card's resting-height ceiling and fallback. A zero maximum uses the available height; the card default caps expansion at 720 points/dp to avoid an excessively tall payment form on large windows. Set it to zero explicitly when full available height is desired.

`allowDismiss` defaults to `true` and permits user dismissal while payment processing is inactive. `autoClose` defaults to `true` and closes on a payment success/failure signal. Native background matching is automatic; card configuration has no color override.

A card also has `orientationPreference`, either `followHost` (default) or `portrait`. Portrait is a best-effort request, not a lock. A host or operating system can decline it, and checkout then fits the actual window. The SDK does not override a host's orientation policy.

Configuration is copied when a presentation opens. Later mutations of the caller's object do not change an active checkout. Non-finite or invalid dimensions use defaults. The actual available area always wins over requested dimensions, including in very small windows.

## Card

A card uses a bottom sheet in compact space and a floating presentation when the platform has room. Every iOS card uses UIKit's `UISheetPresentationController`, including on Duo. UIKit owns its surface, grabber, touch feedback, interactive transitions, and placement. Preferred content width is not a promise of exact outer-sheet width.

When both host size classes are regular, iOS uses native form-sheet sizing with a single system large detent and the selected preferred content size. This floating sheet has one physical stop. Public `expand()` and `collapse()` change its selected size; native dragging retains UIKit spring and dismissal behavior.

Compact iOS layouts use custom resting and expanded detents on iOS 16+. iOS 15 compact layouts use native medium and large detents, or large alone in compact height, so exact configured attached-sheet heights require iOS 16+. Android uses its native view hierarchy with the same semantic states and centers the card in wide usable regions.

For iOS floating form sheets, iOS 16+ compact sheets, and Android, the resting state fits reported intrinsic content up to `preferredContentHeight`. With no usable measurement, that property is the resting height. The expanded state uses the available height, limited by `maximumContentHeight`. If both resolve to the same height, the SDK still remembers the selected semantic state for the next resize. Compact custom detents then expose one physical stop; floating iOS form sheets always have one native stop.

The same WebView remains alive during rotation, unfolding, keyboard changes, and window resizing. Resizing does not reload checkout, emit a new page-loaded event, or reset the selected state. The SDK requests animated changes to detents or floating preferred size; interactive window resizing follows current bounds. Opening the keyboard temporarily expands the card to the available editing space. Closing it restores the selected resting or expanded state.

At rest, compact iOS cards stay below active top occlusions. Dragging upward, calling `expand()`, or opening the keyboard can expand the native background behind a status region while the WebView fits beside it. The resting and expanded heights are resolved independently so both stops remain available before a gesture begins. Closing the keyboard restores the selected state.

The iOS WebView fills the card's usable surface beneath UIKit's grabber. No separate native header band or extra handle height is added to configured or measured content. Checkout pages should keep header controls clear of the grabber.

On iOS, an internal read-only page hint tries to match an identifiable opaque, uniform background at the page edge or on its enclosing checkout surface. If it cannot identify one, the SDK falls back to WebKit's under-page background or the native theme. This is best-effort flat-color matching; it does not reproduce images, gradients, or compositing effects. The hint changes no page styles and requires no public bridge call.

When the same opaque surface covers the viewport, iOS also matches the WebView's native backing to that color during resizing. The SDK releases its inferred override when the surface no longer covers the viewport or navigation changes the document. Transparent pages use WebKit's automatic background or the native theme fallback.

On iOS, the WebView paints through the bottom safe area while its top and horizontal bounds stay within the usable pane. Pages own safe-area spacing for scrolling content and fixed or sticky controls. The SDK supplies `viewport-fit=cover`; use `env(safe-area-inset-bottom)` padding on the relevant page wrappers so content remains reachable above the home indicator. Native scroll indicators avoid the unsafe area, but the SDK does not add content padding or automatically make arbitrary footers safe.

```css
.checkout-safe-area {
  padding-bottom: env(safe-area-inset-bottom, 0px);
}
```

### Optional content sizing

Content sizing is optional. For intrinsic sizing, mark one top-level content wrapper inside any outer safe-area padding:

```html
<div class="checkout-safe-area">
  <main data-stash-content>
    <!-- Checkout content, including ordinary page padding. -->
  </main>
</div>
```

The SDK observes this element when it has a usable intrinsic height. Do not make its height depend on the viewport (`100vh`, `min-height: 100%`, fixed positioning, or sticky positioning). The document's `scrollHeight` is not an intrinsic measurement: it can include the viewport itself and create a resize feedback loop.

Alternatively, report the intrinsic height explicitly:

```javascript
const content = document.querySelector('#checkout');
function reportContentHeight() {
  window.stash_sdk?.setContentHeight(content.getBoundingClientRect().height);
}
new ResizeObserver(reportContentHeight).observe(content);
reportContentHeight();
```

The value is the full height of checkout content in CSS pixels at its current layout viewport width. Include ordinary page padding; exclude native handles, chrome, and outer safe-area padding. Keep that outer padding outside `[data-stash-content]` as well. A cross-origin payment iframe must communicate its own desired height to its embedding page if precise sizing is needed.

The SDK tags measurements with the active document and viewport, converts CSS pixels to native logical units, and discards stale or invalid measurements. It coalesces updates and defers them during an active drag. Expansion does not replace the resting-height measurement.

## Embedded interaction

iOS covers the initial WebView with a native loading surface and fades into rendered content. The loading surface keeps its native theme appearance while the page initializes. The cover is used only for the initial reveal; later page navigation does not hide an active checkout. Reduced Motion removes the fade.

For `https://checkout.stash.gg` and `https://checkout.stashstaging.com`, a single `theme=light` or `theme=dark` parameter also delays the initial reveal until the page's root `data-color-scheme` matches. This uses the Stash checkout theme contract so a previously saved page theme does not flash before the requested theme is applied. The SDK reads this marker without changing page styles or storage and checks it again after the paint boundary. Other origins retain the usual content and paint readiness behavior. The existing 15-second foreground-time limit bounds the initial cover if the expected page state never arrives; background time does not consume that limit. A failed readiness evaluation after navigation finishes also releases the cover.

Cards keep the page at its native layout scale. Pinch, double-tap, input focus, or page changes to viewport metadata must not magnify checkout. Two-finger gestures must not become sheet drags.

Checkout labels, images and links do not expose browser selection, drag, or preview menus. Editable fields retain native selection, clipboard actions, keyboard behavior and autofill, including payment fields in iframes. The SDK does not replace those fields or intercept their typing. iOS omits WebKit's previous/next/Done accessory toolbar to leave more room for checkout.

UIKit's grabber overlays the iOS web surface and retains native dragging and touch feedback.

Checkout owns its text and page colors. The SDK supplies the theme query parameter without forcing page CSS into dark mode. The page paints the bottom safe area; native background matching does not replace its layout. The iOS native backing follows the automatic page-matching policy described above.

## Fold and window behaviour

Keep checkout in one usable region rather than splitting payment fields across a separating hinge. Layout uses current local coordinates and independently handles each safe-area edge. Do not assume symmetric insets or use the physical screen dimensions for an app window.

Full iPhone Duo adaptation depends on the host application being built with the iOS 27.1 SDK; updating only the framework cannot opt an older host build into new display behaviour. Host apps should use scene lifecycle and permit the resizing modes they intend to support. See [Apple's Duo guidance](https://developer.apple.com/videos/play/tech-talks/111461/).

## Verification

Use [the responsive test page](../.github/test/responsive.html) for short/long content, persistent input, content hints, expansion, and processing locks. Content changes should affect eligible card resting heights while preserving the selected expanded state.

A valid resize test preserves the WebView, page-load count, typed input, scroll position, payment state, and callback ordering. Simulator screenshots alone do not establish real-device payment-provider or game-engine behaviour.
