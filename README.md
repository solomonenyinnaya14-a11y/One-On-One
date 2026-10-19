# One On One

A marketplace where people discover and pay other people for one-to-one text or voice conversations.

**Status:** foundation and public landing page only. Accounts, profiles, discovery, bookings, payments and voice are not built yet. `/explore` and `/become-a-provider` are honest "not open yet" pages.

## Stack

- Next.js (App Router) and TypeScript
- Tailwind CSS v4, design tokens in `src/app/globals.css`
- Supabase (auth, Postgres, storage): project `One-On-One`, ref `vjebivcrhtaeqeofqlli`
- Vercel project `one-on-one`, deployed from this repository
- Vitest and Testing Library

One On One is fully separate from Gista: its own repository, Supabase project and Vercel project.

## Getting started

Requires Node 20.9 or newer.

```bash
npm install
cp .env.example .env.local   # then fill in the values
npm run dev
```

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Start the dev server |
| `npm run lint` | ESLint |
| `npm run typecheck` | TypeScript, no emit |
| `npm test` | Unit and component tests |
| `npm run build` | Production build |
| `npm run check` | All of the above, in order |

CI (`.github/workflows/ci.yml`) runs lint, typecheck, tests and build on every push to `main` and `feat/**`, and on pull requests.

## Environment variables

See `.env.example`. Only values prefixed `NEXT_PUBLIC_` reach the browser. `SUPABASE_SECRET_KEY` and any payment or voice secrets are server-only and must never be committed or imported in client code.

| Variable | Scope | Required now |
|---|---|---|
| `NEXT_PUBLIC_SITE_URL` | public | optional (defaults to localhost) |
| `NEXT_PUBLIC_SUPABASE_URL` | public | not yet used |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | public | not yet used |
| `SUPABASE_SECRET_KEY` | server only | not yet used |

## Design system

- Navy `#0b2559` is the brand colour, black is for text, white is the background, and neutral greys handle borders, secondary text and surfaces. Purple is not used.
- Headlines use Newsreader, body text uses Hanken Grotesk.
- Buttons are pill-shaped with at least 48px touch height; keyboard focus is always visible; motion respects `prefers-reduced-motion`.
- The landing-page illustration uses grey bars, never invented messages, people, ratings or testimonials.

## Structure

```
src/
  app/            routes, layout, global styles
  components/     shared UI (header, footer, buttons, illustration)
  lib/            site copy and route constants
```

## Working agreements

- Work happens on feature branches; nothing merges to `main` or ships to production without the product owner's approval.
- Row Level Security, server-side authorization and server-verified payments are required for every feature that touches data or money.
