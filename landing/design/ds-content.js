/**
 * Design system content.
 *
 * One entry per section — id, nav label, and the markup for its pane. Kept in
 * one file so adding a section is a single edit and the rail builds itself,
 * rather than a nav that drifts out of sync with the panes it points at.
 */
const DS_SECTIONS = [

/* ─────────────────────────────────────────────────────────── BRAND ── */
{ id: 'brand', label: 'Brand Identity', html: `
  <h1 class="ds-h1">Brand Identity</h1>
  <p class="ds-intro">
    Booki is a dark product with one loud colour. The wordmark is the only
    decorative element in the system — everything else earns its place by
    carrying information. Slogan: <strong>Be The House</strong>, no full stop.
  </p>

  <p class="ds-label">Wordmark</p>
  <div class="ds-demo">
    <div style="background:#0A0A12;padding:26px 32px;border-radius:12px;border:1px solid var(--border)">
      <img src="../assets/logo-booki-blk.svg" alt="Booki" style="height:38px">
      <div class="ds-anno">logo-booki-blk.svg &middot; primary, for dark grounds</div>
    </div>
    <div style="background:#F8F8F8;padding:26px 32px;border-radius:12px">
      <img src="../assets/logo-booki-wh.svg" alt="Booki" style="height:38px">
      <div class="ds-anno" style="color:#6B6B7B">logo-booki-wh.svg &middot; flat, for light grounds</div>
    </div>
  </div>
  <p class="ds-note">
    Despite the name, <code class="t">blk</code> is the one used on dark: white letters with a
    #0A0A12 outline. <code class="t">wh</code> is a flat single-fill version. Reaching for the
    wrong one is the most common brand mistake in this codebase.
  </p>

  <p class="ds-label">Voice</p>
  <div class="ds-demo col">
    <ul class="ds-do">
      <li>Plain and specific. "Settle up" not "reconcile balances".</li>
      <li>Say what happened. "Pick placed" not "Success!".</li>
      <li>Compliance vocabulary in anything user-facing: Organizer, Member, Pick, Stake, Multi-Pick.</li>
    </ul>
  </div>
` },

/* ────────────────────────────────────────────────────────── COLOUR ── */
{ id: 'colors', label: 'Colors', html: `
  <h1 class="ds-h1">Colors</h1>
  <p class="ds-intro">
    Electric cyan is the signature — actions, focus, wins. Semantic colours carry
    data meaning and are never decorative: cyan is a win, red is a loss, and
    neither is ever used to make something look nice. Click any swatch to copy it.
  </p>

  <p class="ds-label">Core surfaces</p>
  <div class="ds-swatches">
    ${swatch('background','#0A0A12','App background, sheets')}
    ${swatch('cardBackground','#14141F','Cards, elevated containers')}
    ${swatch('elevatedBackground','#1E1E2D','Modals, popovers, nested')}
    ${swatch('border','#2A2A3A','Dividers, card edges')}
    ${swatch('divider','#22222E','Subtle separation')}
  </div>

  <p class="ds-label">Text</p>
  <div class="ds-swatches">
    ${swatch('textPrimary','#F8F8F8','Headlines, primary content')}
    ${swatch('textSecondary','#A8A8B8','Supporting text, labels')}
    ${swatch('textMuted','#6B6B7B','Disabled, hints')}
  </div>

  <p class="ds-label">Accent</p>
  <div class="ds-swatches">
    ${swatch('accent','#00F5D4','Actions, links, focus, wins')}
    ${swatch('accentSecondary','#9D4EDD','Gradients, secondary emphasis')}
    ${swatch('accentTertiary','#FF006E','Highlights, special elements')}
    ${swatch('gold','#FFE66D','Streaks, achievements')}
  </div>

  <p class="ds-label">Semantic &amp; status</p>
  <div class="ds-swatches">
    ${swatch('danger','#FF6B6B','Losses, destructive, errors')}
    ${swatch('warning','#FFA94D','Pending, attention needed')}
    ${swatch('scheduled','#7B68EE','Upcoming events')}
    ${swatch('finalStatus','#5C5C6F','Completed events')}
  </div>

  <p class="ds-label">Aliases</p>
  <p class="ds-note">Same value, deliberately separate token — so a win can stop being cyan without dragging every button with it.</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Resolves to</th><th>Meaning</th></tr></thead>
    <tbody>
      <tr><td><code class="t">live</code></td><td>accent &middot; #00F5D4</td><td>In-progress</td></tr>
      <tr><td><code class="t">win</code></td><td>accent &middot; #00F5D4</td><td>Winning pick</td></tr>
      <tr><td><code class="t">loss</code></td><td>danger &middot; #FF6B6B</td><td>Losing pick</td></tr>
      <tr><td><code class="t">push</code></td><td>textSecondary &middot; #A8A8B8</td><td>Push / void</td></tr>
    </tbody>
  </table></div>
` },

/* ────────────────────────────────────────────────────── TYPOGRAPHY ── */
{ id: 'type', label: 'Typography', html: `
  <h1 class="ds-h1">Typography</h1>
  <p class="ds-intro">
    System font throughout — it renders numbers beautifully, and this product is
    mostly numbers. Three weights maximum on any one screen. Every figure uses
    monospaced digits so columns line up and prices do not jitter as they change.
  </p>

  <p class="ds-label">Scale</p>
  <div class="ds-demo col" style="gap:0">
    ${type('display','34 / Bold / 1.1','$1,284.50','font-size:34px;font-weight:700;font-variant-numeric:tabular-nums')}
    ${type('title1','28 / Bold / 1.2','Screen title','font-size:28px;font-weight:700')}
    ${type('title2','22 / Semibold / 1.25','Section header','font-size:22px;font-weight:600')}
    ${type('headline','17 / Semibold / 1.3','Card title','font-size:17px;font-weight:600')}
    ${type('body','17 / Regular / 1.4','Primary content sits here.','font-size:17px')}
    ${type('callout','16 / Regular / 1.4','Secondary content','font-size:16px;color:var(--text-secondary)')}
    ${type('subheadline','15 / Regular / 1.35','Supporting information','font-size:15px;color:var(--text-secondary)')}
    ${type('footnote','13 / Regular / 1.3','Timestamps and metadata','font-size:13px;color:var(--text-secondary)')}
    ${type('caption','12 / Regular / 1.25','Labels and badges','font-size:12px;color:var(--text-muted)')}
    ${type('micro','11 / Medium / 1.2','CHIP TEXT','font-size:11px;font-weight:500;color:var(--text-muted);letter-spacing:.06em')}
  </div>

  <p class="ds-label">Numbers</p>
  <div class="ds-demo">
    <div style="font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:19px;line-height:2">
      <div><span style="color:var(--accent)">&minus;110</span> &nbsp; <span style="color:var(--accent)">+240</span> &nbsp; <span style="color:var(--text-secondary)">O 9.5</span> &nbsp; <span style="color:var(--text-secondary)">&minus;3.5</span></div>
      <div style="color:var(--accent)">+$248.50</div>
      <div style="color:var(--danger)">&minus;$100.00</div>
    </div>
    <div class="ds-anno">American odds. Minus is a true minus sign (&amp;minus;), not a hyphen.</div>
  </div>
` },

/* ──────────────────────────────────────────── SURFACES & ELEVATION ── */
{ id: 'surfaces', label: 'Surfaces & Elevation', html: `
  <h1 class="ds-h1">Surfaces &amp; Elevation</h1>
  <p class="ds-intro">
    Three surface levels, and depth comes from colour rather than shadow. Each
    level is a step lighter than the one behind it, separated by a 1px border.
    Shadows are rare — reserved for a genuinely featured card, and always the
    accent glow rather than black.
  </p>

  <p class="ds-label">Elevation stack</p>
  <div class="ds-stack">
    <div class="ds-stack-l">background &middot; #0A0A12 — app ground, sheets</div>
    <div class="ds-stack-in">
      <div class="ds-stack-l">cardBackground &middot; #14141F + 1px border — cards, containers</div>
      <div class="ds-stack-in2">
        <div class="ds-stack-l" style="margin:0">elevatedBackground &middot; #1E1E2D — modals, popovers, inputs</div>
      </div>
    </div>
  </div>

  <p class="ds-label">Radius</p>
  <div class="ds-demo">
    ${radius('12','cornerRadiusSmall','buttons, chips, inner elements')}
    ${radius('16','cornerRadius','cards, modals, sheets')}
    ${radius('999','full','pills, avatars')}
  </div>
  <p class="ds-note">Never mix radii within one element. All four corners match, always.</p>

  <p class="ds-label">Shadow</p>
  <div class="ds-demo">
    <div class="ds-card">Standard card<div class="ds-anno">no shadow — the default</div></div>
    <div class="ds-card elev">Featured card<div class="ds-anno">accent glow, 15%, radius 12</div></div>
  </div>
` },

/* ───────────────────────────────────────────────────────── BUTTONS ── */
{ id: 'buttons', label: 'Buttons', html: `
  <h1 class="ds-h1">Buttons</h1>
  <p class="ds-intro">
    One primary action per screen. The gradient is reserved for it — a screen
    with two gradient buttons has no primary action. Secondary actions are
    outlined; destructive ones are outlined in red rather than filled, because a
    filled red button invites the click it is warning about.
  </p>

  <p class="ds-label">Variants</p>
  <div class="ds-demo">
    <button class="ds-btn-primary">Primary</button>
    <button class="ds-btn-flat">Flat accent</button>
    <button class="ds-btn-secondary">Secondary</button>
    <button class="ds-btn-danger">Delete account</button>
  </div>
  <p class="ds-note">
    Gradient (cyan → purple) for the main CTA; flat accent where a gradient would
    compete, such as inside a card that already carries emphasis.
  </p>

  <p class="ds-label">States</p>
  <div class="ds-demo">
    <button class="ds-btn-primary">Default</button>
    <button class="ds-btn-primary" disabled>Disabled</button>
    <button class="ds-btn-primary">Placing&hellip;</button>
  </div>
  <p class="ds-note">A loading button states the verb in progress — "Placing…", not a spinner alone.</p>
` },

/* ─────────────────────────────────────────────────── INPUTS & FORMS ── */
{ id: 'inputs', label: 'Inputs & Forms', html: `
  <h1 class="ds-h1">Inputs &amp; Forms</h1>
  <p class="ds-intro">
    Inputs sit on the background colour, not the card — an inset well rather than
    a raised control. Focus is the accent border, never a browser default outline.
    On iOS, currency entry uses the custom numeric keypad rather than the system
    keyboard, so amounts cannot contain nonsense.
  </p>

  <p class="ds-label">Text field</p>
  <div class="ds-demo col" style="max-width:420px">
    <div>
      <label class="ds-field-label">Email</label>
      <input class="ds-input" type="email" placeholder="member@example.com">
    </div>
    <div>
      <label class="ds-field-label">Credit limit</label>
      <input class="ds-input" value="1000" style="font-family:var(--mono);font-variant-numeric:tabular-nums">
    </div>
  </div>

  <p class="ds-label">Dark list / form rows</p>
  <div class="ds-list" style="max-width:460px">
    <div class="ds-row"><span>Manual pick acceptance</span><span class="ds-badge" style="background:rgba(0,245,212,.15);color:var(--accent)">On</span></div>
    <div class="ds-row"><span>Allow futures in Multi-Picks</span><span class="ds-badge" style="background:rgba(255,255,255,.06);color:var(--text-muted)">Off</span></div>
    <div class="ds-row"><span style="color:var(--danger)">Log Out</span></div>
  </div>
  <p class="ds-note">
    SwiftUI lists need <code class="t">.listRowBackground(Theme.cardBackground)</code> plus
    <code class="t">.scrollContentBackground(.hidden)</code>, or iOS paints its own grey behind them.
  </p>
` },

/* ────────────────────────────────────────────────── BADGES & CHIPS ── */
{ id: 'badges', label: 'Badges & Chips', html: `
  <h1 class="ds-h1">Badges &amp; Chips</h1>
  <p class="ds-intro">
    A badge states a fact about one record; a chip filters a list. Both are pills.
    Badge colour is semantic and comes from the status tokens — never picked to
    look good against the surrounding card.
  </p>

  <p class="ds-label">Event status</p>
  <div class="ds-demo">
    <span class="ds-badge" style="background:rgba(0,245,212,.15);color:var(--accent)">Live</span>
    <span class="ds-badge" style="background:rgba(123,104,238,.15);color:var(--scheduled)">Scheduled</span>
    <span class="ds-badge" style="background:rgba(92,92,111,.22);color:var(--final)">Final</span>
  </div>

  <p class="ds-label">Pick result</p>
  <div class="ds-demo">
    <span class="ds-badge" style="background:rgba(0,245,212,.15);color:var(--accent)">Won</span>
    <span class="ds-badge" style="background:rgba(255,107,107,.15);color:var(--danger)">Lost</span>
    <span class="ds-badge" style="background:rgba(168,168,184,.15);color:var(--text-secondary)">Push</span>
    <span class="ds-badge" style="background:rgba(255,169,77,.15);color:var(--warning)">Pending</span>
    <span class="ds-badge" style="background:rgba(255,255,255,.06);color:var(--text-muted)">Void</span>
  </div>

  <p class="ds-label">Attention tags</p>
  <p class="ds-note">Applied to members on the Members tab. Tappable, each with an explainer.</p>
  <div class="ds-demo">
    <span class="ds-tag">Picks Pending</span>
    <span class="ds-tag" style="color:var(--warning)">Overdue</span>
    <span class="ds-tag" style="color:var(--accent)">On Heater</span>
    <span class="ds-tag">Cold Streak</span>
    <span class="ds-tag" style="color:var(--gold)">Whale</span>
    <span class="ds-tag">Degen</span>
    <span class="ds-tag">Parlay Demon</span>
  </div>
` },

/* ────────────────────────────────────────────────────── ODDS & BET ── */
{ id: 'odds', label: 'Odds & Bet Slip', html: `
  <h1 class="ds-h1">Odds &amp; Bet Slip</h1>
  <p class="ds-intro">
    The odds button is the most-used control in the product. Unselected it is
    quiet — a dark well with the line above the price. Selected it inverts to
    solid accent, so a filled slip is readable at a glance without reading a word.
  </p>

  <p class="ds-label">Odds buttons</p>
  <div class="ds-demo">
    <div class="ds-odds"><span class="line">&minus;1.5</span><span class="price">(&minus;110)</span></div>
    <div class="ds-odds sel"><span class="line">+1.5</span><span class="price">(&minus;110)</span></div>
    <div class="ds-odds"><span class="price">&minus;140</span></div>
    <div class="ds-odds"><span class="line">O 9.5</span><span class="price">(&minus;115)</span></div>
    <div class="ds-odds" style="opacity:.45"><span class="price">&mdash;</span></div>
  </div>
  <p class="ds-note">
    Line in secondary, price in primary with parentheses. The dash state means no
    price is stored — expected beyond the 48h window, a fault inside it.
  </p>

  <p class="ds-label">Line change confirmation</p>
  <div class="ds-demo col" style="max-width:400px">
    <div style="background:rgba(255,176,32,.08);border:1px solid rgba(255,176,32,.35);border-radius:10px;padding:14px 16px">
      <div style="font-size:13px;font-weight:700;color:#FFB020;margin-bottom:4px">The line moved</div>
      <div style="font-size:12px;color:var(--text-secondary);margin-bottom:12px">The price changed before this was placed. Confirm to place at the new price.</div>
      <div style="display:flex;justify-content:space-between;font-size:12px;font-family:var(--mono);border-top:1px solid rgba(255,176,32,.18);padding-top:8px">
        <span>Orlando Magic +7</span>
        <span style="color:var(--text-secondary)"><s>&minus;110</s> &rarr; <strong style="color:var(--text-primary)">&minus;125</strong></span>
      </div>
    </div>
    <div class="ds-anno">Warning-coloured, not destructive — nothing failed, a decision is being asked for.</div>
  </div>
` },

/* ─────────────────────────────────────────────────────────── CARDS ── */
{ id: 'cards', label: 'Cards & Lists', html: `
  <h1 class="ds-h1">Cards &amp; Lists</h1>
  <p class="ds-intro">
    Cards use <code class="t">cardGradient</code> for depth — #14141F to #0E0E18, barely perceptible
    and never colourful. 1px border, 16 radius, 16 padding. A list is a card with
    rows divided by <code class="t">divider</code>, not a stack of separate cards.
  </p>

  <p class="ds-label">Pick card anatomy</p>
  <div class="ds-demo">
    <div class="ds-card" style="min-width:330px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">
        <span style="font-size:17px;font-weight:600">Orlando Magic +7</span>
        <span class="ds-badge" style="background:rgba(0,245,212,.15);color:var(--accent)">Won</span>
      </div>
      <div style="font-size:13px;color:var(--text-secondary)">Magic @ Timberwolves &middot; Final 119&ndash;92</div>
      <div style="display:flex;justify-content:space-between;margin-top:12px;font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:13px">
        <span style="color:var(--text-secondary)">$25.00 @ &minus;110</span>
        <span style="color:var(--accent)">+$22.73</span>
      </div>
    </div>
    <div style="max-width:250px">
      <div class="ds-anno">Title and status on one line — status right-aligned so a column of cards scans vertically.</div>
      <div class="ds-anno">Stake and return share a monospaced row; the figures line up between cards.</div>
    </div>
  </div>

  <p class="ds-label">List rows</p>
  <div class="ds-list" style="max-width:440px">
    <div class="ds-row"><div><div style="font-weight:600">Andrew Sandos</div><div style="font-size:12px;color:var(--text-secondary)">3 open picks</div></div><span style="font-family:var(--mono);color:var(--danger)">&minus;$180.00</span></div>
    <div class="ds-row"><div><div style="font-weight:600">Mike</div><div style="font-size:12px;color:var(--text-secondary)">Settled</div></div><span style="font-family:var(--mono);color:var(--text-muted)">$0.00</span></div>
    <div class="ds-row"><div><div style="font-weight:600">Joseph</div><div style="font-size:12px;color:var(--text-secondary)">1 open pick</div></div><span style="font-family:var(--mono);color:var(--accent)">+$45.00</span></div>
  </div>
` },

/* ───────────────────────────────────────────── DIALOG / TOAST ────── */
{ id: 'overlay', label: 'Dialogs & Toasts', html: `
  <h1 class="ds-h1">Dialogs &amp; Toasts</h1>
  <p class="ds-intro">
    A dialog interrupts and requires an answer; a toast reports something already
    finished and disappears. Anything irreversible gets a dialog naming the
    consequence, never a generic "Are you sure?".
  </p>

  <p class="ds-label">Dialog</p>
  <div class="ds-demo">
    <div style="background:var(--elevated);border:1px solid var(--border);border-radius:var(--radius);padding:22px;max-width:380px">
      <div style="font-size:19px;font-weight:600;margin-bottom:8px">Settle up with Andrew?</div>
      <div style="font-size:14px;color:var(--text-secondary);margin-bottom:18px">
        This clears their balance of &minus;$180.00 to zero and records a payment. It does not move any money.
      </div>
      <div style="display:flex;gap:10px">
        <button class="ds-btn-secondary" style="flex:1">Cancel</button>
        <button class="ds-btn-flat" style="flex:1">Settle up</button>
      </div>
    </div>
  </div>
  <p class="ds-note">The confirm button repeats the verb. "Settle up", never "OK".</p>

  <p class="ds-label">Toasts</p>
  <div class="ds-demo col" style="align-items:flex-start">
    <div class="ds-toast-demo">Pick placed</div>
    <div class="ds-toast-demo" style="border-left-color:var(--danger)">Couldn't place pick — try again</div>
    <div class="ds-toast-demo" style="border-left-color:var(--warning)">Invite expires in 2 days</div>
  </div>
` },

/* ────────────────────────────────────────────── SPACING & MOTION ─── */
{ id: 'spacing', label: 'Spacing & Motion', html: `
  <h1 class="ds-h1">Spacing &amp; Motion</h1>
  <p class="ds-intro">
    A 4pt grid with no exceptions. Motion shows causality — it explains where
    something came from — and never decorates. Springs are critically damped;
    nothing in Booki bounces.
  </p>

  <p class="ds-label">Spacing scale</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Value</th><th style="width:42%">Scale</th><th>Usage</th></tr></thead>
    <tbody>
      ${space('xxs',2,'Icon-to-text tight')}
      ${space('xs',4,'Inline elements')}
      ${space('sm',8,'Related items')}
      ${space('md',12,'Standard padding')}
      ${space('lg',16,'Section spacing, card inset')}
      ${space('xl',24,'Major sections')}
      ${space('xxl',32,'Screen margins')}
      ${space('xxxl',48,'Hero spacing')}
    </tbody>
  </table></div>

  <p class="ds-label">Motion</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Duration</th><th>Easing</th><th>Usage</th></tr></thead>
    <tbody>
      <tr><td><code class="t">instant</code></td><td>0.1s</td><td>ease-out</td><td>Taps, micro-interactions</td></tr>
      <tr><td><code class="t">fast</code></td><td>0.2s</td><td>ease-out</td><td>State changes, toggles</td></tr>
      <tr><td><code class="t">normal</code></td><td>0.3s</td><td>ease-in-out</td><td>Navigation, modals</td></tr>
      <tr><td><code class="t">slow</code></td><td>0.5s</td><td>ease-in-out</td><td>Complex transitions</td></tr>
    </tbody>
  </table></div>
  <p class="ds-note">Damping 0.7–0.8. Every animation honours reduce-motion.</p>
` },

/* ─────────────────────────────────────────────────── ANTI-PATTERNS ── */
{ id: 'dont', label: 'Anti-patterns', html: `
  <h1 class="ds-h1">Anti-patterns</h1>
  <p class="ds-intro">
    Each of these looks like an improvement in isolation and degrades the system
    in aggregate. They are listed because they have all been proposed at least once.
  </p>

  <p class="ds-label">Never</p>
  <ul class="ds-dont">
    <li>Gradient backgrounds on cards — solid, or <code class="t">cardGradient</code> for subtle depth</li>
    <li>Decorative shadows or coloured glows on anything not genuinely featured</li>
    <li>Animated gradients</li>
    <li>Colour for emphasis — use weight or size instead</li>
    <li>Busy backgrounds</li>
    <li>More than three font weights on one screen</li>
    <li>Bouncy animation — critically damped springs only</li>
    <li>Skeuomorphic elements</li>
    <li>Default iOS colours — always a Theme token</li>
    <li>Semantic colour used decoratively — red means loss, not "accent variety"</li>
  </ul>

  <p class="ds-label">Instead</p>
  <ul class="ds-do">
    <li>Elevate with surface colour, not shadow</li>
    <li>Emphasise with weight and size, not hue</li>
    <li>Let the accent be rare enough to mean something</li>
  </ul>
` },
];

/* helpers used by the templates above */
function swatch(name, hex, use) {
  return `<button class="ds-swatch" data-copy="${hex}">
    <div class="ds-chip" style="background:${hex}"></div>
    <div class="ds-tok">${name}</div>
    <div class="ds-hex">${hex}</div>
    <div class="ds-use">${use}</div>
  </button>`;
}
function type(token, spec, sample, style) {
  return `<div style="display:grid;grid-template-columns:170px 1fr;gap:22px;align-items:baseline;padding:12px 0;border-bottom:1px solid var(--divider)">
    <div style="font-family:var(--mono);font-size:11px;color:var(--text-muted)">
      <b style="display:block;color:var(--accent);font-weight:500">${token}</b>${spec}
    </div>
    <div style="${style}">${sample}</div>
  </div>`;
}
function radius(px, token, use) {
  const r = px === '999' ? '999px' : px + 'px';
  return `<div style="text-align:center">
    <div style="width:104px;height:64px;background:var(--elevated);border:1px solid var(--border);border-radius:${r}"></div>
    <div class="ds-anno"><b style="color:var(--accent)">${px}</b> ${token}<br>${use}</div>
  </div>`;
}
function space(token, px, use) {
  return `<tr><td><code class="t">${token}</code></td><td style="font-family:var(--mono)">${px}</td>
    <td><span class="ds-bar" style="width:${px}px"></span></td><td>${use}</td></tr>`;
}
