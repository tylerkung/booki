/**
 * First-touch attribution capture.
 *
 * Runs on every page. Records where a visitor came from the FIRST time they
 * arrive, and never overwrites it — someone who finds Booki through a blog post,
 * leaves, and comes back a week later via a Google ad was caused by the blog
 * post. Last-touch would credit the ad, which is the channel that closed rather
 * than the one that worked. Both are defensible; first-touch is the one that
 * answers "where should we spend more", which is the question being asked.
 *
 * Nothing is sent anywhere here. This only writes to localStorage. The value is
 * read at signup by dashboard.js and written to user_attribution once, so a
 * visitor who never signs up is never recorded anywhere — no tracking pixel, no
 * third party, no request.
 */
(function () {
    'use strict';

    var KEY = 'booki_attribution_v1';

    // Already captured? Then this is not a first touch and we leave it alone.
    // This is the whole point of the module, so it comes first.
    try {
        if (localStorage.getItem(KEY)) return;
    } catch (e) {
        return;                       // private mode / storage blocked — do nothing
    }

    var params = new URLSearchParams(window.location.search);
    var get = function (k) {
        var v = params.get(k);
        return v ? v.slice(0, 200) : null;   // bound it; query strings are attacker-controlled
    };

    var referrer = document.referrer || '';
    var referrerHost = '';
    try {
        if (referrer) {
            var h = new URL(referrer).hostname;
            // Same-site navigation is not a referral. Without this, every visitor
            // who clicks from the homepage to a blog post is recorded as
            // "referred by bookisports.com".
            if (h && h !== window.location.hostname) referrerHost = h;
        }
    } catch (e) { /* malformed referrer, leave blank */ }

    var record = {
        utm_source:   get('utm_source'),
        utm_medium:   get('utm_medium'),
        utm_campaign: get('utm_campaign'),
        utm_term:     get('utm_term'),
        utm_content:  get('utm_content'),
        gclid:        get('gclid'),
        fbclid:       get('fbclid'),
        referrer:     referrerHost ? referrer.slice(0, 500) : null,
        referrer_host: referrerHost || null,
        landing_path: (window.location.pathname || '/').slice(0, 300),
        first_seen_at: new Date().toISOString()
    };

    // A visitor with no campaign, no paid click and no external referrer is
    // direct — someone who typed the URL or used a bookmark. Worth storing as a
    // deliberate value rather than an empty row, because "direct" is a real
    // answer and an absent row is not.
    var hasSignal = record.utm_source || record.gclid || record.fbclid || record.referrer_host;
    if (!hasSignal) record.utm_source = 'direct';

    try {
        localStorage.setItem(KEY, JSON.stringify(record));
    } catch (e) { /* quota or blocked — attribution is not worth breaking a page over */ }
})();
