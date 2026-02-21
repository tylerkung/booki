# PRD: Simplify Bookie Onboarding

## Introduction

The current bookie onboarding flow has too many steps that create friction for new users. Steps like "Add Members" and "Import Games" (which requires an API key) belong later in the experience, not at first launch. The onboarding should be stripped down to: show a welcome screen, then go straight to the dashboard. All configuration (reconciliation frequency, auto-accept, auto-grade, credit limits) uses sensible defaults and can be changed later in Settings.

## Goals

- Remove all intermediate onboarding steps (Configure, Add Members, Import Games, Success)
- Reduce onboarding to a single welcome screen with a CTA to enter the dashboard
- Ensure sensible defaults are applied without requiring user input
- Keep all removed functionality accessible via Settings and main app tabs

## User Stories

### US-001: Strip onboarding to welcome-only flow
**Description:** As a new bookie, I want to get to the dashboard immediately after signing up so I can start exploring the app without a multi-step wizard.

**Acceptance Criteria:**
- [ ] OnboardingContainerView only shows the Welcome step, then dismisses onboarding
- [ ] The "Set Up Your Group" button on OnboardingWelcomeView marks onboarding complete and goes to dashboard
- [ ] The "Skip for now" button also marks onboarding complete and goes to dashboard
- [ ] No Configure, Add Members, Import Games, or Success screens are shown
- [ ] Progress dots / "Step X of 3" header is removed (only one screen, no steps)
- [ ] Typecheck passes

### US-002: Apply sensible defaults on account creation
**Description:** As a new bookie, I want the app to use good defaults so everything works without manual configuration during onboarding.

**Acceptance Criteria:**
- [ ] Auto-accept picks defaults to ON (bookie.manualBetAcceptance = false) — already the default
- [ ] Auto-grade picks defaults to ON (bookie.manualBetGrading = false) — already the default
- [ ] Default credit limit is set to $500 via @AppStorage("default_credit_limit") if not already set
- [ ] Reconciliation frequency defaults to "weekly" — verify this is the existing default
- [ ] All defaults are applied without user interaction
- [ ] Typecheck passes

### US-003: Clean up unused onboarding files
**Description:** As a developer, I want to remove dead onboarding code so the codebase stays clean.

**Acceptance Criteria:**
- [ ] OnboardingConfigureView.swift is deleted
- [ ] OnboardingAddPlayersView.swift is deleted
- [ ] OnboardingImportGamesView.swift is deleted
- [ ] OnboardingSuccessView.swift is deleted
- [ ] OnboardingStep enum is simplified to only have `.welcome` (or removed entirely if unnecessary)
- [ ] OnboardingManager is simplified — `markStepComplete()` and per-step tracking removed, only `isOnboardingComplete` / `markAllComplete()` needed
- [ ] All references to removed files are cleaned up (imports, Xcode project file if needed)
- [ ] No compiler warnings about unused code
- [ ] Typecheck passes

## Functional Requirements

- FR-1: New bookies see only the Welcome screen during onboarding
- FR-2: Tapping the primary CTA ("Set Up Your Group") marks onboarding complete and dismisses the modal
- FR-3: Tapping "Skip for now" has the same behavior as the primary CTA
- FR-4: Sensible defaults are applied automatically (auto-accept ON, auto-grade ON, $500 credit limit, weekly reconciliation)
- FR-5: All configuration previously in onboarding remains accessible in Settings
- FR-6: All member management previously in onboarding remains accessible in the Members tab
- FR-7: All game import functionality previously in onboarding remains accessible in the Games tab

## Non-Goals

- Not changing the Settings view — all configure options already exist there
- Not changing the Members tab — invite/add functionality already exists
- Not changing the Games tab — import functionality already exists
- Not investigating the "Jeff" player visibility issue (separate task)
- Not changing the player claim/onboarding flow

## Technical Considerations

- `OnboardingManager` uses `@AppStorage` keys for step completion — simplify to a single `isOnboardingComplete` flag
- `AuthGateView` triggers onboarding as a `.fullScreenCover` — this mechanism stays, just dismisses faster
- The 4 deleted view files need to be removed from the Xcode project file (`project.pbxproj`) as well
- Existing bookies who already completed onboarding are unaffected (`isOnboardingComplete` is already `true`)

## Success Metrics

- New bookie goes from sign-up to dashboard in 1 tap (down from 4+ screens)
- No onboarding-related user confusion or support requests
- 4 fewer Swift files in the codebase

## Open Questions

- None — scope is clear
