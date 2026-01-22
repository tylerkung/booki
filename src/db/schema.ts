import { pgTable, uuid, varchar, timestamp, pgEnum } from "drizzle-orm/pg-core";

// Subscription status enum for bookies
export const subscriptionStatusEnum = pgEnum("subscription_status", [
  "active",
  "inactive",
  "trial",
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
