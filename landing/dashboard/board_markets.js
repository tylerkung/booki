/**
 * Which main line the board shows when the table holds more than one.
 *
 * sync_games used to insert a new spread every time the number moved and
 * leave the old row bettable. The board query has no ORDER BY, so
 * playerMarketsByEvent kept whichever row arrived last — on Colts @ Texans
 * that was +11.5 from 08:00Z while +12.5 from 20:00Z was already stored.
 * submit_bets then refused the click: the row trailed its sibling.
 *
 * The featured row is the newest bettable one. An unbettable row is a line
 * the ingest has retired; a later updated_at on it (the retire write itself
 * bumps the timestamp) must not put it back on the board. Moneyline, spread
 * and total all go through here. Alternate lines are a different type and
 * are not collapsed.
 *
 * Loaded as a classic script before dashboard.js. The exports at the bottom
 * exist so node can require this file in tests; browsers have no `module`.
 */
function pickFeaturedMarket(current, incoming) {
    if (!incoming) return current || null;
    if (!current) return incoming;
    var currentOff = current.bettable === false;
    var incomingOff = incoming.bettable === false;
    if (currentOff !== incomingOff) return incomingOff ? current : incoming;
    var currentAt = Date.parse(current.updated_at || '') || 0;
    var incomingAt = Date.parse(incoming.updated_at || '') || 0;
    if (incomingAt !== currentAt) return incomingAt > currentAt ? incoming : current;
    return current;
}

/**
 * The market to store for one event and type. Unbettable rows are not shown:
 * with only those left, the cell is empty (an em dash) rather than a line
 * the server will refuse.
 */
function preferBoardMarket(current, incoming) {
    var pick = pickFeaturedMarket(current, incoming);
    if (!pick || pick.bettable === false) {
        return current && current.bettable !== false ? current : null;
    }
    return pick;
}

/** The one main line of `type` to render, or [] when none is bettable. */
function featuredMainList(markets, type) {
    var best = null;
    var list = markets || [];
    for (var i = 0; i < list.length; i++) {
        if (!list[i] || list[i].type !== type) continue;
        best = preferBoardMarket(best, list[i]);
    }
    return best ? [best] : [];
}

/**
 * What a failed submit does to the slip.
 *
 * clearSlip is always false. The previous handler treated
 * line_no_longer_offered as a stale board, toasted, then emptied the slip
 * and hid the panel in the same turn. The toast's enter transition was
 * interrupted by that re-render, so the first failure looked like the slip
 * had vanished on its own. The pick stays so the member can remove it and
 * add the line the board is now showing. refreshBoard is still true for the
 * errors that mean the rows on screen are not the ones the server will take.
 */
function isStaleBoardErrorMessage(raw) {
    var msg = String(raw || '');
    return /^Events? not found/.test(msg) ||
        /^Market not found/.test(msg) ||
        msg === 'line_no_longer_offered' ||
        msg === 'Market has no price';
}

function submitFailureDisposition(raw) {
    return {
        clearSlip: false,
        refreshBoard: isStaleBoardErrorMessage(raw),
    };
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        pickFeaturedMarket: pickFeaturedMarket,
        preferBoardMarket: preferBoardMarket,
        featuredMainList: featuredMainList,
        isStaleBoardErrorMessage: isStaleBoardErrorMessage,
        submitFailureDisposition: submitFailureDisposition,
    };
}
