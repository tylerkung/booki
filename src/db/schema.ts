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
