CREATE TYPE "public"."player_status" AS ENUM('active', 'archived', 'banned');--> statement-breakpoint
CREATE TABLE "players" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"bookie_id" uuid NOT NULL,
	"name" varchar(255) NOT NULL,
	"email" varchar(255),
	"credit_limit" integer DEFAULT 0 NOT NULL,
	"status" "player_status" DEFAULT 'active' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "players" ADD CONSTRAINT "players_bookie_id_bookies_id_fk" FOREIGN KEY ("bookie_id") REFERENCES "public"."bookies"("id") ON DELETE no action ON UPDATE no action;