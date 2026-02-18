# PRD: Booki Motion Design System

## 1. Executive Summary

### Why Motion Matters for Booki

Booki is a sports betting management app where users make time-sensitive decisions involving real money. Motion design in this context serves critical functions:

1. **Confirmation and Confidence**: Users placing bets need immediate, clear feedback that their actions succeeded. Motion communicates "your bet is in" more viscerally than static UI.

2. **Error Prevention**: Subtle animation cues help users understand state changes (pending → accepted → graded → settled) preventing costly mistakes.

3. **Perceived Performance**: During network operations (bet submission, sync), well-designed loading states make the app feel faster and more reliable.

4. **Emotional Calibration**: Sports betting is inherently high-stakes and emotional. Motion can add moments of delight (wins) while maintaining calm professionalism during losses.

5. **Spatial Understanding**: As users navigate between games, bet slips, and history, motion establishes where they are and how to get back.

### Current State Assessment

Booki already has a **solid animation foundation** including:
- Spring-based button feedback (200ms response)
- Multi-layer success celebrations
- Pulsing attention indicators
- Proper loading states
- Tab switching animations

However, opportunities exist to:
- Systematize timing and easing into reusable tokens
- Add hero transitions between related screens
- Enhance data update animations (live scores, odds changes)
- Improve gesture feedback during bet slip interactions
- Create more cohesive navigation transitions

### What Success Looks Like

After implementing this motion system:

- **Quantitative**: 15% reduction in support tickets related to "did my bet go through?"
- **Quantitative**: 10% improvement in task completion rate for first-time bet placement
- **Qualitative**: Users describe the app as "smooth" and "responsive" in reviews
- **Qualitative**: Zero user complaints about animations being "too slow" or "distracting"
- **Technical**: All animations respect accessibility settings (Reduce Motion)
- **Technical**: No animation-related frame drops below 60fps on iPhone 12 and newer

---

## 2. Motion Design Principles for Booki

### Principle 1: Instant Acknowledgment

**Description**: Every user action receives immediate visual feedback within 100ms. Users should never wonder "did that tap register?"

**Example Behaviors**:
- Button press scales to 0.97x instantly on touch-down
- Odds button highlights immediately when tapped
- Swipe actions reveal without delay
- Toggle switches respond on first frame of gesture

### Principle 2: Confident Completion

**Description**: Success states are celebrated clearly but briefly. Users feel confident their action completed without lingering animations blocking flow.

**Example Behaviors**:
- Bet submission shows checkmark + expanding ring (600ms total)
- Success states auto-dismiss after 1.5 seconds maximum
- Settlement confirmations use solid color flash, not confetti
- "Added to bet slip" confirmation is subtle and fast (200ms)

### Principle 3: Spatial Continuity

**Description**: Navigation transitions reinforce the app's information architecture. Users understand where they came from and can predict where they're going.

**Example Behaviors**:
- Tapping a game card expands into detail view (shared element transition)
- Bet slip slides up from floating indicator position
- Back navigation reverses the forward animation
- Tab switching maintains scroll position context

### Principle 4: Data Choreography

**Description**: When multiple data points update simultaneously, they animate in a coordinated sequence rather than chaotic simultaneous pops.

**Example Behaviors**:
- Live score updates cascade: away → home → status badge
- Bet list reorders with staggered 50ms delays between rows
- Dashboard stat cards animate in sequence on refresh
- New bets insert at top with push-down effect on existing items

### Principle 5: Calm Professionalism

**Description**: Motion reinforces trust and professionalism. Animations are smooth and controlled, never bouncy or playful in ways that undermine seriousness.

**Example Behaviors**:
- No emoji animations or character celebrations
- Color changes use opacity transitions (not hue spinning)
- Springs are critically damped (0.7-0.8), not bouncy (0.4-0.5)
- Error states use static icons, not shaking/pulsing

### Principle 6: Performance First

**Description**: Animations never block user interaction or mask slow performance. Loading states are honest about wait times.

**Example Behaviors**:
- Skeleton screens for content loading (not spinners for data)
- Animations complete in under 400ms for primary actions
- Progress indicators show determinate progress when possible
- No animations during scroll to maintain 60fps

### Principle 7: Accessible by Default

**Description**: All animations gracefully degrade when Reduce Motion is enabled. Core functionality never depends on animation completion.

**Example Behaviors**:
- Reduce Motion replaces movement with opacity crossfades
- No information is conveyed through animation alone
- Animation durations are queryable for testing
- Spring animations have finite durations (not infinite)

---

## 3. Audit of Motion Gaps

### Gap 1: Abrupt List Updates

**Current State**: When bets change status or new bets appear, the list updates instantly without animation.

**UX Impact**: Users lose context of what changed. In a list of 20 bets, a status change is invisible without scanning every row.

**Observed In**: BetsListView, PlayersListView, GradingView

### Gap 2: Missing Hero Transitions

**Current State**: Tapping a game or bet pushes a new view with standard iOS slide. No visual connection between the tapped element and the detail view.

**UX Impact**: Users experience navigation as teleportation rather than zooming in on content. Returning feels disorienting.

**Observed In**: GamesView → GameDetailView, BetsListView → TicketDetailView

### Gap 3: Static Live Data

**Current State**: Live scores and odds update by replacing text values without animation.

**UX Impact**: Users miss important changes. A score going from 14-14 to 21-14 appears identical to any other refresh.

**Observed In**: GameCardView, CompactGameRow, EventDetailView

### Gap 4: Binary Loading States

**Current State**: Loading uses circular spinners that give no progress indication.

**UX Impact**: Users can't distinguish between "loading normally" and "something is stuck." Anxiety increases during bet submission.

**Observed In**: BetSlipSheet submission, SyncService operations

### Gap 5: Inconsistent Button Feedback

**Current State**: Primary buttons use spring scale (0.97x), but many secondary buttons have no press feedback.

**UX Impact**: Secondary actions feel unresponsive compared to primary ones. Users may double-tap unnecessarily.

**Observed In**: Cancel buttons, text links, toolbar items

### Gap 6: No Pull-to-Refresh Feedback

**Current State**: Lists refresh on pull but use default iOS spinner only.

**UX Impact**: Missed opportunity for branded experience. No indication of what's being refreshed.

**Observed In**: All scrollable lists

### Gap 7: Form Field Focus Transitions

**Current State**: TextField focus shows border change but no smooth transition.

**UX Impact**: Form interactions feel static. Users don't get clear feedback that keyboard will appear.

**Observed In**: Stake entry, login forms, player creation

### Gap 8: Empty State Transitions

**Current State**: Empty states appear/disappear instantly when data changes.

**UX Impact**: Jarring when a filter change reveals "No games found" or when games suddenly appear.

**Observed In**: GamesView filters, BetsListView filters

---

## 4. High-Impact Motion Opportunities

### Category: Navigation & Structure

| # | Area | Problem Today | Proposed Microinteraction | UX Value | Complexity | Priority |
|---|------|---------------|---------------------------|----------|------------|----------|
| N1 | Game → Detail | Standard push animation | Shared element: game card expands into detail header | High: Maintains context | Medium | P0 |
| N2 | Bet Slip Open | Slides from bottom edge | Slides from floating indicator position with scale | Medium: Spatial continuity | Low | P1 |
| N3 | Tab Switching | Content swaps instantly | Crossfade with 150ms duration | Medium: Reduces jarring | Low | P1 |
| N4 | Back Navigation | Standard iOS back slide | Mirror of forward transition | Medium: Predictability | Low | P1 |
| N5 | Sheet Dismissal | Standard slide down | Velocity-based: fast swipe = fast dismiss | Low: Polish | Low | P2 |

### Category: Core Interactions

| # | Area | Problem Today | Proposed Microinteraction | UX Value | Complexity | Priority |
|---|------|---------------|---------------------------|----------|------------|----------|
| C1 | Odds Selection | Color change only | Scale pulse (1.05x) + haptic + color | High: Clear selection | Low | P0 |
| C2 | Stake Entry | Border change on focus | Border animates thickness + glow appears | Medium: Focus clarity | Low | P1 |
| C3 | Bet Removal | Slide out right | Scale down + fade + collapse space | Medium: Clear deletion | Low | P1 |
| C4 | Parlay Toggle | Instant switch | Pill slides with content crossfade | Low: Polish | Low | P2 |
| C5 | Swipe Actions | Reveal without animation | Reveal with spring resistance | Low: Tactile feel | Low | P2 |

### Category: System Feedback

| # | Area | Problem Today | Proposed Microinteraction | UX Value | Complexity | Priority |
|---|------|---------------|---------------------------|----------|------------|----------|
| F1 | Bet Submission | Checkmark appears | Multi-phase: spinner → checkmark → expand → dismiss | High: Confidence | Medium | P0 |
| F2 | Status Change | Instant color change | Flash highlight → settle to new color | High: Visibility | Low | P0 |
| F3 | Error States | Static error message | Shake input field + red border pulse | Medium: Attention | Low | P1 |
| F4 | Network Offline | Banner appears instantly | Slide down + icon rotation | Medium: Awareness | Low | P1 |
| F5 | Sync Complete | No feedback | Subtle green flash on synced badge | Low: Reassurance | Low | P2 |

### Category: Loading & Performance

| # | Area | Problem Today | Proposed Microinteraction | UX Value | Complexity | Priority |
|---|------|---------------|---------------------------|----------|------------|----------|
| L1 | Game List | Spinner while loading | Skeleton cards with shimmer | High: Perceived speed | Medium | P0 |
| L2 | Bet Submission | Circular spinner | Progress ring fills as stages complete | High: Reduces anxiety | Medium | P1 |
| L3 | Pull to Refresh | iOS default spinner | Branded indicator with sync icon | Medium: Branding | Low | P1 |
| L4 | Image Loading | Pop in when ready | Fade in from placeholder | Low: Polish | Low | P2 |
| L5 | Initial Launch | Static splash | Logo scale + fade into content | Low: First impression | Low | P2 |

### Category: Delight Moments

| # | Area | Problem Today | Proposed Microinteraction | UX Value | Complexity | Priority |
|---|------|---------------|---------------------------|----------|------------|----------|
| D1 | Win Celebration | Static checkmark | Checkmark + subtle gold shimmer + balance highlight | High: Emotional payoff | Medium | P1 |
| D2 | First Bet | No special treatment | Confetti-free "First bet placed!" badge | Medium: Milestone | Low | P2 |
| D3 | Streak Badge | No streaks shown | Win streak counter with increment animation | Medium: Engagement | Medium | P2 |
| D4 | Score Change | Instant update | Number rolls/flips to new value | Medium: Excitement | Medium | P2 |
| D5 | Big Win | Same as normal win | Larger expansion + longer celebration | Low: Special moments | Low | P3 |

---

## 5. Motion System Proposal

### Duration Scale

| Token | Duration | Use Cases |
|-------|----------|-----------|
| `instant` | 0ms | Immediate state changes with no animation |
| `fast` | 100ms | Press feedback, micro-interactions |
| `normal` | 200ms | Standard transitions, button animations |
| `slow` | 350ms | Complex transitions, shared elements |
| `emphasis` | 500ms | Success celebrations, important feedback |

### Easing Curves

| Name | Curve | When to Use |
|------|-------|-------------|
| `standard` | `easeInOut` | General purpose transitions |
| `decelerate` | `easeOut` | Elements entering the screen |
| `accelerate` | `easeIn` | Elements leaving the screen |
| `emphasized` | `cubicBezier(0.4, 0.0, 0.2, 1.0)` | Important state changes |
| `spring` | `spring(response: 0.3, dampingFraction: 0.7)` | Interactive elements, bouncy feel |
| `springTight` | `spring(response: 0.2, dampingFraction: 0.8)` | Quick responsive feedback |

### Animation Patterns

#### Fade
```swift
// Standard fade
.opacity(isVisible ? 1 : 0)
.animation(.easeInOut(duration: 0.2), value: isVisible)

// Asymmetric fade (fast in, slow out)
.transition(.asymmetric(
    insertion: .opacity.animation(.easeOut(duration: 0.15)),
    removal: .opacity.animation(.easeIn(duration: 0.25))
))
```

#### Scale
```swift
// Press feedback
.scaleEffect(isPressed ? 0.97 : 1.0)
.animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)

// Selection pulse
.scaleEffect(isSelected ? 1.05 : 1.0)
.animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
```

#### Slide
```swift
// Slide from bottom
.transition(.move(edge: .bottom).combined(with: .opacity))

// Slide from trailing (for removal)
.transition(.asymmetric(
    insertion: .scale(scale: 0.95).combined(with: .opacity),
    removal: .move(edge: .trailing).combined(with: .opacity)
))
```

#### Shared Element Transitions
```swift
// Using matchedGeometryEffect
.matchedGeometryEffect(id: gameId, in: namespace)

// Coordinated with navigation
.navigationTransition(.zoom(sourceID: gameId, in: namespace))
```

### When NOT to Animate

1. **During Active Scrolling**: Disable per-item animations while scroll velocity > 0
2. **Bulk Data Updates**: When > 10 items change, use crossfade not individual animations
3. **Background Syncs**: Don't animate changes user didn't initiate
4. **Reduce Motion Enabled**: Replace all motion with opacity crossfades
5. **Low Battery Mode**: Reduce animation durations by 50%
6. **Error Recovery**: After errors, restore state without animation
7. **Form Validation**: Don't animate every keystroke validation

---

## 6. Platform Implementation Notes

### iOS Implementation (SwiftUI)

#### Recommended Frameworks
- **SwiftUI Animations**: Primary system for all standard animations
- **matchedGeometryEffect**: Hero transitions between views
- **TimelineView**: For continuous animations (pulsing, shimmer)
- **Core Animation**: Only for complex custom effects

#### Animation Tokens as Extensions
```swift
extension Animation {
    static let booki = BookiAnimation.self

    enum BookiAnimation {
        static let fast = Animation.easeInOut(duration: 0.1)
        static let normal = Animation.easeInOut(duration: 0.2)
        static let slow = Animation.easeInOut(duration: 0.35)
        static let emphasis = Animation.easeInOut(duration: 0.5)
        static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let springTight = Animation.spring(response: 0.2, dampingFraction: 0.8)
    }
}

// Usage
withAnimation(.booki.spring) {
    isSelected = true
}
```

#### Accessibility Compliance
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

var animation: Animation {
    reduceMotion ? .none : .booki.spring
}
```

#### Performance Best Practices
- Use `drawingGroup()` for complex animated views
- Prefer `opacity` and `scaleEffect` over `offset` animations
- Avoid animating `frame` directly; animate container instead
- Use `LazyVStack` to prevent off-screen animation calculations

### Android Implementation (Compose)

#### Recommended Frameworks
- **Compose Animation APIs**: `animateFloatAsState`, `AnimatedVisibility`
- **Shared Element Transitions**: `SharedTransitionLayout` (Compose 1.7+)
- **Motion Layout**: For complex coordinated animations

#### Animation Tokens
```kotlin
object BookiAnimation {
    val fast = tween<Float>(100, easing = FastOutSlowInEasing)
    val normal = tween<Float>(200, easing = FastOutSlowInEasing)
    val slow = tween<Float>(350, easing = FastOutSlowInEasing)
    val spring = spring<Float>(dampingRatio = 0.7f, stiffness = 300f)
}
```

#### Accessibility
```kotlin
val reduceMotion = LocalReduceMotion.current

val animationSpec = if (reduceMotion) {
    snap()
} else {
    BookiAnimation.spring
}
```

---

## 7. Rollout Plan

### Phase 1: Quick Wins (Weeks 1-2)

**Goal**: Immediate polish improvements with minimal risk

| Item | Description | Files Affected |
|------|-------------|----------------|
| Button feedback | Add spring scale to all secondary buttons | Theme.swift, ButtonStyles |
| Status flash | Add highlight flash when bet status changes | StatusBadge, BetsListView |
| Tab crossfade | Add 150ms crossfade to tab content | ContentView, PlayerMainView |
| Error shake | Shake animation for validation errors | Form fields across app |
| Network banner | Smooth slide for offline indicator | ContentView |

**Success Criteria**: No regressions, animations feel consistent

### Phase 2: Structural Transitions (Weeks 3-5)

**Goal**: Improve navigation clarity with hero transitions

| Item | Description | Files Affected |
|------|-------------|----------------|
| Game hero | Shared element transition game → detail | GamesView, GameDetailView |
| Bet slip origin | Slide from indicator position | BetSlipSheet |
| List animations | Staggered insert/remove for bet list | BetsListView |
| Skeleton screens | Replace spinners with skeleton cards | GamesView, BetsListView |
| Progress indicator | Phased progress for bet submission | BetSlipSheet |

**Success Criteria**: Navigation feels spatially coherent, loading feels faster

### Phase 3: Delight and Polish (Weeks 6-8)

**Goal**: Add personality and emotional resonance

| Item | Description | Files Affected |
|------|-------------|----------------|
| Win celebration | Enhanced success animation for wins | BetSlipSheet, GradingView |
| Score animations | Rolling numbers for live scores | GameCardView |
| Pull refresh | Branded refresh indicator | All list views |
| Shimmer loading | Add shimmer to skeleton screens | SkeletonView (new) |
| Micro-delights | Polish details throughout | Various |

**Success Criteria**: Users notice and appreciate polish, no "too much" feedback

---

## 8. Success Metrics

### Qualitative Metrics

| Metric | Measurement Method | Target |
|--------|-------------------|--------|
| Perceived responsiveness | User interviews, "How responsive does the app feel?" (1-5) | 4.2+ average |
| Animation appropriateness | User testing, "Were any animations distracting?" | <10% yes |
| Navigation clarity | Task completion without wrong turns | 90%+ first-try success |
| Emotional resonance | Post-win survey, "How did you feel after winning?" | 80%+ positive |

### Quantitative Metrics

| Metric | Measurement Method | Target |
|--------|-------------------|--------|
| Animation frame rate | Instruments profiling | 60fps, <1% drops |
| Time to first interaction | Analytics timestamp | <100ms after touch |
| Bet confirmation queries | Support ticket analysis | 15% reduction |
| Task completion rate | Analytics funnel | 10% improvement |

### Product Metrics

| Metric | Measurement Method | Target |
|--------|-------------------|--------|
| Session duration | Analytics | No regression |
| Bets per session | Analytics | No regression |
| Return user rate | Analytics | 5% improvement |
| App Store rating | Reviews mentioning "smooth/fast/responsive" | Increase mentions |

### Technical Metrics

| Metric | Measurement Method | Target |
|--------|-------------------|--------|
| Reduce Motion compliance | Automated testing | 100% coverage |
| Animation duration consistency | Unit tests | All use token system |
| Memory during animation | Instruments | No increase vs static |
| Battery during animation | XCTest energy diagnostics | <5% increase |

---

## Appendix A: Animation Token Reference

```swift
// Duration tokens
enum Duration {
    static let instant: Double = 0
    static let fast: Double = 0.1
    static let normal: Double = 0.2
    static let slow: Double = 0.35
    static let emphasis: Double = 0.5
}

// Spring configurations
enum SpringConfig {
    static let responsive = (response: 0.2, damping: 0.8)
    static let standard = (response: 0.3, damping: 0.7)
    static let bouncy = (response: 0.4, damping: 0.6)
    static let gentle = (response: 0.5, damping: 0.7)
}

// Transition presets
enum TransitionPreset {
    static let fade = AnyTransition.opacity
    static let scale = AnyTransition.scale(scale: 0.95).combined(with: .opacity)
    static let slideUp = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    static let slideRight = AnyTransition.move(edge: .trailing).combined(with: .opacity)
}
```

---

## Appendix B: Reduce Motion Alternatives

| Standard Animation | Reduce Motion Alternative |
|-------------------|---------------------------|
| Spring scale press feedback | Instant opacity change (0.7 → 1.0) |
| Slide transitions | Crossfade (200ms) |
| Expanding success ring | Opacity pulse |
| Skeleton shimmer | Static skeleton (no shimmer) |
| Score number roll | Instant number change |
| Staggered list items | Simultaneous fade |
| Hero transitions | Standard crossfade |

---

## Appendix C: Testing Checklist

For each animation implementation:

- [ ] Works with Reduce Motion enabled
- [ ] Maintains 60fps on iPhone 12
- [ ] Doesn't block user interaction
- [ ] Uses duration from token system
- [ ] Uses easing from token system
- [ ] Has unit test for animation presence
- [ ] Documented in motion system guide
- [ ] Reviewed for appropriateness by design

---

*Document Version: 1.0*
*Last Updated: February 2026*
*Author: Motion Design System Initiative*
