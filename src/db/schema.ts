import {
  pgTable,
  uuid,
  varchar,
  timestamp,
  pgEnum,
  integer,
  decimal,
} from "drizzle-orm/pg-core";

// Subscription status enum for bookies
export const subscriptionStatusEnum = pgEnum("subscription_status", [
  "active",
  "inactive",
  "trial",
]);

// Player status enum
export const playerStatusEnum = pgEnum("player_status", [
  "active",
  "archived",
  "banned",
]);

// Bet status enum - lifecycle states
export const betStatusEnum = pgEnum("bet_status", [
  "pending",
  "accepted",
  "declined",
  "ready_to_grade",
  "graded",
  "settled",
  "void",
]);

// Grade result enum - bet outcomes
export const gradeResultEnum = pgEnum("grade_result", ["win", "loss", "push"]);

// Ledger entry type enum
export const ledgerEntryTypeEnum = pgEnum("ledger_entry_type", [
  "settlement",
  "adjustment",
  "payment_logged",
  "reversal",
]);

// Event status enum
export const eventStatusEnum = pgEnum("event_status", [
  "scheduled",
  "live",
  "final",
]);

// Market type enum
export const marketTypeEnum = pgEnum("market_type", [
  "spread",
  "total",
  "moneyline",
]);

// Bookies table - stores bookie accounts
export const bookies = pgTable("bookies", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: varchar("email", { length: 255 }).notNull().unique(),
  name: varchar("name", { length: 255 }).notNull(),
  subscriptionStatus: subscriptionStatusEnum("subscription_status")
    .notNull()
    .default("trial"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Types for use in the application
export type Bookie = typeof bookies.$inferSelect;
export type NewBookie = typeof bookies.$inferInsert;

// Players table - stores player seats that belong to bookies
export const players = pgTable("players", {
  id: uuid("id").primaryKey().defaultRandom(),
  bookieId: uuid("bookie_id")
    .notNull()
    .references(() => bookies.id),
  name: varchar("name", { length: 255 }).notNull(),
  email: varchar("email", { length: 255 }),
  creditLimit: integer("credit_limit").notNull().default(0),
  status: playerStatusEnum("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Player types
export type Player = typeof players.$inferSelect;
export type NewPlayer = typeof players.$inferInsert;

// Bets table - stores bets with full lifecycle state machine
export const bets = pgTable("bets", {
  id: uuid("id").primaryKey().defaultRandom(),
  playerId: uuid("player_id")
    .notNull()
    .references(() => players.id),
  eventId: uuid("event_id").notNull(), // FK to events table (to be created in US-005)
  market: varchar("market", { length: 50 }).notNull(), // e.g., "spread", "total", "moneyline"
  side: varchar("side", { length: 100 }).notNull(), // e.g., "Team A -3.5", "Over 45.5"
  odds: integer("odds").notNull(), // American odds snapshot at submission (immutable after acceptance)
  stake: decimal("stake", { precision: 10, scale: 2 }).notNull(), // Bet amount
  status: betStatusEnum("status").notNull().default("pending"),
  gradeResult: gradeResultEnum("grade_result"), // null until graded
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Bet types
export type Bet = typeof bets.$inferSelect;
export type NewBet = typeof bets.$inferInsert;

// Ledger entries table - append-only financial records
export const ledgerEntries = pgTable("ledger_entries", {
  id: uuid("id").primaryKey().defaultRandom(),
  playerId: uuid("player_id")
    .notNull()
    .references(() => players.id),
  betId: uuid("bet_id").references(() => bets.id), // nullable - only set for settlement entries
  amount: decimal("amount", { precision: 10, scale: 2 }).notNull(), // positive or negative
  type: ledgerEntryTypeEnum("type").notNull(),
  description: varchar("description", { length: 500 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Ledger entry types
export type LedgerEntry = typeof ledgerEntries.$inferSelect;
export type NewLedgerEntry = typeof ledgerEntries.$inferInsert;

// Events table - stores sports events
export const events = pgTable("events", {
  id: uuid("id").primaryKey().defaultRandom(),
  sport: varchar("sport", { length: 100 }).notNull(),
  league: varchar("league", { length: 100 }).notNull(),
  homeTeam: varchar("home_team", { length: 255 }).notNull(),
  awayTeam: varchar("away_team", { length: 255 }).notNull(),
  startTime: timestamp("start_time", { withTimezone: true }).notNull(),
  status: eventStatusEnum("status").notNull().default("scheduled"),
  finalScore: varchar("final_score", { length: 50 }), // e.g., "24-17", nullable until game ends
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Event types
export type Event = typeof events.$inferSelect;
export type NewEvent = typeof events.$inferInsert;

// Markets table - stores betting markets for events
export const markets = pgTable("markets", {
  id: uuid("id").primaryKey().defaultRandom(),
  eventId: uuid("event_id")
    .notNull()
    .references(() => events.id),
  type: marketTypeEnum("type").notNull(),
  sideA: varchar("side_a", { length: 100 }).notNull(), // e.g., "Team A -3.5", "Over 45.5"
  sideB: varchar("side_b", { length: 100 }).notNull(), // e.g., "Team B +3.5", "Under 45.5"
  oddsA: integer("odds_a").notNull(), // American odds for side A
  oddsB: integer("odds_b").notNull(), // American odds for side B
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Market types
export type Market = typeof markets.$inferSelect;
export type NewMarket = typeof markets.$inferInsert;
