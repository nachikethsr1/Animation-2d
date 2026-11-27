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
| `trainings` | a training programme: title, start/end dates, feedback notice, ಭಾಗ-1/ಭಾಗ-2 questions, publish flag and the `archived` soft-delete flag |
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

## Training management

The administrator edits one training at a time in
**Admin → ತರಬೇತಿ ನಿರ್ವಹಣೆ → ಸಂಪಾದಿಸಿ**. The form now carries only what the
institute asked for:

| field | notes |
| --- | --- |
| ತರಬೇತಿ ಶೀರ್ಷಿಕೆ (Training Title) | the official name everywhere, including the certificate designer (`Training Name`) |
| ತರಬೇತಿ ಆರಂಭ ದಿನಾಂಕ / ಅಂತ್ಯ ದಿನಾಂಕ | start and end dates (`trainings.start_date` / `end_date`, ISO) |
| ಉತ್ತೀರ್ಣ ಶೇಕಡಾವಾರು | unchanged, used by the MCQ marking RPC |
| ಥೀಮ್ ಬಣ್ಣ | unchanged |
| ಭಾಗ-1 / ಭಾಗ-2 / MCQ editors | see below |

Training Topic, Training Description, Training Category and the whole session
management block (Add Session / Session Title / Session Heading / Session
Content / Session Teachers) were removed from the interface. The old columns
(`topic`, `description`, `category`, `feedback_sessions`, `feedback_questions`)
are **not dropped** and their rows are **not rewritten**: the page keeps them in
the database, still reads them for old records, and never sends them in an
update. The legacy single `date` column also stays, and is kept in step
(`start – end`) so older reports and `certificates.training_date` stay readable.

Deleting a training is now a soft delete: it sets `archived = true` (the row,
its questions, submissions and certificates stay put) and the training appears
under **ಅಳಿಸಿದ ತರಬೇತಿಗಳು** with *ಮರುಸ್ಥಾಪಿಸಿ* (restore) and *ಶಾಶ್ವತವಾಗಿ ಅಳಿಸಿ*
(permanent delete). A permanent delete is refused by the database while
submissions still reference the training, which protects the register.

## Feedback — ಭಾಗ-1 + ಭಾಗ-2

The feedback stage has two Kannada sections, managed independently of the MCQ
assessment. Both live in the training's own row, so every training has its own
questionnaire.

**ಭಾಗ-1 — ದಿನದ ಹಿಮ್ಮಾಹಿತಿ.** A list of large CSS question blocks. Each block
holds, in this order:

1. ದಿನ — a small input inside the block, with the seven Kannada weekdays offered
   by a `<datalist>`;
2. ದಿನಾಂಕ — a date input;
3. three lines of visual spacing;
4. ಅಧಿವೇಶನ (ಆರಂಭ – ಅಂತ್ಯ) — the session range, e.g. 1–3;
5. ವಿಷಯ — a wide single-line subject input;
6. ಮುಖ್ಯ ಪ್ರಶ್ನೆ — a large multi-line question editor;
7. ಉಪನ್ಯಾಸಕರು — the lecturer's name.

Day, date and session range each carry a **ಒಂದಕ್ಕೆ (Edit for One) /
ಎಲ್ಲಕ್ಕೂ (Edit for All)** switch. With *Edit for All* typed values are copied to
every other block (the whole range for sessions); with *Edit for One* only that
block changes. Subject, main question and lecturer are always edited directly,
and the switch is not offered for them. Blocks can be added, deleted (soft),
restored and permanently removed, and the layout reflows automatically.

The participant sees each block as a styled card (day, date, session range,
subject, question, lecturer) with the four approval levels
(ಅತ್ಯುತ್ತಮ / ಉತ್ತಮ / ತೃಪ್ತಿಕರ / ಸಾಧಾರಣ) to rate it.

**ಭಾಗ-2 — ತರಬೇತಿ ಉಪಯುಕ್ತತೆ ಕುರಿತು ಹಿಮ್ಮಾಹಿತಿ.** The eight institute questions
are preloaded with exactly the wording and options supplied. Each question has a
format the administrator can change:

| format | editor | participant |
| --- | --- | --- |
| ಆಯ್ಕೆ (choice) | any number of options (2–10), each editable | one choice |
| ರೇಟಿಂಗ್ (rating) | its own scale, any number of points, editable labels | round rating chips |
| ವಿವರಣಾತ್ಮಕ (descriptive) | no options at all | a large free-text box |

Questions can be reordered, edited, deleted (soft), restored and permanently
removed; option counts are per question, never hard-coded. Completing every
active question (and every ಭಾಗ-1 block) is required before the MCQ stage opens.

**ಪ್ರತಿಕ್ರಿಯೆ ಮುನ್ನ ಸೂಚನೆ (Notice)** — an optional free-text notice, saved in
`trainings.feedback_notice`, shown in a highlighted card above the feedback.

## Certificate designer

The manual designer (upload a PNG/JPG background, drag labels, set size,
colour and alignment, save) is unchanged. The automatic labels are now exactly:

1. Student Name — participant profile / submission
2. Designation — participant profile / submission
3. KGID Number — participant profile / submission
4. Training Start Date — `trainings.start_date`
5. Training End Date — `trainings.end_date`
6. Training Name — `trainings.title`

Old automatic labels (Training Topic, Training Date, Marks, Total Marks,
Percentage, Certificate ID, Email, Institute Name) are gone from the picker.
A saved design is sanitised when it is read: `Training Date` becomes *Training
Start Date*, `Training Title` becomes *Training Name*, and the remaining
outdated labels are dropped, so an old design keeps working. Hand-placed static
text (headings such as "This is to certify that") is kept — it carries no data.
The canvas previews a real participant and training, both switchable from the
panel, which makes checking label positions straightforward.

`trainings.start_date`, `end_date`, `feedback_version`, `feedback_part1` and
`feedback_part2` are added by
`supabase/migrations/20261127120000_training_system_feedback_v2.sql`. That
migration also backfills the two dates from the legacy free-text `date`. A
project that has not run it yet still saves: the page retries the write in the
legacy shape (the two sections go into `feedback_sessions` / `feedback_questions`,
which are read back by shape), so no work is lost.

## Participant details and Designation

The details stage and the first-sign-in form both use **Designation**
(`profiles.designation`); the old "Position" wording is gone. The details stage
asks for e-mail, name, KGID and designation, and the designation is written back
to the participant's own profile through the one column the student role may
update. `submit_assessment` already copies `profiles.designation` into
`submissions.designation` when the paper is marked — that column was simply not
being displayed before — so the certificate always has the designation without
any change to the marking RPC.

## Applying the migrations

Migrations are plain SQL, named for their applied version. On a fresh project they
can be run in order with the Supabase CLI:

```sh
supabase link --project-ref <project-ref>
supabase db push
```

They are byte-identical to the migrations applied to the live project.
