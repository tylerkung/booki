CREATE TYPE "public"."bet_status" AS ENUM('pending', 'accepted', 'declined', 'ready_to_grade', 'graded', 'settled', 'void');--> statement-breakpoint
CREATE TYPE "public"."grade_result" AS ENUM('win', 'loss', 'push');--> statement-breakpoint
CREATE TABLE "bets" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"player_id" uuid NOT NULL,
	"event_id" uuid NOT NULL,
	"market" varchar(50) NOT NULL,
	"side" varchar(100) NOT NULL,
	"odds" integer NOT NULL,
	"stake" numeric(10, 2) NOT NULL,
	"status" "bet_status" DEFAULT 'pending' NOT NULL,
	"grade_result" "grade_result",
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "bets" ADD CONSTRAINT "bets_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;