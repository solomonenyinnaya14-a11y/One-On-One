import type { Metadata } from "next";
import Link from "next/link";
import { PersonListItem } from "@/components/app/person-card";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { listPeople, PAGE_SIZE } from "@/lib/queries";
import { sanitizeSearchTerm } from "@/lib/search";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Discover" };

export default async function DiscoverPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; providers?: string; page?: string }>;
}) {
  const session = await requireSession();
  const sp = await searchParams;
  const q = sanitizeSearchTerm(sp.q);
  const providersOnly = sp.providers === "1";
  const page = Math.min(Math.max(Number.parseInt(sp.page ?? "1", 10) || 1, 1), 25);

  const { people, error } = await listPeople(session.supabase, session.userId, {
    q,
    providersOnly,
    limit: page * PAGE_SIZE,
  });

  const params = new URLSearchParams();
  if (q) params.set("q", q);
  if (providersOnly) params.set("providers", "1");
  const withParams = (extra: Record<string, string>, drop: string[] = []) => {
    const next = new URLSearchParams(params);
    for (const k of drop) next.delete(k);
    for (const [k, v] of Object.entries(extra)) next.set(k, v);
    const s = next.toString();
    return s ? `/discover?${s}` : "/discover";
  };

  return (
    <>
      <PageTitle>Discover</PageTitle>

      <form action="/discover" role="search" className="mb-4 flex gap-2">
        {providersOnly ? <input type="hidden" name="providers" value="1" /> : null}
        <label htmlFor="q" className="sr-only">Search by name or username</label>
        <input
          id="q"
          name="q"
          type="search"
          defaultValue={q}
          maxLength={40}
          placeholder="Search by name or username"
          className="min-h-12 min-w-0 flex-1 rounded-full border-2 border-grey-200 bg-paper px-5 text-base placeholder:text-grey-300"
        />
        <button className="min-h-12 shrink-0 rounded-full bg-navy-900 px-6 font-semibold text-white">Search</button>
      </form>

      <div className="mb-6 flex gap-2" role="group" aria-label="Filter">
        <Link
          href={withParams({}, ["providers", "page"])}
          aria-current={!providersOnly ? "true" : undefined}
          className={`rounded-full px-4 py-2 text-sm font-semibold ${!providersOnly ? "bg-ink text-white" : "border border-grey-200 text-ink"}`}
        >
          Everyone
        </Link>
        <Link
          href={withParams({ providers: "1" }, ["page"])}
          aria-current={providersOnly ? "true" : undefined}
          className={`rounded-full px-4 py-2 text-sm font-semibold ${providersOnly ? "bg-ink text-white" : "border border-grey-200 text-ink"}`}
        >
          Providers
        </Link>
      </div>

      {error ? (
        <ErrorState what="people" />
      ) : people.length === 0 ? (
        q ? (
          <EmptyState title="No one found" body={`Nobody matches "${q}". Try a different name or username.`} />
        ) : providersOnly ? (
          <EmptyState title="No providers yet" body="Approved providers will be listed here." />
        ) : (
          <EmptyState title="Nobody here yet" body="As people join and finish setting up, they'll appear here." />
        )
      ) : (
        <>
          <ul className="space-y-3">
            {people.map((p) => (
              <PersonListItem key={p.id} person={p} />
            ))}
          </ul>
          {people.length >= page * PAGE_SIZE && page < 25 ? (
            <p className="mt-6 text-center">
              <Link
                href={withParams({ page: String(page + 1) })}
                className="inline-flex min-h-12 items-center rounded-full border-2 border-ink px-7 font-semibold"
              >
                Show more
              </Link>
            </p>
          ) : null}
        </>
      )}
    </>
  );
}
