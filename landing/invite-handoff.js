// Invite code handoff shared by /invite/{code}, /dashboard/login.html, and
// the dashboard. The code has to outlive the URL: email confirmation, magic
// links, and the logged-out redirect from /dashboard/ all drop the query
// string. localStorage covers a new tab (the confirmation email); sessionStorage
// covers the same tab when localStorage is blocked. Cleared once the invite is
// claimed or rejected.
(function (global) {
    var KEY = 'booki_pending_invite';
    var NAME_KEY = 'booki_pending_invite_name';
    var BLOCK_KEY = 'booki_invite_blocked';
    // Survives a reload of the "check your email" screen. The password does
    // not: it lives in sessionStorage only, so this tab can sign in once the
    // link is clicked, and it dies when the tab closes.
    var AWAIT_KEY = 'booki_awaiting_verification';
    var SECRET_KEY = 'booki_verify_password';
    var AWAIT_TTL_MS = 24 * 60 * 60 * 1000;

    function normalize(raw) {
        return String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
    }

    function stores() {
        var list = [];
        try { if (global.localStorage) list.push(global.localStorage); } catch (e) {}
        try { if (global.sessionStorage) list.push(global.sessionStorage); } catch (e) {}
        return list;
    }

    function getFrom(store, key) {
        try { return store.getItem(key) || ''; } catch (e) { return ''; }
    }

    function readCode() {
        var fromUrl = '';
        try {
            fromUrl = normalize(new URLSearchParams(global.location.search).get('invite'));
        } catch (e) {}
        if (fromUrl) return fromUrl;
        var found = '';
        stores().some(function (store) {
            found = normalize(getFrom(store, KEY));
            return !!found;
        });
        return found;
    }

    function writeCode(code, name) {
        stores().forEach(function (store) {
            try {
                store.setItem(KEY, code);
                if (name) store.setItem(NAME_KEY, name);
            } catch (e) {}
        });
    }

    function clearCode() {
        stores().forEach(function (store) {
            try {
                store.removeItem(KEY);
                store.removeItem(NAME_KEY);
            } catch (e) {}
        });
    }

    // Only drop storage when it holds THIS code. An invalid link must not wipe
    // a different invite the browser was already holding.
    function clearCodeIf(code) {
        stores().forEach(function (store) {
            try {
                if (getFrom(store, KEY) === code) {
                    store.removeItem(KEY);
                    store.removeItem(NAME_KEY);
                }
            } catch (e) {}
        });
    }

    function readName() {
        var name = '';
        stores().some(function (store) {
            name = getFrom(store, NAME_KEY);
            return !!name;
        });
        return name;
    }

    function writeBlocked(title, detail) {
        var payload = JSON.stringify({ title: title, detail: detail });
        stores().forEach(function (store) {
            try { store.setItem(BLOCK_KEY, payload); } catch (e) {}
        });
    }

    function readBlocked() {
        var raw = '';
        stores().some(function (store) {
            raw = getFrom(store, BLOCK_KEY);
            return !!raw;
        });
        if (!raw) return null;
        try {
            var parsed = JSON.parse(raw);
            if (parsed && parsed.detail) return parsed;
        } catch (e) {}
        return { title: "This invite isn't valid", detail: raw };
    }

    function clearBlocked() {
        stores().forEach(function (store) {
            try { store.removeItem(BLOCK_KEY); } catch (e) {}
        });
    }

    function writeAwaiting(email) {
        var payload = JSON.stringify({ email: String(email || '').trim(), at: Date.now() });
        stores().forEach(function (store) {
            try { store.setItem(AWAIT_KEY, payload); } catch (e) {}
        });
    }

    function readAwaiting() {
        var raw = '';
        stores().some(function (store) {
            raw = getFrom(store, AWAIT_KEY);
            return !!raw;
        });
        if (!raw) return null;
        try {
            var parsed = JSON.parse(raw);
            if (!parsed || !parsed.email) return null;
            if (parsed.at && Date.now() - parsed.at > AWAIT_TTL_MS) return null;
            return { email: String(parsed.email), at: parsed.at || 0 };
        } catch (e) {
            return null;
        }
    }

    function clearAwaiting() {
        stores().forEach(function (store) {
            try { store.removeItem(AWAIT_KEY); } catch (e) {}
        });
        clearVerifySecret();
    }

    function sessionStore() {
        try { return global.sessionStorage || null; } catch (e) { return null; }
    }

    function writeVerifySecret(password) {
        var store = sessionStore();
        if (!store || !password) return;
        try { store.setItem(SECRET_KEY, password); } catch (e) {}
    }

    function readVerifySecret() {
        var store = sessionStore();
        if (!store) return '';
        return getFrom(store, SECRET_KEY);
    }

    function clearVerifySecret() {
        var store = sessionStore();
        if (!store) return;
        try { store.removeItem(SECRET_KEY); } catch (e) {}
    }

    // Origin passed as emailRedirectTo. The confirm-signup template appends
    // /verify?token={{ .TokenHash }}&type=signup, so this must be the origin
    // with no path and no trailing slash. A preview origin only works once it
    // is on the Auth redirect allow list; until then sign-up retries without it.
    function emailConfirmOrigin(origin) {
        var base = String(origin || '').trim().replace(/\/+$/, '');
        if (!/^https?:\/\//i.test(base)) return '';
        return base;
    }

    // Where /verify sends someone who just confirmed. Absolute, because that
    // page is at the site root. No invite means the ordinary dashboard, which
    // is still the organizer path.
    function dashboardTarget(code) {
        var normalized = normalize(code);
        if (!normalized) return '/dashboard/';
        return '/dashboard/?invite=' + encodeURIComponent(normalized);
    }

    function alreadyInGroupCopy(name) {
        var who = String(name || '').trim();
        if (!who) return 'You\u2019re already in this group';
        return 'You\u2019re already in ' + who + '\u2019s group';
    }

    function ensureInUrl(code) {
        try {
            var url = new URL(global.location.href);
            if (url.searchParams.get('invite') === code) return;
            url.searchParams.set('invite', code);
            global.history.replaceState({}, '', url.toString());
        } catch (e) {}
    }

    function stripFromUrl() {
        try {
            var url = new URL(global.location.href);
            if (!url.searchParams.has('invite') && !url.searchParams.has('mode')) return;
            url.searchParams.delete('invite');
            url.searchParams.delete('mode');
            global.history.replaceState({}, '', url.toString());
        } catch (e) {}
    }

    global.BookiInvite = {
        normalize: normalize,
        readCode: readCode,
        writeCode: writeCode,
        clearCode: clearCode,
        clearCodeIf: clearCodeIf,
        readName: readName,
        writeBlocked: writeBlocked,
        readBlocked: readBlocked,
        clearBlocked: clearBlocked,
        ensureInUrl: ensureInUrl,
        stripFromUrl: stripFromUrl,
        writeAwaiting: writeAwaiting,
        readAwaiting: readAwaiting,
        clearAwaiting: clearAwaiting,
        writeVerifySecret: writeVerifySecret,
        readVerifySecret: readVerifySecret,
        clearVerifySecret: clearVerifySecret,
        emailConfirmOrigin: emailConfirmOrigin,
        dashboardTarget: dashboardTarget,
        alreadyInGroupCopy: alreadyInGroupCopy,
    };
})(window);
