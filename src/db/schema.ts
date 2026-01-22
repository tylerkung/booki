import { pgTable, uuid, varchar, timestamp, pgEnum, integer } from "drizzle-orm/pg-core";

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
