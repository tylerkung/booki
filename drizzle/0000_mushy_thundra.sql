CREATE TYPE "public"."subscription_status" AS ENUM('active', 'inactive', 'trial');--> statement-breakpoint
CREATE TABLE "bookies" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" varchar(255) NOT NULL,
	"name" varchar(255) NOT NULL,
	"subscription_status" "subscription_status" DEFAULT 'trial' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "bookies_email_unique" UNIQUE("email")
);
