/**
 * Design system content — one entry per section.
 *
 * Markup here uses the component classes in ds.css. Inline style is permitted
 * in exactly one case: when the value IS the specimen (a swatch's colour, a
 * radius demo's radius, a spacing bar's width). Anything else — layout,
 * type, spacing — must be a class, or this page stops being an example of the
 * system it documents.
 */

// The chip paints from the token and the hex label is filled in at runtime by
// ds.js reading the resolved value. Writing the hex here would make this page a
// third copy of the palette, free to disagree with landing/tokens.css the
// moment a colour changes — which is the exact failure this architecture removes.
const swatch = (name, token, use) => `
  <button class="ds-swatch" data-token="${token}">
    <div class="ds-swatch__chip" style="background:var(${token})"></div>
    <div class="ds-swatch__name">${name}</div>
    <div class="ds-swatch__hex"></div>
    <div class="ds-swatch__use">${use}</div>
  </button>`;

// Paints from the gradient token; ds.js reads the resolved stops back out of
// the computed value for the label. Writing the hexes here made this block a
// third copy of the palette — free to keep showing an old colour forever.
const gradient = (name, token, use) => `
  <div class="ds-swatch ds-swatch--static">
    <div class="ds-swatch__chip" style="background:var(${token})"></div>
    <div class="ds-swatch__name">${name}</div>
    <div class="ds-swatch__hex" data-gradient="${token}"></div>
    <div class="ds-swatch__use">${use}</div>
  </div>`;


const btnRow = (variant, name, use) => {
  const cell = (mod) => `<td><button class="ds-btn ds-btn--${variant}${mod}">Call to Action</button></td>`;
  return `<tr>
    <td><div class="ds-matrix__name">${name}</div><div class="ds-matrix__use">${use}</div></td>
    ${cell('')}${cell(' is-hover')}${cell(' is-pressed')}
    <td><button class="ds-btn ds-btn--${variant}" disabled>Call to Action</button></td>
  </tr>`;
};

const toast = (variant, glyph, title, text) => `
  <div class="ds-toastbox ds-toastbox--${variant}">
    <span class="ds-toastbox__icon">${glyph}</span>
    <span class="ds-toastbox__body">
      <span class="ds-toastbox__title">${title}</span>
      <span class="ds-toastbox__text">${text}</span>
    </span>
    <button class="ds-toastbox__x" aria-label="Dismiss">&times;</button>
  </div>`;

const alertBox = (variant, glyph, title, text) => `
  <div class="ds-toastbox ds-alert ds-toastbox--${variant}">
    <span class="ds-toastbox__icon">${glyph}</span>
    <span class="ds-toastbox__body">
      <span class="ds-toastbox__title">${title}</span>
      <span class="ds-toastbox__text">${text}</span>
    </span>
  </div>`;

const icon = (glyph, name) => `
  <div class="ds-icon"><div class="ds-icon__glyph">${glyph}</div><div class="ds-icon__name">${name}</div></div>`;

const barRow = (label, pct, value, neg) => `
  <div class="ds-bars__row">
    <span class="ds-sub">${label}</span>
    <span class="ds-bars__track"><span class="ds-bars__fill${neg ? ' ds-bars__fill--neg' : ''}" style="width:${pct}%"></span></span>
    <span class="ds-bars__val ${neg ? 'ds-lose' : 'ds-win'}">${value}</span>
  </div>`;

const spec = (token, meta, sample, cls) => `
  <div class="ds-spec">
    <div class="ds-spec__meta"><b>${token}</b>${meta}</div>
    <div class="${cls}">${sample}</div>
  </div>`;

// Paints from the token and labels itself from the resolved value, filled in by
// ds.js — writing the px here would make this page disagree with tokens.css the
// moment a radius changes.
const radiusDemo = (token, use) => `
  <div class="ds-center">
    <div class="ds-specimen" style="border-radius:var(${token})"></div>
    <p class="ds-anno"><b data-radius="${token}"></b> ${token}<br>${use}</p>
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
        <img src="../assets/logo-booki.svg" alt="Booki" class="ds-logo">
      </div>
      <p class="ds-anno">logo-booki.svg<br>primary &middot; dark grounds</p>
    </div>
    <div class="ds-center">
      <div class="ds-callout ds-ground--light">
        <img src="../assets/logo-booki-blk.svg" alt="Booki" class="ds-logo">
      </div>
      <p class="ds-anno">logo-booki-blk.svg<br>light and white grounds</p>
    </div>
    <div class="ds-center">
      <div class="ds-callout ds-ground--dark">
        <img src="../assets/logo-booki-wh.svg" alt="Booki" class="ds-logo">
      </div>
      <p class="ds-anno">logo-booki-wh.svg<br>flat white &middot; dark grounds only</p>
    </div>
  </div>
  <p class="ds-note">
    The mark is a sticker: letterforms with a hard offset behind them. That is why
    <code class="t">blk</code> reads as dark on white — you are seeing the offset, not the
    fill — and it is the variant for light grounds. <code class="t">logo-booki.svg</code>
    carries the cyan offset and is the primary mark on dark.
    <code class="t">wh</code> is flat white with no offset: it is
    <strong>invisible on white</strong> and belongs only on dark.
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
    ${swatch('background', '--background', 'App background, sheets')}
    ${swatch('cardBackground', '--card', 'Cards, containers')}
    ${swatch('elevatedBackground', '--elevated', 'Modals, popovers, inputs')}
    ${swatch('border', '--border', 'Dividers, card edges')}
    ${swatch('divider', '--divider', 'Subtle separation')}
  </div>

  <p class="ds-label">Text</p>
  <div class="ds-grid">
    ${swatch('textPrimary', '--text-primary', 'Headlines, primary content')}
    ${swatch('textSecondary', '--text-secondary', 'Supporting text, labels')}
    ${swatch('textMuted', '--text-muted', 'Disabled, hints')}
  </div>

  <p class="ds-label">Accent</p>
  <div class="ds-grid">
    ${swatch('accent', '--accent', 'Actions, links, focus, wins')}
    ${swatch('accentSecondary', '--accent-secondary', 'Gradients, secondary emphasis')}
    ${swatch('accentTertiary', '--accent-tertiary', 'Highlights, special elements')}
    ${swatch('gold', '--gold', 'Streaks, achievements')}
  </div>

  <p class="ds-label">Semantic &amp; status</p>
  <div class="ds-grid">
    ${swatch('danger', '--danger', 'Losses, destructive, errors')}
    ${swatch('warning', '--warning', 'Pending, attention needed')}
    ${swatch('scheduled', '--scheduled', 'Upcoming events')}
    ${swatch('finalStatus', '--final', 'Completed events')}
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

  <p class="ds-label">Web roles</p>
  <p class="ds-anno" style="margin-bottom:var(--s4)">
    The scale above is the iOS scale — Apple text styles, 17px body. The web
    dashboard is a denser desktop UI whose body size is 13px, so it carries its
    own 9-step scale. Colour, spacing and radius are shared with iOS; type sizes
    deliberately are not. These are the role classes in
    <code>landing/dashboard/dashboard.css</code> — reach for one before writing
    a new component-scoped type style.
  </p>
  <div class="ds-demo ds-demo--col ds-demo--start">
    ${spec('.t-title', '18 / Bold / primary', 'Section heading', 'ds-w-title')}
    ${spec('.t-body-strong', '14 / Semibold / primary', 'Row title', 'ds-w-bodystrong')}
    ${spec('.t-strong', '13 / Semibold / primary', 'Compact row title', 'ds-w-strong')}
    ${spec('.t-body', '13 / Regular / secondary', 'Supporting copy sits here.', 'ds-w-body')}
    ${spec('.t-body-muted', '13 / Regular / muted', 'De-emphasised detail', 'ds-w-bodymuted')}
    ${spec('.t-caption', '12 / Regular / muted', 'Timestamps and metadata', 'ds-w-caption')}
    ${spec('.t-label', '12 / Regular / muted / upper', 'SECTION LABEL', 'ds-w-label')}
    ${spec('.t-micro', '11 / Regular', 'Chip text', 'ds-w-micro')}
    ${spec('.t-micro-muted', '11 / Regular / muted', 'Fine print', 'ds-w-micromuted')}
  </div>
  <p class="ds-anno">
    These replaced 142 repeated inline style strings and sit alongside 31
    component-scoped type classes that predate them. The component-scoped ones
    are largely the same nine roles under different names — fold them in when
    you next touch the component rather than adding a tenth.
  </p>
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
    ${radiusDemo('--radius-xs', 'tags, the smallest chips')}
    ${radiusDemo('--radius-sm', 'anything inside a rounded container')}
    ${radiusDemo('--radius', 'the container itself')}
    ${radiusDemo('--radius-full', 'pills, avatars')}
  </div>
  <p class="ds-note">
    <b>Radius is chosen by nesting depth, not by element type.</b> The outer
    container — card, panel, sheet — takes <code class="t">--radius</code>.
    Anything rounded sitting inside it steps down to
    <code class="t">--radius-sm</code>. A child that repeats its parent&rsquo;s
    radius reads as though its corner bulges outward, because the gap between
    the two arcs is narrowest exactly at the corner; stepping down keeps the
    curves concentric.
  </p>
  <p class="ds-note">
    <b>There is no exemption for controls.</b> A search input, a nav link or a
    button that is the outermost rounded element takes
    <code class="t">--radius</code>, exactly like a card does &mdash; radius
    follows position in the tree, not what kind of thing an element is. The same
    button takes <code class="t">--radius-sm</code> once it sits inside a card.
    Never mix radii within one element: all four corners match.
  </p>
  <p class="ds-note">
    A CSS class is not contextual, so a component whose own rule sets
    <code class="t">--radius-sm</code> because it usually sits inside a card
    needs <code class="t">.r-outer</code> when it stands alone.
  </p>
  <p class="ds-note">
    <code class="t">--radius-full</code> (999px) and 50% are not
    interchangeable. On a non-square element 999px gives a stadium and 50% gives
    an ellipse &mdash; hence the separate
    <code class="t">--radius-circle</code>.
  </p>

  <p class="ds-label">Shadow</p>
  <div class="ds-demo">
    <div class="ds-card"><span class="ds-strong">Standard card</span><p class="ds-anno">no shadow — the default</p></div>
    <div class="ds-card ds-card--elev"><span class="ds-strong">Featured card</span><p class="ds-anno">accent glow at 15%</p></div>
  </div>
` },

{ id: 'buttons', label: 'Buttons', html: `
  <h1 class="ds-h1">Buttons</h1>
  <p class="ds-intro">
    One primary action per screen. The gradient is reserved for it — a screen with
    two gradient buttons has no primary action. Everything else is progressively
    quieter, and the quietest variants exist so that a screen can offer several
    actions without any of them competing.
  </p>
  <p class="ds-note">
    <b>Buttons are set in Space Grotesk, 700, all caps, tracked 0.1em.</b> The
    same face as headings and figures, so an action reads as part of the
    product&rsquo;s voice rather than as interface furniture. Capitals were drawn
    with more room around them than lowercase and crowd when set solid; at this
    weight the 0.1em is what keeps them legible rather than decorative. Size
    steps down to 14px because caps have no descenders and read larger &mdash;
    the drop keeps the optical mass of the 16px sentence case it replaces.
  </p>
  <p class="ds-note">
    This is for <b>actions</b>. Odds buttons are data
    (<code class="t">+1.5 (&minus;167)</code>) and filter or toggle chips are
    navigation &mdash; both keep sentence case and Inter. Capitalising a number
    changes nothing and tracking one makes it harder to read.
  </p>

  <p class="ds-label">Variants &times; states</p>
  <div class="ds-demo ds-demo--flush">
    <div class="ds-scroll"><table class="ds-matrix">
      <thead><tr><th>Variant</th><th>Default</th><th>Hover</th><th>Pressed</th><th>Disabled</th></tr></thead>
      <tbody>
        ${btnRow('primary', 'primary', 'the one main action')}
        ${btnRow('accent', 'accent', 'inside a card that already carries emphasis')}
        ${btnRow('secondary', 'secondary', 'the alternative in a pair')}
        ${btnRow('ghost', 'ghost', 'toolbar and row actions')}
        ${btnRow('link', 'link', 'inline in prose')}
        ${btnRow('destructive', 'destructive', 'confirmed deletion')}
        ${btnRow('quiet', 'quiet destructive', 'an exit that is not the point of the screen')}
      </tbody>
    </table></div>
  </div>
  <p class="ds-note">
    Filled variants shift brightness on hover and press; transparent ones gain a
    fill. Pressed additionally displaces 1px — Booki uses no shadows, so
    brightness alone does not read as a press. Two treatments across seven
    variants, so a new variant inherits an obvious state behaviour rather than
    inventing one.
  </p>

  <p class="ds-label">Sizes</p>
  <div class="ds-demo">
    <button class="ds-btn ds-btn--accent ds-btn--sm">Small</button>
    <button class="ds-btn ds-btn--accent">Default</button>
    <button class="ds-btn ds-btn--accent ds-btn--lg">Large</button>
    <button class="ds-btn ds-btn--accent ds-btn--icon" aria-label="Settings">&#9881;</button>
    <button class="ds-btn ds-btn--secondary ds-btn--icon ds-btn--sm" aria-label="Copy">&#9112;</button>
  </div>
  <p class="ds-note">
    Height is the only dimension that changes — 32, 48 and 56. Padding and type
    follow it. The spec says 50pt; 48 is used so the control stays on the 4pt grid.
  </p>

  <p class="ds-label">Full width</p>
  <div class="ds-demo ds-demo--col ds-w-sm">
    <button class="ds-btn ds-btn--primary ds-btn--block">Place 3 Picks &middot; $75.00</button>
    <div class="ds-dialog__actions">
      <button class="ds-btn ds-btn--secondary ds-btn--grow">Cancel</button>
      <button class="ds-btn ds-btn--accent ds-btn--grow">Settle up</button>
    </div>
  </div>
  <p class="ds-note">
    Sheets and bet slips use full width. A pair splits the row evenly with the
    confirming action on the right, matching the platform convention.
  </p>

  <p class="ds-label">Rules</p>
  <ul class="ds-rules">
    <li>One gradient button per screen. If two are needed, one of them is not primary.</li>
    <li>The label is the verb that happens. "Settle up", never "OK" or "Submit".</li>
    <li>A working button states the verb in progress — "Placing&hellip;" — never a bare spinner.</li>
    <li>Destructive is filled only behind a confirmation. The quiet variant is for the entry point.</li>
    <li>Disabled is 40% opacity and keeps its shape, so the layout does not move when it enables.</li>
  </ul>
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
    A badge states a fact about one record; a tag describes a pattern across
    several. Both are pills, but they are deliberately not interchangeable: a
    badge is uppercase monospace, because it labels a state machine value, and a
    tag is sentence-case sans, because it is a human judgement. Badge colour is
    semantic and comes from the status tokens — never chosen to look good
    against the surrounding card.
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
   <div class="ds-odds-row">
    <div class="ds-odds"><span class="ds-odds__line">&minus;1.5</span><span class="ds-odds__price">(&minus;110)</span></div>
    <div class="ds-odds ds-odds--sel"><span class="ds-odds__line">+1.5</span><span class="ds-odds__price">(&minus;110)</span></div>
    <div class="ds-odds"><span class="ds-odds__price">&minus;140</span></div>
    <div class="ds-odds"><span class="ds-odds__line">O 9.5</span><span class="ds-odds__price">(&minus;115)</span></div>
    <div class="ds-odds ds-odds--empty"><span class="ds-odds__price">&mdash;</span></div>
   </div>
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
  <div class="ds-demo ds-demo--top">
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
  <h1 class="ds-h1">Dialogs, Toasts &amp; Alerts</h1>
  <p class="ds-intro">
    A dialog interrupts and needs an answer. A toast reports something already
    finished and leaves. An alert belongs to the content around it and stays.
    Anything irreversible gets a dialog naming the consequence — never a generic
    "Are you sure?".
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
        <button class="ds-btn ds-btn--accent ds-btn--grow">Settle up</button>
      </div>
    </div>
  </div>
  <p class="ds-note">The confirm button repeats the verb. "Settle up", never "OK".</p>

  <p class="ds-label">Toasts</p>
  <div class="ds-demo ds-demo--col ds-demo--start">
    ${toast('success', '&check;', 'Pick placed', '$25.00 on Magic +7 at &minus;110.')}
    ${toast('info', 'i', 'Code copied', 'SNW92TQR is on your clipboard.')}
    ${toast('warn', '!', 'Invite expiring', 'Andrew&rsquo;s invite expires in 2 days.')}
    ${toast('error', '&times;', 'Couldn&rsquo;t place pick', 'The line moved. Try again.')}
  </div>
  <p class="ds-note">
    <strong>Every toast is the same width</strong> — 360px, regardless of message
    length. Toasts stack in a corner, and variable widths read as debris rather
    than as a system. Long text wraps; the box does not grow.
  </p>

  <p class="ds-label">Alerts</p>
  <div class="ds-demo ds-demo--col ds-demo--start">
    ${alertBox('info', 'i', 'Lines open 48 hours out', 'Games further away are listed without prices.')}
    ${alertBox('warn', '!', 'Approaching member limit', 'You have 3 of 3 members on the free plan.')}
    ${alertBox('error', '!', 'Sync failed', 'Couldn&rsquo;t reach the odds provider. Prices may be stale.')}
  </div>
  <p class="ds-note">
    An alert takes the full width of its container, because it belongs to the
    content it interrupts. It has no dismiss — it goes away when the condition does.
  </p>

  <p class="ds-label">Which to use</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th></th><th>Toast</th><th>Alert</th><th>Dialog</th></tr></thead>
    <tbody>
      <tr><td>Interrupts</td><td>No</td><td>No</td><td>Yes</td></tr>
      <tr><td>Dismisses itself</td><td>Yes</td><td>No</td><td>No</td></tr>
      <tr><td>Needs an answer</td><td>No</td><td>No</td><td>Yes</td></tr>
      <tr><td>Width</td><td>Fixed 360</td><td>Container</td><td>Max 400</td></tr>
      <tr><td>Use for</td><td>It happened</td><td>It is true right now</td><td>Decide before continuing</td></tr>
    </tbody>
  </table></div>
` },

{ id: 'icons', label: 'Icons', html: `
  <h1 class="ds-h1">Icons</h1>
  <p class="ds-intro">
    SF Symbols throughout — no custom icon set, no second family. An icon labels
    a thing that recurs; it never decorates, and it never replaces a word the
    user would have to guess at.
  </p>

  <p class="ds-label">Sports</p>
  <div class="ds-icons">
    ${icon('&#127936;', 'basketball.fill')}
    ${icon('&#127944;', 'football.fill')}
    ${icon('&#9917;', 'soccerball')}
    ${icon('&#9918;', 'baseball.diamond.bases')}
    ${icon('&#127954;', 'hockey.puck.fill')}
    ${icon('&#129354;', 'figure.martial.arts')}
    ${icon('&#127934;', 'tennisball.fill')}
    ${icon('&#9971;', 'figure.golf')}
    ${icon('&#127967;', 'sportscourt.fill')}
  </div>

  <p class="ds-label">Interface</p>
  <div class="ds-icons">
    ${icon('&#128202;', 'chart.bar.fill')}
    ${icon('&#128100;', 'person.fill')}
    ${icon('&#9881;', 'gearshape.fill')}
    ${icon('&#127915;', 'ticket.fill')}
    ${icon('&#128274;', 'lock.fill')}
    ${icon('&#9888;', 'exclamationmark.triangle')}
    ${icon('&#10003;', 'checkmark.circle.fill')}
    ${icon('&#10005;', 'xmark.circle.fill')}
    ${icon('&#9003;', 'delete.left')}
    ${icon('&#8250;', 'chevron.right')}
    ${icon('&#8249;', 'chevron.left')}
    ${icon('&#128269;', 'magnifyingglass')}
    ${icon('&#9733;', 'star.fill')}
    ${icon('&#128273;', 'person.badge.key')}
    ${icon('&#8593;', 'square.and.arrow.up')}
  </div>

  <p class="ds-note">
    Glyphs above are stand-ins for the SF Symbol named beneath them — this page
    is HTML and cannot render SF Symbols. The name is the contract; use it
    verbatim in Swift.
  </p>

  <ul class="ds-rules">
    <li>Filled variants for selected and active states, outline for the rest.</li>
    <li>An icon alone is only acceptable where the meaning is unambiguous — a chevron, a close, a search.</li>
    <li>Icons inherit the text colour of their row. They are not separately coloured.</li>
  </ul>
` },

{ id: 'nav', label: 'Tabs & Navigation', html: `
  <h1 class="ds-h1">Tabs &amp; Navigation</h1>
  <p class="ds-intro">
    Three levels, and they are not interchangeable. The tab bar switches the
    whole context. Underline tabs move between peer views inside one context. A
    segmented control filters what is already on screen.
  </p>

  <p class="ds-label">Tab bar &mdash; switches context</p>
  <div class="ds-demo ds-demo--flush ds-w-md">
    <div>
      <div class="ds-tabbar">
        <div class="ds-tabbar__item is-active">Dashboard</div>
        <div class="ds-tabbar__item">Events</div>
        <div class="ds-tabbar__item">Picks<span class="ds-tabbar__badge">3</span></div>
        <div class="ds-tabbar__item">Members</div>
      </div>
    </div>
  </div>
  <p class="ds-note">All-caps labels, accent for the active item, and a count badge only where something is waiting on the organizer.</p>

  <p class="ds-label">Underline tabs &mdash; peer views</p>
  <div class="ds-demo ds-demo--flush">
    <div class="ds-tabs">
      <button class="ds-tab is-active">NFL</button>
      <button class="ds-tab">NCAAF</button>
      <button class="ds-tab">Futures</button>
    </div>
  </div>

  <p class="ds-label">Segmented &mdash; filters the current view</p>
  <div class="ds-demo">
    <div class="ds-seg">
      <button class="ds-seg__item is-active">Open</button>
      <button class="ds-seg__item">Past</button>
    </div>
    <div class="ds-seg">
      <button class="ds-seg__item is-active">All</button>
      <button class="ds-seg__item">Singles</button>
      <button class="ds-seg__item">Multi-Pick</button>
      <button class="ds-seg__item">Futures</button>
    </div>
  </div>
  <p class="ds-note">A segmented control never navigates. If choosing an option changes the screen, it should have been tabs.</p>
` },

{ id: 'states', label: 'Empty & Loading', html: `
  <h1 class="ds-h1">Empty &amp; Loading</h1>
  <p class="ds-intro">
    The two states a screen spends most of its early life in, and the two most
    often left to chance. An empty state says what would be here and how to get
    it. A loading state holds the shape of what is coming, so nothing jumps when
    it arrives.
  </p>

  <p class="ds-label">Empty &mdash; first run</p>
  <div class="ds-demo ds-demo--flush ds-w-md">
    <div class="ds-list">
      <div class="ds-empty">
        <div class="ds-empty__glyph">&#128100;</div>
        <div class="ds-empty__title">No members yet</div>
        <div class="ds-empty__text">Invite someone and they will appear here with their balance and open picks.</div>
        <div style="margin-top:var(--s4)"><button class="ds-btn ds-btn--accent ds-btn--sm">Invite your first member</button></div>
      </div>
    </div>
  </div>

  <p class="ds-label">Empty &mdash; filtered to nothing</p>
  <div class="ds-demo ds-demo--flush ds-w-md">
    <div class="ds-list">
      <div class="ds-empty">
        <div class="ds-empty__glyph">&#128269;</div>
        <div class="ds-empty__title">No picks match</div>
        <div class="ds-empty__text">Try a different filter, or clear it to see everything.</div>
      </div>
    </div>
  </div>
  <p class="ds-note">
    These are different states and must read differently. "Nothing here yet"
    invites an action; "nothing matches" invites undoing a filter. Showing the
    first-run copy to someone with an active filter is the common mistake.
  </p>

  <p class="ds-label">Loading &mdash; skeletons</p>
  <div class="ds-demo ds-demo--flush ds-w-md">
    <div class="ds-list">
      <div class="ds-row">
        <div style="flex:1">
          <div class="ds-skel ds-skel--title" style="width:45%"></div>
          <div class="ds-skel ds-skel--line" style="width:28%;margin-top:var(--s2)"></div>
        </div>
        <div class="ds-skel ds-skel--line" style="width:64px"></div>
      </div>
      <div class="ds-row">
        <div style="flex:1">
          <div class="ds-skel ds-skel--title" style="width:36%"></div>
          <div class="ds-skel ds-skel--line" style="width:22%;margin-top:var(--s2)"></div>
        </div>
        <div class="ds-skel ds-skel--line" style="width:64px"></div>
      </div>
    </div>
  </div>
  <p class="ds-note">
    A skeleton mirrors the row it replaces — same height, same rhythm — so
    content does not shift when it lands. Never a spinner where the shape is
    known. Skeletons are skipped entirely when local data is already cached.
  </p>
` },

{ id: 'menus', label: 'Menus & Tables', html: `
  <h1 class="ds-h1">Menus &amp; Tables</h1>
  <p class="ds-intro">
    A menu holds actions that would clutter the surface. A table is for data
    dense enough that alignment matters more than shape — on mobile the same
    data becomes rows.
  </p>

  <p class="ds-label">Overflow menu</p>
  <div class="ds-demo ds-demo--start">
    <div class="ds-menu">
      <div class="ds-menu__item">Edit credit limit</div>
      <div class="ds-menu__item">Edit win limit</div>
      <div class="ds-menu__item">Settle up</div>
      <div class="ds-menu__sep"></div>
      <div class="ds-menu__item">Archive member</div>
      <div class="ds-menu__item ds-menu__item--danger">Remove from group</div>
    </div>
  </div>
  <p class="ds-note">Destructive actions sit last, below a separator. Never first, where a mis-tap lands.</p>

  <p class="ds-label">Table</p>
  <div class="ds-demo ds-demo--flush">
    <div class="ds-scroll"><table class="ds-table">
      <thead><tr><th>Code</th><th>Email</th><th>Credit limit</th><th>Created</th></tr></thead>
      <tbody>
        <tr><td><code class="t">SNW92TQR</code></td><td>andrew@example.com</td><td class="ds-num">$1,000.00</td><td>Aug 17</td></tr>
        <tr><td><code class="t">3ESHFJNX</code></td><td>&mdash;</td><td class="ds-num">$1,000.00</td><td>Aug 18</td></tr>
      </tbody>
    </table></div>
  </div>
  <p class="ds-note">Numeric columns are monospaced and right-aligned so figures compare down the column. Text columns stay left.</p>
` },

{ id: 'avatars', label: 'Avatars', html: `
  <h1 class="ds-h1">Avatars</h1>
  <p class="ds-intro">
    Initials on a tinted ground — never a photo. Members are people the organizer
    already knows by name, so an initial identifies a row without the upload flow,
    the storage, or the empty-state problem a photo would bring.
  </p>

  <p class="ds-label">Sizes</p>
  <div class="ds-demo">
    <div class="ds-center"><span class="avatar avatar--sm">AS</span><p class="ds-anno">24 &middot; dense rows</p></div>
    <div class="ds-center"><span class="avatar">AS</span><p class="ds-anno">32 &middot; default</p></div>
    <div class="ds-center"><span class="avatar avatar--lg">AS</span><p class="ds-anno">48 &middot; member detail</p></div>
  </div>

  <p class="ds-label">Tints carry state, not identity</p>
  <div class="ds-demo">
    <span class="avatar">MK</span>
    <span class="avatar avatar--accent">JS</span>
    <span class="avatar avatar--warning">AS</span>
    <span class="avatar avatar--danger">TB</span>
  </div>
  <p class="ds-note">
    Neutral by default. A tint means something is true of that member right now —
    up, needs attention, overdue — and uses the same semantic colours as
    everything else. Never assign a colour per person: a colour that means
    "Andrew" cannot also mean "overdue".
  </p>

  <p class="ds-label">In a row</p>
  <div class="ds-list ds-w-md">
    <div class="ds-row">
      <div class="ds-split" style="gap:var(--s3);justify-content:flex-start">
        <span class="avatar">AS</span>
        <span><span class="ds-body">Andrew Sandos</span><span class="ds-dim" style="display:block">3 open picks</span></span>
      </div>
      <span class="ds-num ds-lose">&minus;$180.00</span>
    </div>
    <div class="ds-row">
      <div class="ds-split" style="gap:var(--s3);justify-content:flex-start">
        <span class="avatar avatar--accent">JM</span>
        <span><span class="ds-body">Joseph Molina</span><span class="ds-dim" style="display:block">On heater</span></span>
      </div>
      <span class="ds-num ds-win">+$45.00</span>
    </div>
  </div>

  <p class="ds-label">Group</p>
  <div class="ds-demo ds-demo--roomy">
    <div class="avatar-stack">
      <span class="avatar avatar--sm">AS</span>
      <span class="avatar avatar--sm">JM</span>
      <span class="avatar avatar--sm">MK</span>
      <span class="avatar avatar--sm">+9</span>
    </div>
    <div class="avatar-stack">
      <span class="avatar">AS</span>
      <span class="avatar">JM</span>
      <span class="avatar">MK</span>
      <span class="avatar">+9</span>
    </div>
    <div class="avatar-stack">
      <span class="avatar avatar--lg">AS</span>
      <span class="avatar avatar--lg">JM</span>
      <span class="avatar avatar--lg">+9</span>
    </div>
  </div>
  <p class="ds-note">
    Chips overlap by 4, 4 and 12 across the three sizes, each ringed in the card
    colour so the stack reads as a stack. Two rules make it work, and both were
    once wrong here. <b>The overlap is bounded by the width of two initials, not
    by the chip.</b> These are letters, not photographs &mdash; a stack may
    cover the empty margin around the initials but not the initials themselves,
    or MK reads as MI. <b>And a chip must be opaque.</b> Every tint in this
    system is translucent, so without an opaque base underneath, a covered chip
    shows its initials straight through the chip covering it and the whole group
    turns to mush. The overflow count is the last chip, never a separate label.
  </p>
` },

{ id: 'data', label: 'Data Display', html: `
  <h1 class="ds-h1">Data Display</h1>
  <p class="ds-intro">
    Figures are the product. Every number is monospaced, right-aligned in a
    column, and signed. Colour indicates direction — up or down — and nothing
    else. A number is never coloured to draw the eye.
  </p>

  <p class="ds-label">Stat</p>
  <div class="ds-demo">
    <div class="ds-stat">
      <span class="ds-stat__label">Net position</span>
      <span class="ds-stat__value ds-win">+$1,284.50</span>
      <span class="ds-stat__sub">Across 12 members</span>
    </div>
    <div class="ds-stat">
      <span class="ds-stat__label">Open activity</span>
      <span class="ds-stat__value">$3,150.00</span>
      <span class="ds-stat__sub">22 picks unresolved</span>
    </div>
    <div class="ds-stat">
      <span class="ds-stat__label">This week</span>
      <span class="ds-stat__value ds-lose">&minus;$310.00</span>
      <span class="ds-stat__sub">Down from +$95.00</span>
    </div>
  </div>
  <p class="ds-note">
    A stat is label, figure, context — in that order and never fewer than three.
    A number with no comparison cannot be judged, so the sub-line is not optional.
  </p>

  <p class="ds-label">Credit utilisation</p>
  <div class="ds-demo ds-demo--col ds-demo--roomy ds-w-sm">
    <div class="ds-meter">
      <div class="ds-meter__track"><div class="ds-meter__fill" style="width:34%"></div></div>
      <div class="ds-meter__legend"><span>$340 used</span><span>$1,000 limit</span></div>
    </div>
    <div class="ds-meter">
      <div class="ds-meter__track"><div class="ds-meter__fill ds-meter__fill--warn" style="width:78%"></div></div>
      <div class="ds-meter__legend"><span>$780 used</span><span>$1,000 limit</span></div>
    </div>
    <div class="ds-meter">
      <div class="ds-meter__track"><div class="ds-meter__fill ds-meter__fill--danger" style="width:100%"></div></div>
      <div class="ds-meter__legend"><span>$1,000 used</span><span>At limit</span></div>
    </div>
  </div>
  <p class="ds-note">
    Accent below 75%, warning to 99%, danger at the limit. The thresholds are
    fixed so the same bar means the same thing on every screen. Credit used
    includes open stakes, not just settled balance.
  </p>

  <p class="ds-label">Performance by sport</p>
  <div class="ds-demo ds-demo--flush ds-w-md">
    <div class="ds-bars">
      ${barRow('MLB', 82, '+$640', false)}
      ${barRow('NFL', 45, '+$355', false)}
      ${barRow('NBA', 28, '&minus;$220', true)}
      ${barRow('NCAAB', 12, '&minus;$95', true)}
    </div>
  </div>
  <p class="ds-note">
    Bars are proportional to absolute value, so a loss and a win of the same size
    read as the same length. Direction comes from colour and the sign, not from
    bar length.
  </p>

  <ul class="ds-rules">
    <li>Always <code class="t">tabular-nums</code>. Figures that shift width as they change are unreadable.</li>
    <li>Always signed. "+$45.00" and "&minus;$45.00", never a bare "45.00" whose meaning depends on context.</li>
    <li>Currency to two decimals everywhere, including zero — "$0.00", not "$0".</li>
    <li>Colour means direction. A large number is not coloured for being large.</li>
  </ul>
` },

{ id: 'validation', label: 'Validation', html: `
  <h1 class="ds-h1">Validation</h1>
  <p class="ds-intro">
    A message says what is wrong and what to do about it. Validate on submit, not
    on every keystroke — telling someone their email is invalid while they are
    still typing it is noise, not help.
  </p>

  <p class="ds-label">Field states</p>
  <div class="ds-demo ds-demo--col ds-demo--roomy ds-w-sm">
    <label class="ds-field">
      <span class="ds-field__label">Email</span>
      <input class="ds-input" type="email" placeholder="member@example.com">
      <span class="ds-field__msg">They will receive an invite with a join link.</span>
    </label>
    <label class="ds-field">
      <span class="ds-field__label">Email</span>
      <input class="ds-input ds-input--error" type="email" value="andrew@">
      <span class="ds-field__msg ds-field__msg--error">Add the part after the @ &mdash; for example andrew@gmail.com.</span>
    </label>
    <label class="ds-field">
      <span class="ds-field__label">Credit limit</span>
      <input class="ds-input ds-input--num ds-input--ok" value="1000">
      <span class="ds-field__msg ds-field__msg--ok">Applies to new members from now on.</span>
    </label>
  </div>
  <p class="ds-note">
    Helper text occupies the same slot as the error, so the layout does not shift
    when validation fires. The slot is reserved even when empty.
  </p>

  <p class="ds-label">Writing the message</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Instead of</th><th>Write</th></tr></thead>
    <tbody>
      <tr><td class="ds-lose">Invalid input</td><td class="ds-win">Add the part after the @</td></tr>
      <tr><td class="ds-lose">Error: limit must be numeric</td><td class="ds-win">Enter an amount, like 500</td></tr>
      <tr><td class="ds-lose">Something went wrong</td><td class="ds-win">The line moved &mdash; confirm the new price</td></tr>
      <tr><td class="ds-lose">Required field</td><td class="ds-win">Add an email, or copy the code instead</td></tr>
    </tbody>
  </table></div>
  <p class="ds-note">
    Every one of these names the fix. A message that only names the problem makes
    the reader do the translation.
  </p>

  <ul class="ds-rules">
    <li>Validate on submit or on blur. Never on every keystroke.</li>
    <li>Move focus to the first failing field, so a long form does not need hunting.</li>
    <li>Server rules are the truth. Client validation is a courtesy, and both must agree.</li>
    <li>Success needs a message only when something non-obvious happened.</li>
  </ul>
` },

{ id: 'a11y', label: 'Focus & Access', html: `
  <h1 class="ds-h1">Focus &amp; Access</h1>
  <p class="ds-intro">
    Booki is used one-handed, often quickly, sometimes by someone who has just
    watched a bad beat. The system's job is to stay operable under those
    conditions — which is the same work as being accessible.
  </p>

  <p class="ds-label">Focus ring</p>
  <div class="ds-demo">
    <button class="ds-btn ds-btn--accent ds-focus-ring">Focused</button>
    <button class="ds-btn ds-btn--secondary ds-focus-ring">Focused</button>
    <span class="ds-badge ds-badge--live ds-focus-ring">Focusable</span>
  </div>
  <p class="ds-note">
    2px accent, 2px offset, on every interactive element. Applied through
    <code class="t">:focus-visible</code> so it appears for keyboard users without
    ringing every mouse click. Never removed without a replacement.
  </p>

  <p class="ds-label">Tap targets</p>
  <div class="ds-demo">
    <div class="ds-center"><span class="ds-target">&times;</span><p class="ds-anno">24 visual<br>44 target</p></div>
    <div class="ds-center"><span class="ds-target">&#9881;</span><p class="ds-anno">dashed = the hit area</p></div>
  </div>
  <p class="ds-note">
    A control may look 24px but must accept a 44px touch. Small dismiss and
    overflow controls are the usual offenders — they are visually quiet by
    design, which makes it easy to forget they still have to be hittable.
  </p>

  <p class="ds-label">Contrast</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Pair</th><th>Ratio</th><th>Use</th></tr></thead>
    <tbody>
      <tr><td>textPrimary on background</td><td class="ds-num">18.1&thinsp;:&thinsp;1</td><td>Any size</td></tr>
      <tr><td>textSecondary on background</td><td class="ds-num">8.9&thinsp;:&thinsp;1</td><td>Any size</td></tr>
      <tr><td>textMuted on background</td><td class="ds-num">4.1&thinsp;:&thinsp;1</td><td>Large or non-essential only</td></tr>
      <tr><td>accent on background</td><td class="ds-num">13.4&thinsp;:&thinsp;1</td><td>Any size</td></tr>
      <tr><td>background on accent</td><td class="ds-num">13.4&thinsp;:&thinsp;1</td><td>Button labels</td></tr>
    </tbody>
  </table></div>
  <p class="ds-note">
    <code class="t">textMuted</code> is the one to watch — it clears 4.5:1 only at
    large sizes, so it is for hints and timestamps, never for anything a decision
    depends on.
  </p>

  <ul class="ds-rules">
    <li>Colour is never the only signal. A win says "Won" as well as being cyan.</li>
    <li>Every animation honours reduce-motion, including the shimmer on skeletons.</li>
    <li>Icon-only controls carry a label for screen readers.</li>
    <li>Focus order follows reading order. A dialog traps focus until it closes.</li>
  </ul>
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
  <p class="ds-anno ds-anno--lead">
    iOS durations. The web dashboard runs faster and on three steps rather than
    four &mdash; <code class="t">--dur-fast</code> 0.15s,
    <code class="t">--dur-base</code> 0.2s, <code class="t">--dur-slow</code>
    0.3s &mdash; because pointer interactions tolerate less latency than touch.
    See Web&nbsp;Tokens.
  </p>
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
    ${gradient('buttonGradient', '--gradient-button', 'Primary CTAs on iOS')}
    ${gradient('rainbowGradient', '--gradient-rainbow', 'Special / featured')}
    ${gradient('goldGradient', '--gradient-gold', 'Achievements')}
    ${gradient('cardGradient', '--gradient-card', 'Subtle card depth')}
    ${gradient('gradient-accent', '--gradient-accent', 'Primary CTAs on web — see below')}
  </div>
  <p class="ds-note">
    Gradients on primary buttons only. Cards stay solid &mdash; cardGradient is
    depth, never colour.
  </p>
  <p class="ds-note">
    <b>iOS and web do not paint the same primary CTA.</b>
    <code class="t">--gradient-button</code> is Theme.buttonGradient, cyan into
    purple. The web dashboard paints
    <code class="t">--gradient-accent</code>, cyan into a deeper cyan, on every
    primary button it has. Both are shown above so the difference is visible
    rather than assumed. Unresolved: one of them should win.
  </p>
` },

{ id: 'web-tokens', label: 'Web Tokens', html: `
  <h1 class="ds-h1">Web Tokens</h1>
  <p class="ds-intro">
    The sections above mirror <code class="t">Theme.swift</code>, so they cover
    what iOS and web genuinely share &mdash; colour, spacing, radius. These are
    the token groups the web dashboard needs that have no iOS counterpart:
    translucent fills, elevation, motion, stacking order and element dimensions.
    All defined in <code class="t">landing/dashboard/dashboard.css</code> and
    enforced by <code class="t">scripts/check-design-tokens.py</code>.
  </p>

  <p class="ds-label">Opacity ladder</p>
  <p class="ds-anno ds-anno--lead">
    Every translucent fill is derived from a channel triplet
    (<code class="t">--accent-rgb</code> and friends) at one of these steps, so a
    palette change reaches the tints. Before this existed the tints were frozen
    literals: the danger tint was still the red <code class="t">--danger</code>
    had been months earlier, and the warning tint was a colour that was never a
    Booki token at all.
  </p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Value</th><th>Usage</th></tr></thead>
    <tbody>
      <tr><td><code class="t">--o-hairline</code></td><td>0.03</td><td>Row hover</td></tr>
      <tr><td><code class="t">--o-faint</code></td><td>0.05</td><td>Ambient glow, faint wells</td></tr>
      <tr><td><code class="t">--o-soft</code></td><td>0.10</td><td>Badge and chip fills</td></tr>
      <tr><td><code class="t">--o-med</code></td><td>0.15</td><td>Default tint &mdash; status fills</td></tr>
      <tr><td><code class="t">--o-strong</code></td><td>0.20</td><td>Selected states</td></tr>
      <tr><td><code class="t">--o-heavy</code></td><td>0.25</td><td>Borders on tinted surfaces</td></tr>
      <tr><td><code class="t">--o-glow</code></td><td>0.30</td><td>Accent shadows</td></tr>
      <tr><td><code class="t">--o-intense</code></td><td>0.40</td><td>Float shadows, scrims</td></tr>
      <tr><td><code class="t">--o-opaque</code></td><td>0.80</td><td>Loading veil over content</td></tr>
    </tbody>
  </table></div>

  <p class="ds-label">Elevation</p>
  <p class="ds-anno ds-anno--lead">
    Shadows are the accent glow, never black alone &mdash; consistent with
    Surfaces &amp; Elevation, where depth comes from colour.
  </p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Usage</th></tr></thead>
    <tbody>
      <tr><td><code class="t">--shadow-focus</code></td><td>Focus ring, 3px accent halo</td></tr>
      <tr><td><code class="t">--shadow-btn</code></td><td>Primary button at rest</td></tr>
      <tr><td><code class="t">--shadow-btn-hover</code></td><td>Primary button hover</td></tr>
      <tr><td><code class="t">--shadow-raised</code></td><td>Lifted card</td></tr>
      <tr><td><code class="t">--shadow-float</code></td><td>Floating bet slip bar</td></tr>
      <tr><td><code class="t">--shadow-modal</code></td><td>Modal, wide ambient glow</td></tr>
    </tbody>
  </table></div>

  <p class="ds-label">Motion</p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Duration</th><th>Usage</th></tr></thead>
    <tbody>
      <tr><td><code class="t">--dur-fast</code></td><td>0.15s</td><td>Hover, colour and opacity changes</td></tr>
      <tr><td><code class="t">--dur-base</code></td><td>0.2s</td><td>Borders, transforms</td></tr>
      <tr><td><code class="t">--dur-slow</code></td><td>0.3s</td><td>Panel slide, bet slip reflow</td></tr>
    </tbody>
  </table></div>

  <p class="ds-label">Stacking order</p>
  <p class="ds-anno ds-anno--lead">
    Was eight ad-hoc values between 2 and 1000 with no ordering rationale. Never
    write a raw <code class="t">z-index</code> &mdash; if nothing here fits, the
    layer is missing and belongs in this list.
  </p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Value</th><th>Layer</th></tr></thead>
    <tbody>
      <tr><td><code class="t">--z-base</code></td><td>1</td><td>Raised in-flow content</td></tr>
      <tr><td><code class="t">--z-dropdown</code></td><td>50</td><td>Menus, popovers</td></tr>
      <tr><td><code class="t">--z-sticky</code></td><td>100</td><td>Sticky headers</td></tr>
      <tr><td><code class="t">--z-betslip</code></td><td>150</td><td>Bet slip sidebar and bar</td></tr>
      <tr><td><code class="t">--z-overlay</code></td><td>200</td><td>Modal scrim</td></tr>
      <tr><td><code class="t">--z-modal</code></td><td>250</td><td>Modal above another overlay</td></tr>
      <tr><td><code class="t">--z-toast</code></td><td>300</td><td>Toasts &mdash; always on top</td></tr>
    </tbody>
  </table></div>

  <p class="ds-label">Dimensions</p>
  <p class="ds-anno ds-anno--lead">
    Sizes, not spacing, so deliberately not snapped to the 4pt grid &mdash; an
    18px icon rendered at 16 is a worse icon. A size used three or more times
    gets a name; a one-off container width stays a literal, because naming it
    moves the number without making it reusable.
  </p>
  <div class="ds-scroll"><table class="ds-table">
    <thead><tr><th>Token</th><th>Value</th><th>Usage</th></tr></thead>
    <tbody>
      <tr><td><code class="t">--hairline</code></td><td>1px</td><td>Borders, rules, dividers</td></tr>
      <tr><td><code class="t">--bar-thin</code></td><td>3px</td><td>Toast accent bar, progress</td></tr>
      <tr><td><code class="t">--dot-sm / --dot / --dot-lg</code></td><td>4 / 6 / 8px</td><td>Status dots, leg indicators</td></tr>
      <tr><td><code class="t">--icon-xs … --icon-lg</code></td><td>16 / 18 / 20 / 24px</td><td>Inline and nav icons</td></tr>
      <tr><td><code class="t">--badge</code></td><td>28px</td><td>Numbered step badge</td></tr>
      <tr><td><code class="t">--avatar-xs</code></td><td>32px</td><td>Compact avatar</td></tr>
      <tr><td><code class="t">--tile</code></td><td>36px</td><td>Rounded icon tile</td></tr>
      <tr><td><code class="t">--control</code></td><td>48px</td><td>Button and input height</td></tr>
      <tr><td><code class="t">--avatar-sm / --avatar / --avatar-lg</code></td><td>56 / 64 / 80px</td><td>Avatars, feature icons, logo</td></tr>
      <tr><td><code class="t">--odds-col</code></td><td>90px</td><td>Odds button and its column label &mdash; shared so they cannot drift apart</td></tr>
      <tr><td><code class="t">--w-panel … --w-content</code></td><td>280 / 320 / 480 / 768px</td><td>Container widths</td></tr>
      <tr><td><code class="t">--sidebar-width</code></td><td>240px</td><td>Fixed sidebar</td></tr>
      <tr><td><code class="t">--betslip-width</code></td><td>340px</td><td>Bet slip sidebar</td></tr>
    </tbody>
  </table></div>

  <p class="ds-anno">
    Skeleton geometry is deliberately exempt from all of this. A shimmer bar is
    100px wide because that is roughly how wide a name looks; those values are
    arbitrary and tokenising them would invent meaning that is not there.
  </p>
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

  { id: 'shipped', label: 'As Shipped', html: `
    <h2 class="ds-h1">As shipped</h2>
    <p class="ds-lede">Everything on this page renders from <code>tokens.css</code> and
    <code>dashboard.css</code> &mdash; the product's own stylesheets, not a copy. Change a
    component in the product and this page changes with it.</p>

    <p>That was not true until now. The page carried its own <code>.ds-*</code>
    implementation of every component, which is two hand-maintained copies of the
    same thing and exactly the arrangement that lets them drift apart. Avatars have
    been converted outright: the <code>.ds-avatar</code> rules are deleted and the
    Avatars section above renders the product's <code>.avatar</code> class directly.</p>

    <p><strong>Three components could not simply be renamed</strong>, because the two
    systems do not model them the same way. The design system names a badge for what
    it means &mdash; <code>won</code>, <code>lost</code>, <code>push</code> &mdash; and
    the product names it for how it looks &mdash; <code>success</code>,
    <code>danger</code>, <code>muted</code>. Those are different axes, not different
    spellings, and picking one is a design decision rather than a refactor.</p>

    <p>So the divergence is shown instead of hidden. Below, each component renders with
    the product's real classes, beside a list of what this page documents. Where the
    two columns disagree, that is the drift &mdash; visible on the page, which is the
    point.</p>

    <p class="ds-label">btn &mdash; rendered from dashboard.css</p>
    <div class="ds-demo"><div class="ds-wrapline"><button class="btn btn-accent">accent</button><button class="btn btn-danger">danger</button><button class="btn btn-danger-outline">danger-outline</button><button class="btn btn-ghost">ghost</button><button class="btn btn-grade">grade</button><button class="btn btn-grade-loss">grade-loss</button><button class="btn btn-grade-push">grade-push</button><button class="btn btn-grade-win">grade-win</button><button class="btn btn-primary-full">primary-full</button><button class="btn btn-secondary">secondary</button><button class="btn btn-void">void</button></div></div>
    <p class="ds-note">3 of 20 variants exist on both sides.</p>
    <div class="ds-scroll"><table class="ds-table">
      <thead><tr><th>variant</th><th>documented</th><th>shipped</th></tr></thead>
      <tbody><tr><td><code>accent</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>block</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>danger</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>danger-outline</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>destructive</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>ghost</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>grade</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>grade-loss</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>grade-push</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>grade-win</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>grow</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>icon</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>lg</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>link</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>primary</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>primary-full</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>quiet</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>secondary</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>sm</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>void</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr></tbody></table></div>

    <p class="ds-label">badge &mdash; rendered from dashboard.css</p>
    <div class="ds-demo"><div class="ds-wrapline"><span class="badge badge-accent">accent</span><span class="badge badge-danger">danger</span><span class="badge badge-muted">muted</span><span class="badge badge-pro">pro</span><span class="badge badge-success">success</span><span class="badge badge-warning">warning</span></div></div>
    <p class="ds-note">0 of 14 variants exist on both sides.</p>
    <div class="ds-scroll"><table class="ds-table">
      <thead><tr><th>variant</th><th>documented</th><th>shipped</th></tr></thead>
      <tbody><tr><td><code>accent</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>danger</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>final</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>live</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>lost</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>muted</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>off</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>pending</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>pro</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>push</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>scheduled</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>success</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>warning</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>won</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr></tbody></table></div>

    <p class="ds-label">card &mdash; rendered from dashboard.css</p>
    <div class="ds-demo"><div class="ds-wrapline"><div class="card card-header">header</div><div class="card card-title">title</div></div></div>
    <p class="ds-note">0 of 5 variants exist on both sides.</p>
    <div class="ds-scroll"><table class="ds-table">
      <thead><tr><th>variant</th><th>documented</th><th>shipped</th></tr></thead>
      <tbody><tr><td><code>elev</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>foot</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>head</code></td><td><span class="ds-ok">yes</span></td><td><span class="ds-no">&mdash;</span></td></tr><tr><td><code>header</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr><tr><td><code>title</code></td><td><span class="ds-no">&mdash;</span></td><td><span class="ds-ok">yes</span></td></tr></tbody></table></div>

    <p class="ds-note"><code>scripts/check-ds-drift.py</code> fails when a
    <code>.ds-*</code> component class duplicates a base that already exists in the
    product, so a new copy cannot be added quietly. It does not force the two naming
    models to agree &mdash; that is a decision for whoever resolves them.</p>
  ` },
  ];
