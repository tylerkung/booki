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
    };
})(window);
