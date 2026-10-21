import type { Metadata } from "next";
import Link from "next/link";
import { PersonListItem } from "@/components/app/person-card";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { listPeople } from "@/lib/queries";
import { getSession } from "@/lib/session";

export const metadata: Metadata = { title: "Home" };

export default async function HomePage() {
  const session = (await getSession())!;
  const firstName = session.profile.display_name.split(" ")[0];

  const [providers, people] = await Promise.all([
    listPeople(session.supabase, session.userId, { providersOnly: true, limit: 5 }),
    listPeople(session.supabase, session.userId, { limit: 6 }),
  ]);

  return (
    <>
      <PageTitle sub="Find someone worth talking to.">Hi, {firstName}</PageTitle>

      <section aria-labelledby="providers-h" className="mb-10">
        <div className="mb-3 flex items-baseline justify-between">
          <h2 id="providers-h" className="text-lg font-semibold">Providers</h2>
          <Link href="/discover?providers=1" className="text-sm font-semibold text-navy-900 underline underline-offset-4">
            See all
          </Link>
        </div>
        {providers.error ? (
          <ErrorState what="providers" />
        ) : providers.people.length === 0 ? (
          <EmptyState
            title="No providers yet"
            body="Providers will appear here once they've been approved. Want to be one of the first?"
            action={{ href: "/create", label: "Become a provider" }}
          />
        ) : (
          <ul className="space-y-3">
            {providers.people.map((p) => (
              <PersonListItem key={p.id} person={p} />
            ))}
          </ul>
        )}
      </section>

      <section aria-labelledby="people-h">
        <div className="mb-3 flex items-baseline justify-between">
          <h2 id="people-h" className="text-lg font-semibold">New on One On One</h2>
          <Link href="/discover" className="text-sm font-semibold text-navy-900 underline underline-offset-4">
            Discover
          </Link>
        </div>
        {people.error ? (
          <ErrorState what="people" />
        ) : people.people.length === 0 ? (
          <EmptyState title="You're early" body="No one else has joined yet. Invite a friend to start the first conversation." />
        ) : (
          <ul className="space-y-3">
            {people.people.map((p) => (
              <PersonListItem key={p.id} person={p} />
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
