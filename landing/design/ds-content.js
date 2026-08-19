/**
 * Design system content — one entry per section.
 *
 * Markup here uses the component classes in ds.css. Inline style is permitted
 * in exactly one case: when the value IS the specimen (a swatch's colour, a
 * radius demo's radius, a spacing bar's width). Anything else — layout,
 * type, spacing — must be a class, or this page stops being an example of the
 * system it documents.
 */

const swatch = (name, hex, use) => `
  <button class="ds-swatch" data-copy="${hex}">
    <div class="ds-swatch__chip" style="background:${hex}"></div>
    <div class="ds-swatch__name">${name}</div>
    <div class="ds-swatch__hex">${hex}</div>
    <div class="ds-swatch__use">${use}</div>
  </button>`;

const gradient = (name, css, stops, use) => `
  <div class="ds-swatch ds-swatch--static">
    <div class="ds-swatch__chip" style="background:${css}"></div>
    <div class="ds-swatch__name">${name}</div>
    <div class="ds-swatch__hex">${stops}</div>
    <div class="ds-swatch__use">${use}</div>
  </div>`;

const spec = (token, meta, sample, cls) => `
  <div class="ds-spec">
    <div class="ds-spec__meta"><b>${token}</b>${meta}</div>
    <div class="${cls}">${sample}</div>
  </div>`;

const radiusDemo = (px, token, use) => `
  <div class="ds-center">
    <div class="ds-specimen" style="border-radius:${px === '999' ? '999px' : px + 'px'}"></div>
    <p class="ds-anno"><b>${px}</b> ${token}<br>${use}</p>
  </div>`;

const spaceRow = (token, px, use) => `
  <tr><td><code class="t">${token}</code></td><td class="ds-num">${px}</td>
  <td><span class="ds-bar" style="width:${px}px"></span></td><td>${use}</td></tr>`;

const DS_SECTIONS = [

{ id: 'brand', label: 'Brand Identity', html: `
  <h1 class="ds-h1">Brand Identity</h1>
  <p class="ds-intro">
    Booki is a dark product with one loud colour. The wordmark is the only
    decorative element in the system — everything else earns its place by
    carrying information. Slogan: <strong>Be The House</strong>, no full stop.
  </p>

  <p class="ds-label">Wordmark</p>
  <div class="ds-demo">
    <div class="ds-center">
      <div class="ds-callout ds-ground--dark">
        <img src="../assets/logo-booki-blk.svg" alt="Booki" class="ds-logo">
      </div>
      <p class="ds-anno">logo-booki-blk.svg &middot; primary, dark grounds</p>
    </div>
    <div class="ds-center">
      <div class="ds-callout ds-ground--light">
        <img src="../assets/logo-booki-wh.svg" alt="Booki" class="ds-logo">
      </div>
      <p class="ds-anno">logo-booki-wh.svg &middot; flat, light grounds</p>
    </div>
  </div>
  <p class="ds-note">
    Despite the name, <code class="t">blk</code> is the one used on dark — white letters with a
    #0A0A12 outline. <code class="t">wh</code> is a flat single-fill version. Reaching for the
    wrong one is the most common brand mistake in this codebase.
  </p>

  <p class="ds-label">Voice</p>
  <ul class="ds-rules">
    <li>Plain and specific. "Settle up", not "reconcile balances".</li>
    <li>Say what happened. "Pick placed", not "Success!".</li>
    <li>Compliance vocabulary everywhere user-facing: Organizer, Member, Pick, Stake, Multi-Pick.</li>
  </ul>
` },

{ id: 'colors', label: 'Colors', html: `
  <h1 class="ds-h1">Colors</h1>
  <p class="ds-intro">
    Electric cyan is the signature — actions, focus, wins. Semantic colours carry
    data meaning and are never decorative: cyan is a win, red is a loss, and
    neither is ever used to make something look nice. Click any swatch to copy it.
  </p>

  <p class="ds-label">Core surfaces</p>
  <div class="ds-grid">
    ${swatch('background', '#0A0A12', 'App background, sheets')}
    ${swatch('cardBackground', '#14141F', 'Cards, containers')}
    ${swatch('elevatedBackground', '#1E1E2D', 'Modals, popovers, inputs')}
    ${swatch('border', '#2A2A3A', 'Dividers, card edges')}
    ${swatch('divider', '#22222E', 'Subtle separation')}
  </div>

  <p class="ds-label">Text</p>
  <div class="ds-grid">
    ${swatch('textPrimary', '#F8F8F8', 'Headlines, primary content')}
    ${swatch('textSecondary', '#A8A8B8', 'Supporting text, labels')}
    ${swatch('textMuted', '#6B6B7B', 'Disabled, hints')}
  </div>

  <p class="ds-label">Accent</p>
  <div class="ds-grid">
    ${swatch('accent', '#00F5D4', 'Actions, links, focus, wins')}
    ${swatch('accentSecondary', '#9D4EDD', 'Gradients, secondary emphasis')}
    ${swatch('accentTertiary', '#FF006E', 'Highlights, special elements')}
    ${swatch('gold', '#FFE66D', 'Streaks, achievements')}
  </div>

  <p class="ds-label">Semantic &amp; status</p>
  <div class="ds-grid">
    ${swatch('danger', '#FF6B6B', 'Losses, destructive, errors')}
    ${swatch('warning', '#FFA94D', 'Pending, attention needed')}
    ${swatch('scheduled', '#7B68EE', 'Upcoming events')}
    ${swatch('finalStatus', '#5C5C6F', 'Completed events')}
  </div>

  <p class="ds-label">Tinted fills</p>
  <p class="ds-note">
    Every badge, well and callout uses one recipe — the semantic colour at 15%
    — rather than each picking its own opacity. One variable, <code class="t">--tint</code>,
    changes all of them together.
  </p>

  <p class="ds-label">Aliases</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Resolves to</th><th>Meaning</th></tr></thead>
    <tbody>
      <tr><td><code class="t">live</code></td><td>accent &middot; #00F5D4</td><td>In-progress</td></tr>
      <tr><td><code class="t">win</code></td><td>accent &middot; #00F5D4</td><td>Winning pick</td></tr>
      <tr><td><code class="t">loss</code></td><td>danger &middot; #FF6B6B</td><td>Losing pick</td></tr>
      <tr><td><code class="t">push</code></td><td>textSecondary &middot; #A8A8B8</td><td>Push / void</td></tr>
    </tbody>
  </table></div>
  <p class="ds-note">Same value, deliberately separate token — so a win can stop being cyan without dragging every button with it.</p>
` },

{ id: 'type', label: 'Typography', html: `
  <h1 class="ds-h1">Typography</h1>
  <p class="ds-intro">
    System font throughout — it renders numbers beautifully, and this product is
    mostly numbers. Three weights maximum on any one screen. Every figure uses
    monospaced digits so columns align and prices do not jitter as they change.
  </p>

  <p class="ds-label">Scale</p>
  <div class="ds-demo ds-demo--col">
    ${spec('display', '34 / Bold / 1.1', '$1,284.50', 'ds-num ds-h1')}
    ${spec('title1', '28 / Bold / 1.2', 'Screen title', 'ds-dialog__title')}
    ${spec('title2', '22 / Semibold / 1.25', 'Section header', 'ds-dialog__title')}
    ${spec('headline', '17 / Semibold / 1.3', 'Card title', 'ds-strong')}
    ${spec('body', '17 / Regular / 1.4', 'Primary content sits here.', 'ds-body')}
    ${spec('callout', '16 / Regular / 1.4', 'Secondary content', 'ds-sub')}
    ${spec('subheadline', '15 / Regular / 1.35', 'Supporting information', 'ds-sub')}
    ${spec('footnote', '13 / Regular / 1.3', 'Timestamps and metadata', 'ds-sub')}
    ${spec('caption', '12 / Regular / 1.25', 'Labels and badges', 'ds-dim')}
    ${spec('micro', '11 / Medium / 1.2', 'CHIP TEXT', 'ds-dim')}
  </div>

  <p class="ds-label">Numbers</p>
  <div class="ds-demo ds-demo--col ds-demo--start">
    <div class="ds-num ds-strong">
      <span class="ds-win">&minus;110</span> &nbsp; <span class="ds-win">+240</span> &nbsp;
      <span class="ds-sub">O 9.5</span> &nbsp; <span class="ds-sub">&minus;3.5</span>
    </div>
    <div class="ds-num ds-strong ds-win">+$248.50</div>
    <div class="ds-num ds-strong ds-lose">&minus;$100.00</div>
    <p class="ds-anno">American odds. Minus is a true minus sign, not a hyphen.</p>
  </div>
` },

{ id: 'surfaces', label: 'Surfaces & Elevation', html: `
  <h1 class="ds-h1">Surfaces &amp; Elevation</h1>
  <p class="ds-intro">
    Three surface levels, and depth comes from colour rather than shadow. Each
    level steps lighter than the one behind it, separated by a 1px border.
    Shadows are rare — reserved for a genuinely featured card, and always the
    accent glow rather than black.
  </p>

  <p class="ds-label">Elevation stack</p>
  <div class="ds-elev">
    <p class="ds-elev__cap">background &middot; #0A0A12 — app ground, sheets</p>
    <div class="ds-elev__l1">
      <p class="ds-elev__cap">cardBackground &middot; #14141F + 1px border — cards, containers</p>
      <div class="ds-elev__l2">
        <p class="ds-elev__cap">elevatedBackground &middot; #1E1E2D — modals, popovers, inputs</p>
      </div>
    </div>
  </div>

  <p class="ds-label">Radius</p>
  <div class="ds-demo">
    ${radiusDemo('12', 'cornerRadiusSmall', 'buttons, chips, inputs')}
    ${radiusDemo('16', 'cornerRadius', 'cards, modals, sheets')}
    ${radiusDemo('999', 'full', 'pills, avatars')}
  </div>
  <p class="ds-note">Two radii and a pill. Never mix them within one element — all four corners match.</p>

  <p class="ds-label">Shadow</p>
  <div class="ds-demo">
    <div class="ds-card"><span class="ds-strong">Standard card</span><p class="ds-anno">no shadow — the default</p></div>
    <div class="ds-card ds-card--elev"><span class="ds-strong">Featured card</span><p class="ds-anno">accent glow at 15%</p></div>
  </div>
` },

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
    <button class="ds-btn ds-btn--primary">Primary</button>
    <button class="ds-btn ds-btn--flat">Flat accent</button>
    <button class="ds-btn ds-btn--secondary">Secondary</button>
    <button class="ds-btn ds-btn--danger">Delete account</button>
  </div>
  <p class="ds-note">
    Gradient for the main CTA; flat accent where a gradient would compete, such
    as inside a card that already carries emphasis.
  </p>

  <p class="ds-label">States</p>
  <div class="ds-demo">
    <button class="ds-btn ds-btn--primary">Default</button>
    <button class="ds-btn ds-btn--primary" disabled>Disabled</button>
    <button class="ds-btn ds-btn--primary">Placing&hellip;</button>
  </div>
  <p class="ds-note">A loading button states the verb in progress — "Placing…", never a spinner alone.</p>
` },

{ id: 'inputs', label: 'Inputs & Forms', html: `
  <h1 class="ds-h1">Inputs &amp; Forms</h1>
  <p class="ds-intro">
    Inputs sit on the background colour rather than the card — an inset well, not
    a raised control. Focus is the accent border, never a browser default outline.
    On iOS, currency entry uses the custom numeric keypad so an amount cannot
    contain nonsense.
  </p>

  <p class="ds-label">Fields</p>
  <div class="ds-demo ds-demo--col ds-w-sm">
    <label class="ds-field">
      <span class="ds-field__label">Email</span>
      <input class="ds-input" type="email" placeholder="member@example.com">
    </label>
    <label class="ds-field">
      <span class="ds-field__label">Credit limit</span>
      <input class="ds-input ds-input--num" value="1000">
    </label>
  </div>

  <p class="ds-label">Form rows</p>
  <div class="ds-list ds-w-md">
    <div class="ds-row"><span class="ds-body">Manual pick acceptance</span><span class="ds-badge ds-badge--live">On</span></div>
    <div class="ds-row"><span class="ds-body">Allow futures in Multi-Picks</span><span class="ds-badge ds-badge--off">Off</span></div>
    <div class="ds-row"><span class="ds-body ds-lose">Log Out</span></div>
  </div>
  <p class="ds-note">
    SwiftUI lists need <code class="t">.listRowBackground(Theme.cardBackground)</code> and
    <code class="t">.scrollContentBackground(.hidden)</code>, or iOS paints its own grey behind them.
  </p>
` },

{ id: 'badges', label: 'Badges & Chips', html: `
  <h1 class="ds-h1">Badges &amp; Chips</h1>
  <p class="ds-intro">
    A badge states a fact about one record; a chip filters a list. Both are pills
    at the same size. Badge colour is semantic and comes from the status tokens —
    never chosen to look good against the surrounding card.
  </p>

  <p class="ds-label">Event status</p>
  <div class="ds-demo">
    <span class="ds-badge ds-badge--live">Live</span>
    <span class="ds-badge ds-badge--scheduled">Scheduled</span>
    <span class="ds-badge ds-badge--final">Final</span>
  </div>

  <p class="ds-label">Pick result</p>
  <div class="ds-demo">
    <span class="ds-badge ds-badge--won">Won</span>
    <span class="ds-badge ds-badge--lost">Lost</span>
    <span class="ds-badge ds-badge--push">Push</span>
    <span class="ds-badge ds-badge--pending">Pending</span>
    <span class="ds-badge ds-badge--off">Void</span>
  </div>

  <p class="ds-label">Attention tags</p>
  <div class="ds-demo">
    <span class="ds-tag">Picks Pending</span>
    <span class="ds-tag ds-tag--warn">Overdue</span>
    <span class="ds-tag ds-tag--hot">On Heater</span>
    <span class="ds-tag">Cold Streak</span>
    <span class="ds-tag ds-tag--gold">Whale</span>
    <span class="ds-tag">Degen</span>
    <span class="ds-tag">Parlay Demon</span>
  </div>
  <p class="ds-note">Applied to members on the Members tab. Each is tappable and opens an explainer.</p>
` },

{ id: 'odds', label: 'Odds & Bet Slip', html: `
  <h1 class="ds-h1">Odds &amp; Bet Slip</h1>
  <p class="ds-intro">
    The odds button is the most-used control in the product. Unselected it is
    quiet — a dark well with the line above the price. Selected it inverts to
    solid accent, so a filled slip is readable at a glance without reading a word.
  </p>

  <p class="ds-label">Odds buttons</p>
  <div class="ds-demo">
    <div class="ds-odds"><span class="ds-odds__line">&minus;1.5</span><span class="ds-odds__price">(&minus;110)</span></div>
    <div class="ds-odds ds-odds--sel"><span class="ds-odds__line">+1.5</span><span class="ds-odds__price">(&minus;110)</span></div>
    <div class="ds-odds"><span class="ds-odds__price">&minus;140</span></div>
    <div class="ds-odds"><span class="ds-odds__line">O 9.5</span><span class="ds-odds__price">(&minus;115)</span></div>
    <div class="ds-odds ds-odds--empty"><span class="ds-odds__price">&mdash;</span></div>
  </div>
  <p class="ds-note">
    Line in secondary, price in primary with parentheses. The dash means no price
    is stored — expected beyond the 48h window, a fault inside it.
  </p>

  <p class="ds-label">Line change confirmation</p>
  <div class="ds-demo ds-w-sm">
    <div class="ds-callout ds-callout--warn">
      <div class="ds-callout__title">The line moved</div>
      <div class="ds-sub">The price changed before this was placed. Confirm to place at the new price.</div>
      <div class="ds-callout__row">
        <span>Orlando Magic +7</span>
        <span><s>&minus;110</s> &rarr; <strong>&minus;125</strong></span>
      </div>
    </div>
  </div>
  <p class="ds-note">Warning-coloured, not destructive — nothing failed, a decision is being asked for.</p>
` },

{ id: 'cards', label: 'Cards & Lists', html: `
  <h1 class="ds-h1">Cards &amp; Lists</h1>
  <p class="ds-intro">
    Cards use <code class="t">cardGradient</code> for depth — #14141F to #0E0E18, barely
    perceptible and never colourful. 1px border, 16 radius, 16 padding. A list is
    one card with rows divided by <code class="t">divider</code>, not a stack of separate cards.
  </p>

  <p class="ds-label">Pick card anatomy</p>
  <div class="ds-demo">
    <div class="ds-card">
      <div class="ds-card__head">
        <span class="ds-strong">Orlando Magic +7</span>
        <span class="ds-badge ds-badge--won">Won</span>
      </div>
      <div class="ds-sub">Magic @ Timberwolves &middot; Final 119&ndash;92</div>
      <div class="ds-card__foot ds-num">
        <span class="ds-sub">$25.00 @ &minus;110</span>
        <span class="ds-win">+$22.73</span>
      </div>
    </div>
    <div class="ds-stack ds-w-sm">
      <p class="ds-anno">Title and status share one line, status right-aligned, so a column of cards scans vertically.</p>
      <p class="ds-anno">Stake and return share a monospaced row — the figures line up between cards.</p>
    </div>
  </div>

  <p class="ds-label">List rows</p>
  <div class="ds-list ds-w-md">
    <div class="ds-row">
      <div><div class="ds-body">Andrew Sandos</div><div class="ds-dim">3 open picks</div></div>
      <span class="ds-num ds-lose">&minus;$180.00</span>
    </div>
    <div class="ds-row">
      <div><div class="ds-body">Mike</div><div class="ds-dim">Settled</div></div>
      <span class="ds-num ds-flat">$0.00</span>
    </div>
    <div class="ds-row">
      <div><div class="ds-body">Joseph</div><div class="ds-dim">1 open pick</div></div>
      <span class="ds-num ds-win">+$45.00</span>
    </div>
  </div>
` },

{ id: 'overlay', label: 'Dialogs & Toasts', html: `
  <h1 class="ds-h1">Dialogs &amp; Toasts</h1>
  <p class="ds-intro">
    A dialog interrupts and requires an answer; a toast reports something already
    finished and disappears. Anything irreversible gets a dialog naming the
    consequence — never a generic "Are you sure?".
  </p>

  <p class="ds-label">Dialog</p>
  <div class="ds-demo">
    <div class="ds-dialog">
      <div class="ds-dialog__title">Settle up with Andrew?</div>
      <div class="ds-dialog__body">
        This clears their balance of &minus;$180.00 to zero and records a payment.
        It does not move any money.
      </div>
      <div class="ds-dialog__actions">
        <button class="ds-btn ds-btn--secondary ds-btn--grow">Cancel</button>
        <button class="ds-btn ds-btn--flat ds-btn--grow">Settle up</button>
      </div>
    </div>
  </div>
  <p class="ds-note">The confirm button repeats the verb. "Settle up", never "OK".</p>

  <p class="ds-label">Toasts</p>
  <div class="ds-demo ds-demo--col ds-demo--start ds-w-sm">
    <div class="ds-callout ds-callout--accent">Pick placed</div>
    <div class="ds-callout ds-callout--danger">Couldn't place pick — try again</div>
    <div class="ds-callout ds-callout--warn">Invite expires in 2 days</div>
  </div>
` },

{ id: 'spacing', label: 'Spacing & Motion', html: `
  <h1 class="ds-h1">Spacing &amp; Motion</h1>
  <p class="ds-intro">
    A 4pt grid with no exceptions — this page included. Motion shows causality:
    it explains where something came from, and never decorates. Springs are
    critically damped; nothing in Booki bounces.
  </p>

  <p class="ds-label">Spacing scale</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Value</th><th class="ds-col-scale">Scale</th><th>Usage</th></tr></thead>
    <tbody>
      ${spaceRow('xxs', 2, 'Icon-to-text tight')}
      ${spaceRow('xs', 4, 'Inline elements')}
      ${spaceRow('sm', 8, 'Related items')}
      ${spaceRow('md', 12, 'Standard padding')}
      ${spaceRow('lg', 16, 'Section spacing, card inset')}
      ${spaceRow('xl', 24, 'Major sections')}
      ${spaceRow('xxl', 32, 'Screen margins')}
      ${spaceRow('xxxl', 48, 'Hero spacing')}
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

  <p class="ds-label">Gradients</p>
  <div class="ds-grid">
    ${gradient('buttonGradient', 'linear-gradient(135deg,#00F5D4,#9D4EDD)', '#00F5D4 → #9D4EDD', 'Primary CTAs')}
    ${gradient('rainbowGradient', 'linear-gradient(135deg,#00F5D4,#9D4EDD,#FF006E)', '#00F5D4 → #9D4EDD → #FF006E', 'Special / featured')}
    ${gradient('goldGradient', 'linear-gradient(135deg,#FFE66D,#FFAA00)', '#FFE66D → #FFAA00', 'Achievements')}
    ${gradient('cardGradient', 'linear-gradient(180deg,#14141F,#0E0E18)', '#14141F → #0E0E18', 'Subtle card depth')}
  </div>
  <p class="ds-note">Gradients on primary buttons only. Cards stay solid — cardGradient is depth, never colour.</p>
` },

{ id: 'dont', label: 'Anti-patterns', html: `
  <h1 class="ds-h1">Anti-patterns</h1>
  <p class="ds-intro">
    Each of these looks like an improvement in isolation and degrades the system
    in aggregate. They are listed because they have all been proposed at least once.
  </p>

  <p class="ds-label">Never</p>
  <ul class="ds-rules ds-rules--dont">
    <li>Gradient backgrounds on cards — solid, or <code class="t">cardGradient</code> for depth</li>
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
  <ul class="ds-rules">
    <li>Elevate with surface colour, not shadow</li>
    <li>Emphasise with weight and size, not hue</li>
    <li>Keep the accent rare enough that it means something</li>
  </ul>
` },
];
