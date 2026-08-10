const { switchToCheckoutWebview, switchToNative } = require("./webview");

// Fills the Stash checkout card form and submits.
//
// The card number, expiry and CVC are Adyen "secured fields": each lives in a
// cross-origin iframe (checkoutshopper-test.adyen.com). WKWebView blocks JS from
// reading or switching into those frames, so we cannot type into them via the
// webview context. Instead we read each field's on-screen rect from the main
// document, map it to a native screen coordinate, tap it, and type on the native
// keyboard. Holder name, postcode and the Pay button are in the main frame, so
// those we drive with plain JS.
const FIELDS = {
  cardNumber: "[class*=cardNumber]",
  expiry: "[class*=expiryDate]",
  cvc: "[class*=securityCode]",
  holderName: 'input[autocomplete="cc-name"]',
  postal: 'input[autocomplete="postal-code"]',
};

async function fillCardForm(card) {
  await switchToCheckoutWebview();

  // Reveal the card form (the checkout defaults to the wallet buttons).
  await clickByText(/^card/i);
  await driver.pause(2500);

  // Adyen fields auto-format the slash and spacing, so send digits only.
  await tapType(FIELDS.cardNumber, card.number.replace(/\s/g, ""));
  await tapType(FIELDS.expiry, card.expiry.replace(/\D/g, ""));
  await tapType(FIELDS.cvc, card.cvc);
  await tapType(FIELDS.holderName, card.name);
  await tapType(FIELDS.postal, card.zip);

  // Submit from the main frame, which is same-origin and scriptable.
  await switchToCheckoutWebview();
  await clickByText(/^pay$/i);
  await switchToNative();
}

// Scrolls the field into view, maps its webview rect to a native screen point,
// taps to focus it, then types on the native keyboard. Rects are recomputed per
// field because focusing one can scroll the page and move the others.
async function tapType(selector, value) {
  await switchToCheckoutWebview();
  const r = await browser.execute((sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    // Keep the field clear of the keyboard at the bottom of the screen.
    el.scrollIntoView({ block: "center" });
    const b = el.getBoundingClientRect();
    return { x: b.x, y: b.y, w: b.width, h: b.height, innerW: window.innerWidth };
  }, selector);
  if (!r) return;

  await switchToNative();
  const wv = await $("//XCUIElementTypeWebView");
  const loc = await wv.getLocation();
  const size = await wv.getSize();
  const scale = size.width / r.innerW;
  const p = {
    x: Math.round(loc.x + (r.x + r.w / 2) * scale),
    y: Math.round(loc.y + (r.y + r.h / 2) * scale),
  };
  await driver.action("pointer").move(p).down().up().perform();
  await driver.pause(500);

  // Explicit key down/up per char; wdio's keys() sends a malformed sequence to
  // WDA in the native context.
  const kb = driver.action("key");
  for (const ch of value) kb.down(ch).up(ch);
  await kb.perform();
  await driver.pause(300);
}

// Clicks the first main-frame button whose trimmed text matches the regex.
// Runs in the webview context.
async function clickByText(re) {
  await browser.execute(
    (pattern, flags) => {
      const rx = new RegExp(pattern, flags);
      const btn = Array.from(document.querySelectorAll("button,[role=button]")).find((e) =>
        rx.test((e.innerText || "").trim())
      );
      if (btn) btn.click();
    },
    re.source,
    re.flags
  );
}

module.exports = { fillCardForm };
