import type { Metadata } from "next";
import Link from "next/link";
import { PersonListItem } from "@/components/app/person-card";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { listPeople, PAGE_SIZE } from "@/lib/queries";
import { sanitizeSearchTerm } from "@/lib/search";
import { requireSession } from "@/lib/session";
export const metadata: Metadata = { title: "Discover people" };
export default async function DiscoverPage({ searchParams }: { searchParams: Promise<{ q?: string; page?: string }> }) {
  const session = await requireSession(), sp = await searchParams, q = sanitizeSearchTerm(sp.q);
  const page = Math.min(Math.max(Number.parseInt(sp.page ?? "1",10) || 1,1),25);
  const { people, error } = await listPeople(session.supabase, session.userId, { q, limit: page * PAGE_SIZE });
  const params = new URLSearchParams(); if (q) params.set("q",q); params.set("page",String(page+1));
  return <>
    <PageTitle sub="Find people by name or username. Send a request to start a private chat.">Discover</PageTitle>
    <section className="mb-7 rounded-3xl bg-navy-950 p-5 text-white sm:p-7">
      <p className="text-xs font-bold uppercase tracking-[0.18em] text-navy-100">Your next conversation</p>
      <h2 className="mt-2 max-w-md font-serif text-3xl font-medium leading-tight sm:text-4xl">Someone new is one search away.</h2>
      <p className="mt-3 max-w-md text-sm leading-relaxed text-navy-100 sm:text-base">Search a username, find their profile, and send a message request. They choose whether to accept.</p>
      <form action="/discover" role="search" className="mt-5 flex gap-2 rounded-2xl bg-white p-2"><label htmlFor="q" className="sr-only">Search by name or username</label><input id="q" name="q" type="search" defaultValue={q} maxLength={40} autoComplete="off" placeholder="Try a name or @username" className="min-h-11 min-w-0 flex-1 rounded-xl border-0 bg-white px-3 text-base text-ink placeholder:text-grey-600 focus:outline-none focus:ring-2 focus:ring-navy-700" /><button className="min-h-11 shrink-0 rounded-xl bg-navy-900 px-5 text-sm font-semibold text-white transition-colors hover:bg-navy-800">Search</button></form>
    </section>
    <div className="mb-4 flex items-center justify-between gap-3"><h2 className="text-lg font-semibold">{q ? "Search results" : "People to discover"}</h2>{q ? <Link href="/discover" className="text-sm font-semibold text-navy-900 underline underline-offset-4">Clear search</Link> : null}</div>
    {error ? <ErrorState what="people" /> : people.length === 0 ? (q ? <EmptyState title="No one found" body={`Nobody matches "${q}". Try another name or username.`} /> : <EmptyState title="You're early" body="As more people join One On One, you'll find them here. Share your username with a friend to start the first conversation." />) : <>
      <ul className="space-y-3">{people.map((p) => <PersonListItem key={p.id} person={p} />)}</ul>
      {people.length >= page * PAGE_SIZE && page < 25 ? <p className="mt-6 text-center"><Link href={`/discover?${params.toString()}`} className="inline-flex min-h-11 items-center rounded-full border border-grey-300 bg-white px-6 text-sm font-semibold text-ink hover:bg-grey-50">Show more people</Link></p> : null}
    </>}
  </>;
}