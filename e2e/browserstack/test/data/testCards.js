// Stash test cards, see https://docs.stash.gg/guides/get-started/test-cards
// The number/expiry/cvc are the same test card. In the test environment the
// cardholder name is what drives the outcome: a normal name succeeds, and the
// special override names trigger specific declines.

module.exports = {
  success: {
    number: "4400002000000004",
    expiry: "03/30",
    cvc: "737",
    zip: "10001",
    name: "Test Buyer",
  },

  // Decline: not enough balance. Other override names: CARD_EXPIRED, FRAUD,
  // CVC_DECLINED, BLOCKED_CARD, 3D_NOT_AUTHENTICATED.
  declined: {
    number: "4400002000000004",
    expiry: "03/30",
    cvc: "737",
    zip: "10001",
    name: "NOT_ENOUGH_BALANCE",
  },
};
