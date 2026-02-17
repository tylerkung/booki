# PRD: Guided Bookie Onboarding & First-Run Setup

## Introduction

New bookies land in the app after signup with no structured guidance. They must discover how to configure their book, add players, import games, and understand how betting works. This creates friction and weak activation.

We will introduce a **Guided Setup Flow** that takes a bookie from signup to first-bet-readiness in minutes.

**Goal:** Turn Booki into a product that onboards itself.

## Problem Statement

New bookies currently experience:
- Empty screens
- Hidden settings
- No sense of progress
- No clear "first success moment"

Without early activation, users churn before experiencing value.

**Activation Milestone:** "My book is ready to take bets."

## Goals

### User Goals
- Understand what Booki does
- Configure their book quickly
- Add players easily
- Get to a ready state fast

### Business Goals
- Increase signup → activation rate
- Reduce first-day churn
- Prepare users for trial → subscription funnel

## Activation Milestone Definition

A bookie is considered **activated** when they have completed:
1. Book configuration
2. Added at least 1 player
3. Imported at least 1 sport's games

## When Onboarding Appears

Show onboarding when:
- A bookie logs in for the first time
- OR onboarding has not been completed

Onboarding is **resumable**.

## Onboarding Flow Structure

**Flow style:** Full-screen stepper
**Progress indicator:** "Step X of 4"
**Skippable:** Yes (but incomplete state persists)

### Steps:
1. Welcome
2. Configure Book
3. Add Players
4. Import Games
5. Success State

---

## User Stories

### US-001: Create OnboardingManager to track state
**Description:** As a developer, I need a service to track which onboarding steps are complete so we can resume and show/hide onboarding.

**Acceptance Criteria:**
- [ ] Create `OnboardingManager.swift` in Services folder
- [ ] Track completion state for each step: welcome, configureBook, addPlayers, importGames
- [ ] Persist state using @AppStorage or UserDefaults
- [ ] Provide `isOnboardingComplete` computed property
- [ ] Provide `nextIncompleteStep` computed property for resuming
- [ ] Typecheck passes

### US-002: Create Welcome Screen (Step 1)
**Description:** As a new bookie, I want to see a welcome screen that frames what Booki does so I understand the product.

**Acceptance Criteria:**
- [ ] Create `OnboardingWelcomeView.swift` in Views folder
- [ ] Headline: "Run your sportsbook like a business."
- [ ] Body: "Booki helps you track bets, manage players, and run weekly settlements."
- [ ] Primary CTA: "Set up your book" → advances to next step
- [ ] Secondary CTA: "Skip for now" → goes to dashboard with incomplete state
- [ ] Use Theme colors and styling
- [ ] Typecheck passes

### US-003: Create Configure Book Screen (Step 2)
**Description:** As a new bookie, I want to configure my book settings during onboarding so I don't have to find them in Settings.

**Acceptance Criteria:**
- [ ] Create `OnboardingConfigureView.swift` in Views folder
- [ ] Settlement frequency picker: Weekly (default), Bi-weekly, Monthly
- [ ] Bet approval mode: Auto-accept (recommended), Manual approval
- [ ] Bet grading mode: Auto-grade (recommended), Manual grading
- [ ] Default player credit limit: numeric input with $500 placeholder
- [ ] Save settings to Bookie model and AcceptancePolicy
- [ ] "Continue" button advances to next step
- [ ] Typecheck passes

### US-004: Create Add Players Screen (Step 3)
**Description:** As a new bookie, I want to add my first players during onboarding so I don't start with an empty book.

**Acceptance Criteria:**
- [ ] Create `OnboardingAddPlayersView.swift` in Views folder
- [ ] Headline: "Your book needs players."
- [ ] Two options: "Invite players" and "Add manually"
- [ ] Invite players: generate code via InviteCodeService, show share sheet
- [ ] Add manually: inline form with name, credit limit (prefilled from default)
- [ ] Show success checkmark after adding first player
- [ ] "Continue" button appears once >= 1 player exists
- [ ] Typecheck passes

### US-005: Create Import Games Screen (Step 4)
**Description:** As a new bookie, I want to import games during onboarding so I have events to bet on immediately.

**Acceptance Criteria:**
- [ ] Create `OnboardingImportGamesView.swift` in Views folder
- [ ] Headline: "Let's add upcoming games."
- [ ] Multi-select sport chips: NFL, NBA, MLB, NHL
- [ ] "Import games" button triggers OddsAPIService import
- [ ] Show loading state during import
- [ ] Show success state: "X games imported successfully"
- [ ] Auto-advance to success screen after import completes
- [ ] Typecheck passes

### US-006: Create Success Screen (Step 5)
**Description:** As a new bookie, I want to see a success screen confirming my book is ready so I feel accomplished.

**Acceptance Criteria:**
- [ ] Create `OnboardingSuccessView.swift` in Views folder
- [ ] Headline: "Your book is ready" with celebration styling
- [ ] Show completed checklist: Book configured, Players added, Games imported
- [ ] Each item shows green checkmark
- [ ] Primary CTA: "Go to Dashboard" → navigates to main app
- [ ] Mark onboarding as complete in OnboardingManager
- [ ] Typecheck passes

### US-007: Create OnboardingContainerView with stepper
**Description:** As a developer, I need a container view that manages the step flow and progress indicator.

**Acceptance Criteria:**
- [ ] Create `OnboardingContainerView.swift` in Views folder
- [ ] Show "Step X of 4" progress indicator at top
- [ ] Navigate between steps using @State currentStep
- [ ] Handle back navigation where appropriate
- [ ] Support skipping to dashboard at any point
- [ ] Full-screen presentation style
- [ ] Typecheck passes

### US-008: Integrate onboarding into app launch flow
**Description:** As a new bookie, I want onboarding to appear automatically after my first login.

**Acceptance Criteria:**
- [ ] Update AuthGateView or ContentView to check OnboardingManager.isOnboardingComplete
- [ ] If not complete and user is bookie, present OnboardingContainerView
- [ ] After onboarding completes, transition to normal dashboard
- [ ] Existing bookies (already have players/games) skip onboarding
- [ ] Typecheck passes

### US-009: Add "Finish Setup" card to dashboard for incomplete onboarding
**Description:** As a bookie who skipped onboarding, I want a reminder card on dashboard so I can resume setup.

**Acceptance Criteria:**
- [ ] Add `FinishSetupCard` component to DashboardView
- [ ] Only show if OnboardingManager.isOnboardingComplete is false
- [ ] Card shows: "Finish setting up your book" with progress (e.g., "2 of 4 steps complete")
- [ ] Tap opens OnboardingContainerView at next incomplete step
- [ ] Card disappears once onboarding is complete
- [ ] Typecheck passes

---

## Functional Requirements

- FR-1: Onboarding state persists across app launches
- FR-2: Steps can be completed in order only (no skipping ahead)
- FR-3: User can skip entire onboarding but incomplete state shows on dashboard
- FR-4: If user already has players, step 3 auto-completes
- FR-5: If user already has games, step 4 auto-completes
- FR-6: Settings saved during onboarding sync to Supabase

## Non-Goals (Out of Scope)

- Subscription/paywall integration
- Player billing setup
- Advanced tutorials or tooltips
- Push notification permissions
- Analytics event tracking (future PRD)

## Technical Considerations

- Use existing `InviteCodeService` for player invites
- Use existing `OddsAPIService` for game imports
- Use existing `AcceptancePolicy` model for settings
- OnboardingManager should be observable (@Observable or ObservableObject)
- Consider using NavigationStack for step management

## Success Metrics

**Primary:**
- Signup → Activation rate ↑

**Secondary:**
- Time to first player ↓
- Time to first game import ↓
