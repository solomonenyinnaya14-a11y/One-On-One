# One On One

One On One is a messaging-first application for discovering people, sending message requests, and chatting privately after the recipient accepts.

**MVP scope:** account registration, user profiles, username search, Discovery, incoming and outgoing message requests, private text messaging, and a persistent Messages inbox.

**Explicitly deferred:** paid conversations, booking and scheduling, provider subscriptions, services, commissions, payments, earnings, withdrawals, and video calling. Existing marketplace database objects are retained for possible future use, but the MVP UI does not expose those features.

## Stack
- Next.js App Router and TypeScript
- Tailwind CSS v4, design tokens in `src/app/globals.css`
- Supabase Auth, Postgres, Row Level Security, and Realtime
- Supabase project `One-On-One`, ref `vjebivcrhtaeqeofqlli`
- Vercel project `one-on-one`
- Vitest and Testing Library

One On One is separate from Gista: its own repository, Supabase project, and Vercel project.

## Core user flow
1. Sign up and set a username.
2. Discover people or search by username.
3. Open a profile and send a message request.
4. The recipient accepts or declines the request.
5. Once accepted, both people can continue a private text conversation.
6. Accepted conversations and message history remain in Messages.

## Local development
Requires Node 20.9 or newer.
```bash
npm install
cp .env.example .env.local
# Fill in the Supabase values from the One On One project.
npm run check
npm run dev
```

## Safety and implementation notes
- The recipient must accept a message request before the conversation becomes an accepted chat.
- Message limits and access checks must be enforced by database functions and Row Level Security, not only by the UI.
- Do not use real payments or expose marketplace routes in the messaging-first MVP.
- Do not seed fake users or conversations in a live environment.