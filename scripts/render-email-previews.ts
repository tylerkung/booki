/**
 * Render the follow-up email variants to landing/ as browser-previewable HTML.
 *
 *   deno run --allow-read --allow-write scripts/render-email-previews.ts
 *
 * The previews are GENERATED from the edge function's own template rather than
 * hand-copied. CLAUDE.md warns that landing/email-*.html are copies which are
 * not read at send time, so an edit to one silently diverges from the other.
 * These two cannot: regenerate and they match the shipped copy by construction.
 */
const SOURCE = "supabase/functions/send_followup_email/index.ts";

const src = await Deno.readTextFile(SOURCE);
const start = src.indexOf("function getFollowupEmailHtml");
const end = src.indexOf("\nDeno.serve", start);
if (start === -1 || end === -1) {
  console.error(`Could not locate getFollowupEmailHtml in ${SOURCE}`);
  Deno.exit(1);
}

const mod = `${src.slice(start, end)}
export { getFollowupEmailHtml };
`;
const tmp = await Deno.makeTempFile({ suffix: ".ts" });
await Deno.writeTextFile(tmp, mod);
const { getFollowupEmailHtml } = await import(`file://${tmp}`);
await Deno.remove(tmp);

const variants: Array<[string, string, number]> = [
  // name, output file, invites already created
  ["Brian", "landing/email-apology.html", 4],
  ["Andrew", "landing/email-standard.html", 0],
];
for (const [name, path, invites] of variants) {
  await Deno.writeTextFile(path, getFollowupEmailHtml(name, invites));
  console.log(`${path}  (invites_created=${invites})`);
}
