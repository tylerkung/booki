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

/**
 * A retired or off-board moneyline. submit_bet and submit_parlay say
 * market_not_bettable. submit_bets says the sentence. Both used to reach the
 * member as raw text, and the board did not refresh.
 */
function isOffBoardSlipError(raw) {
    var msg = String(raw || '');
    return msg === 'off_the_board' ||
        msg === 'market_not_bettable' ||
        msg === 'This market is not available to bet';
}

function submitFailureDisposition(raw) {
    var msg = String(raw || '');
    var off = isOffBoardSlipError(msg);
    return {
        clearSlip: false,
        refreshBoard: isStaleBoardErrorMessage(msg) || off,
        markOffBoard: off,
    };
}

/**
 * Slip indexes to mark off the board.
 *
 * `failed[].index` is the index in the staked list that was sent, not the
 * index in the slip. `stakedSlipIndexes[failedIndex]` is the slip index.
 */
function slipLegsToMarkOffBoard(stakedSlipIndexes, failed) {
    var out = [];
    var rows = failed || [];
    for (var i = 0; i < rows.length; i++) {
        if (!isOffBoardSlipError(rows[i] && rows[i].error)) continue;
        var slipIndex = stakedSlipIndexes[rows[i].index];
        if (typeof slipIndex === 'number') out.push(slipIndex);
    }
    return out;
}

/**
 * A moneyline the board will not offer.
 *
 * Missing, retired, either side worse than -10000, or last written more than
 * 18 hours ago. -10000 itself stays. A pick'em (-110/-110, -105/-115) stays.
 * The same numbers live in supabase/functions/_shared/h2h.ts. The test checks
 * they match.
 */
var OFF_BOARD_AMERICAN = -10000;
var MONEYLINE_MAX_AGE_MS = 18 * 60 * 60 * 1000;
var OFF_BOARD_LABEL = 'Off the board';

function moneylinePriceOffBoard(price) {
    // Same rule as isOffBoardAmerican: a null or missing price is off the
    // board, not a price of zero that can still be tapped.
    if (typeof price !== 'number' || !isFinite(price)) return true;
    return price < OFF_BOARD_AMERICAN;
}

function moneylineMarketOnBoard(market, nowMs) {
    if (!market || market.bettable === false) return false;
    if (moneylinePriceOffBoard(market.odds_a) || moneylinePriceOffBoard(market.odds_b)) return false;
    var at = Date.parse(market.updated_at || '');
    if (!isFinite(at)) return false;
    var now = typeof nowMs === 'number' ? nowMs : Date.now();
    return now - at <= MONEYLINE_MAX_AGE_MS;
}

/**
 * The number in the league header. Games only.
 *
 * leagueGroup.events also holds the championship outright, which made NFL,
 * NCAAF, NBA, NCAAB and NHL read one high. The futures block still renders
 * from leagueGroup.outrights. This count does not decide that.
 */
function leagueHeaderCount(group) {
    if (!group || !group.games) return 0;
    return group.games.length;
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        pickFeaturedMarket: pickFeaturedMarket,
        preferBoardMarket: preferBoardMarket,
        featuredMainList: featuredMainList,
        isStaleBoardErrorMessage: isStaleBoardErrorMessage,
        isOffBoardSlipError: isOffBoardSlipError,
        submitFailureDisposition: submitFailureDisposition,
        slipLegsToMarkOffBoard: slipLegsToMarkOffBoard,
        OFF_BOARD_AMERICAN: OFF_BOARD_AMERICAN,
        MONEYLINE_MAX_AGE_MS: MONEYLINE_MAX_AGE_MS,
        OFF_BOARD_LABEL: OFF_BOARD_LABEL,
        moneylineMarketOnBoard: moneylineMarketOnBoard,
        moneylinePriceOffBoard: moneylinePriceOffBoard,
        leagueHeaderCount: leagueHeaderCount,
    };
}
