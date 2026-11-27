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
| `profiles` | one row per account: name, KGID, designation, `role` (admin/student), `status` (pending/approved/rejected/disabled) |
| `trainings` | a training programme, its feedback questions and publish/archive flags |
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

Nobody can sign themselves in: a first Google sign-in creates a `profiles` row with
`status = 'pending'`, the student fills in name / KGID / designation / department,
and an administrator approves the account before any training is visible.

## Applying the migrations

Migrations are plain SQL, named for their applied version. On a fresh project they
can be run in order with the Supabase CLI:

```sh
supabase link --project-ref <project-ref>
supabase db push
```

They are byte-identical to the migrations applied to the live project.
