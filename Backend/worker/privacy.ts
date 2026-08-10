/**
 * The privacy policy, as a page.
 *
 * The same policy is in the app under Settings → Privacy, which is where a
 * person actually reads it. This exists because a URL is a separate
 * requirement: App Store Connect asks for one, and an app that reads HealthKit
 * and sends a photograph to a third party is the kind Apple checks for it.
 *
 * Served outside the API and before the auth middleware — a policy behind a
 * bearer token is not a published policy. Every claim here is one the code can
 * be checked against: there is no analytics SDK, no location, no advertising
 * identifier and no third-party dependency in the app beyond `ShamanCore`,
 * which is this repository.
 */

/** The one date on the page, so it cannot drift between the two mentions. */
const UPDATED = "10 August 2026";
const CONTACT = "maximkadocnikov@gmail.com";

const page = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>eatsome — Privacy Policy</title>
<style>
  :root { color-scheme: light dark; --ink: #14202e; --muted: #5b6b7d; --bg: #f6f8fb; --card: #fff; }
  @media (prefers-color-scheme: dark) {
    :root { --ink: #e8eef5; --muted: #9aa9b8; --bg: #0d141c; --card: #131c26; }
  }
  body {
    margin: 0; padding: 32px 20px 72px; background: var(--bg); color: var(--ink);
    font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  }
  main { max-width: 40rem; margin: 0 auto; }
  h1 { font-size: 1.8rem; line-height: 1.2; margin: 0 0 6px; }
  h2 { font-size: 1.15rem; margin: 34px 0 8px; }
  p, li { color: var(--ink); }
  .updated { color: var(--muted); font-size: 0.95rem; margin: 0 0 28px; }
  section { background: var(--card); border-radius: 16px; padding: 2px 22px 18px; margin-bottom: 14px; }
  a { color: #2f6df6; }
  footer { color: var(--muted); font-size: 0.9rem; margin-top: 28px; }
</style>
</head>
<body>
<main>
  <h1>eatsome — Privacy Policy</h1>
  <p class="updated">Last updated ${UPDATED}. eatsome is a beta distributed through TestFlight.</p>

  <section>
    <h2>Your account</h2>
    <p>eatsome requires Sign in with Apple. It receives Apple's account-specific identifier and, only
    if you choose to share it, your email address. It does not receive or store your Apple password.
    The app also generates a random identifier for the installation so existing history on that phone
    can be joined to your account. A shared app credential cannot access account data by itself.</p>
  </section>

  <section>
    <h2>What is stored, and where</h2>
    <ul>
      <li><strong>Meal photographs.</strong> A photograph stays on your device and a copy is stored in
      eatsome's private Cloudflare R2 bucket, so a failed reading or a retry does not need a second
      upload. The bucket is not public.</li>
      <li><strong>Your meal log.</strong> Meals, corrections and the answers you give are appended to a
      log on the device and synced to eatsome's backend under your account. The log is
      append-only: a correction is a new entry rather than an edit.</li>
      <li><strong>Recognition results.</strong> What the model returned for a photograph is kept so a
      reading can be explained and compared later.</li>
    </ul>
  </section>

  <section>
    <h2>Photographs and AI recognition</h2>
    <p>Before the first meal description or photograph leaves the device, the app shows a consent
    screen that names the AI provider that will process it. Nothing is sent for recognition until you
    agree. Typed or dictated words, and any photograph you attach, are sent for one purpose:
    identifying the foods and estimating what they weigh. eatsome does not add your photographs to
    its research corpus unless you separately opt in.</p>
    <p>The providers used for recognition are Google (Gemini) and OpenAI, depending on the build.
    Hosting, storage and the database are Cloudflare. No one else receives your data.</p>
  </section>

  <section>
    <h2>Health data is read only</h2>
    <p>With your permission, eatsome reads workouts, sleep and body weight from Apple Health to show a
    daily overview and to size a protein target. That data is read on the device, is never copied into
    the meal log, is never uploaded to eatsome's backend or to any AI provider, and is never written
    back to Health. Refusing Health access leaves the rest of the app fully usable.</p>
  </section>

  <section>
    <h2>What eatsome does not collect</h2>
    <p>No advertising, no advertising identifier, no analytics or crash-reporting SDK, no location, no
    contacts, no tracking across other apps or websites. The app contains no third-party SDKs. Your
    data is never sold and never shared for anyone else's marketing.</p>
  </section>

  <section>
    <h2>Deleting your data</h2>
    <p>Deleting a meal removes its entry and, when no other meal refers to the same photograph, the
    cloud copy of the photograph too. Settings → Privacy → <em>Delete all cloud data</em> erases the
    stored photographs, meal events, recognition results, table content, account identities, sessions
    and research-corpus consent held for your account, and withdraws consent for photo processing.
    The local meal log remains on the phone but is locked until you authenticate an account again.
    Signing out removes this phone's local account session.</p>
  </section>

  <section>
    <h2>Children</h2>
    <p>eatsome is not directed at children and is not intended for use by children under 13.</p>
  </section>

  <section>
    <h2>Contact</h2>
    <p>Questions, or a request to delete data you can no longer reach from the app:
    <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>
  </section>

  <footer>Changes to this policy are published on this page with a new date above.</footer>
</main>
</body>
</html>
`;

/**
 * The policy for any request that asks for it, and `null` for everything else
 * so the caller can fall through to the API. Returning null rather than a 404
 * keeps the one route table in `index.ts`.
 */
export function privacyPage(request: Request): Response | null {
  const path = new URL(request.url).pathname.replace(/\/+$/, "");
  if (path !== "/privacy") return null;
  return new Response(page, {
    headers: {
      "content-type": "text/html; charset=UTF-8",
      // A minute, not an hour. At `max-age=3600` a deploy left edge caches
      // serving the previous policy for up to an hour afterwards — one request
      // in six, in the window where an App Review reviewer is the likeliest
      // reader. This page is a few kilobytes off a Worker that is already
      // running; there was never anything to save here.
      "cache-control": "public, max-age=60",
    },
  });
}
