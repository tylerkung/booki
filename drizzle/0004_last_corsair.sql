CREATE TYPE "public"."event_status" AS ENUM('scheduled', 'live', 'final');--> statement-breakpoint
CREATE TYPE "public"."market_type" AS ENUM('spread', 'total', 'moneyline');--> statement-breakpoint
CREATE TABLE "events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"sport" varchar(100) NOT NULL,
	"league" varchar(100) NOT NULL,
	"home_team" varchar(255) NOT NULL,
	"away_team" varchar(255) NOT NULL,
	"start_time" timestamp with time zone NOT NULL,
	"status" "event_status" DEFAULT 'scheduled' NOT NULL,
	"final_score" varchar(50),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "markets" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"event_id" uuid NOT NULL,
	"type" "market_type" NOT NULL,
	"side_a" varchar(100) NOT NULL,
	"side_b" varchar(100) NOT NULL,
	"odds_a" integer NOT NULL,
	"odds_b" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "markets" ADD CONSTRAINT "markets_event_id_events_id_fk" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE no action ON UPDATE no action;