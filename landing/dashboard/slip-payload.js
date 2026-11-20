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

  var SLIP_KEY_STORAGE = 'booki_slip_idempotency_keys';
  var slipKeyMemory = {};

  function slipLower(value) {
    return String(value == null ? '' : value).trim().toLowerCase();
  }

  function slipMoney(value) {
    if (typeof value === 'number' && isFinite(value)) return slipMoney(value.toFixed(2));
    var trimmed = String(value == null ? '' : value).trim();
    if (!/^-?\d+(\.\d+)?$/.test(trimmed)) return '';
    var negative = trimmed.charAt(0) === '-';
    var unsigned = negative ? trimmed.slice(1) : trimmed;
    var parts = unsigned.split('.');
    var cents = (parts[1] || '') + '00';
    var normalized = String(parseInt(parts[0] || '0', 10)) + '.' + cents.slice(0, 2);
    return negative ? '-' + normalized : normalized;
  }

  function slipOdds(value) {
    if (typeof value === 'number' && isFinite(value) && Math.floor(value) === value) return value;
    if (typeof value === 'string' && /^[+-]?\d+$/.test(value.trim())) return Number(value.trim());
    return null;
  }

  // What the slip will actually POST. A retry of this string reuses one key.
  // A stake, price, or selection change is a different string and a new key.
  function slipFingerprint(slip) {
    var player = slipLower(slip.player_id);
    var bookie = slipLower(slip.bookie_id);
    var selections = slip.selections || [];
    if (slip.mode === 'multi') {
      return JSON.stringify({
        mode: 'multi',
        player_id: player,
        bookie_id: bookie,
        stake: slipMoney(slip.multiStake),
        combined_odds: slipOdds(slip.combinedOdds),
        legs: selections.map(function (s) {
          return {
            event_id: slipLower(s.event_id),
            market_id: slipLower(s.market_id),
            side: s.side == null ? '' : String(s.side),
            side_indicator: s.side_indicator == null ? '' : String(s.side_indicator),
            odds: slipOdds(s.odds),
          };
        }),
      });
    }
    var bets = [];
    var stakes = slip.stakes || {};
    for (var i = 0; i < selections.length; i++) {
      var stake = Number(stakes[i]) || 0;
      if (stake <= 0) continue;
      var sel = selections[i];
      bets.push({
        event_id: slipLower(sel.event_id),
        market_id: slipLower(sel.market_id),
        side: sel.side_indicator == null ? '' : String(sel.side_indicator),
        odds: slipOdds(sel.odds),
        stake: slipMoney(stake),
      });
    }
    return JSON.stringify({
      mode: 'singles',
      player_id: player,
      bookie_id: bookie,
      bets: bets,
    });
  }

  function readSlipKeys(storage) {
    if (!storage || !storage.getItem) return {};
    try {
      var parsed = JSON.parse(storage.getItem(SLIP_KEY_STORAGE) || '{}');
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
      return parsed;
    } catch (e) {
      return {};
    }
  }

  function writeSlipKeys(storage, map) {
    if (!storage || !storage.setItem) return;
    try {
      storage.setItem(SLIP_KEY_STORAGE, JSON.stringify(map));
    } catch (e) { /* private mode; the in-page map still dedupes a double tap */ }
  }

  function defaultSlipKey() {
    var c = typeof crypto !== 'undefined' ? crypto : null;
    if (c && typeof c.randomUUID === 'function') return c.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (ch) {
      var n = Math.random() * 16 | 0;
      return (ch === 'x' ? n : (n & 0x3 | 0x8)).toString(16);
    });
  }

  // One key per fingerprint, shared by every caller in this page (a double
  // tap, a second Alpine instance) and by a later retry in this tab.
  function claimSlipKey(storage, fingerprint, mint) {
    var map = readSlipKeys(storage);
    var stored = typeof map[fingerprint] === 'string' ? map[fingerprint] : '';
    var remembered = typeof slipKeyMemory[fingerprint] === 'string' ? slipKeyMemory[fingerprint] : '';
    var key = stored || remembered || (mint || defaultSlipKey)();
    slipKeyMemory[fingerprint] = key;
    map[fingerprint] = key;
    var names = Object.keys(map);
    if (names.length > 50) {
      for (var i = 0; i < names.length && Object.keys(map).length > 50; i++) {
        if (names[i] === fingerprint) continue;
        delete map[names[i]];
        delete slipKeyMemory[names[i]];
      }
    }
    writeSlipKeys(storage, map);
    return key;
  }

  function releaseSlipKey(storage, fingerprint) {
    delete slipKeyMemory[fingerprint];
    var map = readSlipKeys(storage);
    if (Object.prototype.hasOwnProperty.call(map, fingerprint)) {
      delete map[fingerprint];
      writeSlipKeys(storage, map);
    }
  }

  root.BookiSlip = {
    singleBetPayload: singleBetPayload,
    parlayLegPayload: parlayLegPayload,
    slipFingerprint: slipFingerprint,
    claimSlipKey: claimSlipKey,
    releaseSlipKey: releaseSlipKey,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
