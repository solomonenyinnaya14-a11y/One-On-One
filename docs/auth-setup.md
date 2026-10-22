# Supabase Auth setup for email links (Preview and Production)

The app confirms email and resets passwords through `/auth/confirm`, which
verifies a `token_hash`. This works even when the email link is opened in a
different browser from the one used to sign up (Safari -> Chrome on iPhone).

## Authentication -> URL Configuration
- **Site URL**: the stable app URL (production domain once approved; until then a stable Preview alias).
- **Redirect URLs** (allow-list), add:
  - `https://one-on-*-solomonenyinnaya14-a11ys-projects.vercel.app/**`
  - `https://one-on-one-git-feat-foundation-landing-solomonenyinnaya14-a11ys-projects.vercel.app/**`

## Authentication -> Email Templates
**Confirm signup** link:
```
<a href="{{ .RedirectTo }}&token_hash={{ .TokenHash }}&type=signup">Confirm your email</a>
```
**Reset password** link:
```
<a href="{{ .RedirectTo }}&token_hash={{ .TokenHash }}&type=recovery">Reset your password</a>
```
`{{ .RedirectTo }}` is the app's `/auth/confirm?next=...` URL, so the link returns to the same deployment that sent it.
