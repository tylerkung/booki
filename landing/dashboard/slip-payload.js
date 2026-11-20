// Builds the single and multi-pick request bodies the dashboard bet slip posts.
// Bet-slip payloads.
//
// Singles keep `side` as 'a' or 'b'. That is what the deployed submit_bets
// accepts. The readable label rides in side_label, which production ignores
// and the new function does not need in order to store the market's label.
//
// Parlays send the label in `side` and the letter in `side_indicator`. The
// deployed submit_parlay already accepts that, which is why multi-picks kept
// working on the preview.
(function (root) {
  function singleBetPayload(sel, stake) {
    return {
      event_id: sel.event_id,
      market_id: sel.market_id,
      side: sel.side_indicator,
      side_label: sel.side,
      odds: sel.odds,
      stake: stake,
    };
  }

  function parlayLegPayload(sel) {
    return {
      event_id: sel.event_id,
      market_id: sel.market_id,
      side: sel.side,
      side_indicator: sel.side_indicator,
      odds: sel.odds,
    };
  }

  root.BookiSlip = { singleBetPayload: singleBetPayload, parlayLegPayload: parlayLegPayload };
})(typeof globalThis !== 'undefined' ? globalThis : this);
