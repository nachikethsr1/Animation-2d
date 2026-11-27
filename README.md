# ಜಿಲ್ಲಾ ತರಬೇತಿ ಸಂಸ್ಥೆ, ಬೆಂಗಳೂರು ನಗರ — Training Portal

District Training Institute, Bengaluru City — a single-page training portal
(Kannada UI) for government-officer training: feedback, a post-training
assessment, results, and digital certificates.

Everything lives in one self-contained file, `Ksgdhvsjh.html`. There is no build
step, no bundler, and no npm dependency — open the file (or serve it) and it runs.

## Backend

The portal uses [Supabase](https://supabase.com) for Postgres, Google sign-in and
private file storage.

* Project URL and the **publishable** key are at the top of `Ksgdhvsjh.html`
  (`SUPABASE_URL`, `SUPABASE_KEY`). Both are safe to ship in a page: every table
  is protected by row level security.
* The **service-role / secret key must never** be added to the page, to any other
  client file, or to this repository.
* Schema, policies, storage bucket and RPCs are defined in `supabase/migrations/`
  and are the source of truth for recreating the database.

### Tables

| table | holds |
| --- | --- |
| `profiles` | one row per account: name, KGID, designation, `role` (admin/student), `status` (`approved` on sign-up, `disabled` when an admin revokes access) |
| `trainings` | a training programme, its feedback notice, feedback questions and publish/archive flags |
| `training_questions` | the assessment paper for a training (no answer key) |
| `submissions` | one marked paper per student per training |
| `certificates` | issued certificate register (`serial` = `DTI-BNG-YYYY-NNNN`) |
| `portal_settings`, `certificate_design` | single-row settings and the certificate template |

Answer keys live in `private.training_answer_keys`. That schema is not reachable
from the browser: only the `security definer` RPCs read it.

### RPCs

* `submit_assessment(p_training_id, p_answers, p_feedback, p_official_name, p_kgid, p_email)`
  — marks the paper server-side, records the submission, mints the certificate
  serial, and returns `marks`, `percentage`, `passed`, `certificate_serial`.
* `admin_save_answer_key(p_training_id, p_answer_key)` — admin only.
* `admin_set_profile_status(p_profile_id, p_status)` — admin only.

### Storage

Bucket `certificate-assets` (private, 5 MB, `image/png` + `image/jpeg`). Approved
admins upload the certificate background there; approved accounts may read it.

## Running locally

Any static server works, e.g.:

```sh
python3 -m http.server 8000
# then open http://localhost:8000/Ksgdhvsjh.html
```

## Deploying to Netlify (static, no build)

Upload exactly these files, keeping the folder structure:

```
Ksgdhvsjh.html                     the portal
vendor/supabase-js-2.45.4.js       the Supabase browser client
_redirects                         (optional) sends / to the portal
```

`_redirects`, if you want the bare domain to work:

```
/            /Ksgdhvsjh.html   302
```

No build command, no environment variables, no server. Do **not** publish the
repository root as-is: `README.md` and `supabase/migrations/*.sql` have no reason
to be public.

### About the vendored client

`vendor/supabase-js-2.45.4.js` is the unmodified npm build
`@supabase/supabase-js@2.45.4/dist/umd/supabase.js`
(sha256 `8596965fe918e656600a1b568d3a168f5c0d3d22a600886bb6f44a6555db01e7`,
110,797 bytes). It exposes `window.supabase`.

It is a plain `<script>` in `<head>` — deliberately **not** `defer`/`async`, so
`window.supabase` exists before the inline app script runs. (The earlier CDN tag
was both deferred *and* pointed at `dist/umd/supabase.min.js`, a file that does
not exist in that version, which is why the portal reported that the client had
not loaded.)

If the local file is missing, the page tries jsDelivr and then unpkg, and only
then shows an error that names `vendor/supabase-js-2.45.4.js` and lists every
URL it tried. To upgrade, drop a newer `dist/umd/supabase.js` in as
`vendor/supabase-js-<version>.js` and update the `<script src>` and the CDN
fallback URLs in `SECTION B.2a`.

## Google sign-in setup (one-time)

Sign-in is a plain OAuth redirect: browser → Supabase → Google → Supabase → back
to this page. Two consoles are involved.

**1. Google Cloud Console** — APIs & Services → Credentials → *Create credentials*
→ *OAuth client ID* → type **Web application**:

| field | value |
| --- | --- |
| Authorized redirect URI | `https://yjqfaexhoxbunnaydkdx.supabase.co/auth/v1/callback` |
| Authorized JavaScript origin (optional for this flow) | the page's origin, e.g. `http://localhost:8000` |

The redirect URI is the Supabase callback, **not** this page — Google returns to
Supabase, and Supabase returns to the page. Copy the resulting **Client ID** and
**Client secret**.

**2. Supabase Dashboard** — Authentication → Sign In / Providers → **Google**:
enable it and paste the Client ID and Client secret. Supabase stores the secret
(encrypted, server side). It must never be written into this repository or into
`Ksgdhvsjh.html`.

**3. Supabase Dashboard** — Authentication → URL Configuration:

* **Site URL**: the deployed site (or `http://localhost:8000` while developing)
* **Redirect URLs**: the page itself, e.g. `http://localhost:8000/Ksgdhvsjh.html`
  — wildcards such as `http://localhost:8000/**` also work. `signInGoogle()`
  sends `location.origin + location.pathname` as `redirectTo`, so this exact
  URL has to be allowed or Supabase falls back to the Site URL.

Consent screen scopes are only `openid`, `email`, `profile` — all non-sensitive,
so no Google verification review is needed. While the app is in *Testing* only
listed test users can sign in; publish it when the real users arrive.

## Accounts

There is no approval step. A Google sign-in creates a `profiles` row with
`status = 'approved'` (the `on_auth_user_created` trigger in
`20261127083858_auto_approve_new_signups.sql`), the student fills in name / KGID /
designation / department on the first visit, and the portal opens immediately.

The administrator keeps a kill switch instead: **Admin → Student accounts** can
disable an account (`status = 'disabled'`) and re-enable it. A disabled account is
blocked at the gate and by every policy that calls `is_approved()`. Row level
security still scopes each student to their own submission and certificate rows.

Restoring the old behaviour is a one-line change to the trigger
(`'approved'` → `'pending'` in `handle_new_user`); the gate in the page still
handles `status = 'rejected'` / `'disabled'`.

## Feedback

The feedback stage is part 1 (session ratings) + part 2 (questions), and the admin
editor controls both:

* **ಪ್ರತಿಕ್ರಿಯೆ ಮುನ್ನ ಸೂಚನೆ (Notice)** — an optional free-text notice, saved in
  `trainings.feedback_notice`. When it is set, the student sees it in a highlighted
  card at the very top of the feedback stage, before the session ratings. Line
  breaks are kept (`white-space:pre-line`).
* **Feedback questions** — each one is either a four-option choice (radio) or a
  free-text answer. A radio question must have all four options filled, and the
  student is asked for one answer per question before the stage can advance.

`trainings.feedback_notice` was added by
`supabase/migrations/20261127092431_feedback_notice.sql` (with the same
column-level grants as the rest of the table). An older project that has not been
migrated yet still saves trainings: the page retries the write without the notice
and tells the admin that the notice was not stored.

## Applying the migrations

Migrations are plain SQL, named for their applied version. On a fresh project they
can be run in order with the Supabase CLI:

```sh
supabase link --project-ref <project-ref>
supabase db push
```

They are byte-identical to the migrations applied to the live project.
