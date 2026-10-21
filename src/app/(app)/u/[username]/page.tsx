import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { FollowButton } from "@/components/app/follow-button";
import { Avatar } from "@/components/ui/avatar";
import { formatCount, formatNaira } from "@/lib/format";
import { getOfferings, getPersonByUsername, getStats } from "@/lib/queries";
import { getSession } from "@/lib/session";

type Params = { params: Promise<{ username: string }> };

export const metadata: Metadata = { title: "Profile" };

export default async function PublicProfilePage({ params }: Params) {
  const { username } = await params;
  const session = (await getSession())!;
  if (username.toLowerCase() === session.profile.username) redirect("/me");

  const person = await getPersonByUsername(session.supabase, username);
  // Hidden, blocked, suspended and unknown accounts all look the same.
  if (!person) notFound();

  const [stats, offerings] = await Promise.all([
    getStats(session.supabase, person.id),
    person.provider ? getOfferings(session.supabase, person.id) : Promise.resolve([]),
  ]);
  const rating =
    person.provider && person.provider.rating_count > 0
      ? (person.provider.rating_sum / person.provider.rating_count).toFixed(1)
      : null;

  return (
    <article>
      <header className="flex items-start gap-5">
        <Avatar name={person.display_name} path={person.avatar_path} size="lg" />
        <div className="min-w-0 flex-1">
          <h1 className="font-serif text-3xl font-medium leading-tight">{person.display_name}</h1>
          <p className="text-grey-600">@{person.username}</p>
          {person.provider ? (
            <p className="mt-1 text-sm font-semibold text-navy-900">
              Provider{rating ? ` · ${rating} (${person.provider.rating_count} reviews)` : ""}
            </p>
          ) : null}
        </div>
      </header>

      <dl className="mt-6 flex gap-8">
        <div>
          <dt className="text-sm text-grey-600">Followers</dt>
          <dd className="text-xl font-semibold">{formatCount(stats.follower_count)}</dd>
        </div>
        <div>
          <dt className="text-sm text-grey-600">Following</dt>
          <dd className="text-xl font-semibold">{formatCount(stats.following_count)}</dd>
        </div>
      </dl>

      <div className="mt-6">
        <FollowButton targetId={person.id} username={person.username!} following={stats.viewer_follows} />
      </div>

      {person.provider?.headline ? (
        <p className="mt-8 font-serif text-xl">{person.provider.headline}</p>
      ) : null}
      {person.provider?.about || person.bio ? (
        <p className="mt-3 whitespace-pre-line text-ink">{person.provider?.about ?? person.bio}</p>
      ) : null}
      {person.expertise ? (
        <p className="mt-4 text-sm text-grey-600">
          <span className="font-semibold text-ink">Knows about:</span> {person.expertise}
        </p>
      ) : null}
      {person.interests.length > 0 ? (
        <ul className="mt-4 flex flex-wrap gap-2" aria-label="Interests">
          {person.interests.map((i) => (
            <li key={i} className="rounded-full bg-grey-100 px-3 py-1 text-sm">{i}</li>
          ))}
        </ul>
      ) : null}

      {person.provider ? (
        <section aria-labelledby="offerings-h" className="mt-10">
          <h2 id="offerings-h" className="text-lg font-semibold">Paid conversations</h2>
          {offerings.length === 0 ? (
            <p className="mt-2 text-grey-600">This provider hasn&apos;t listed a conversation yet.</p>
          ) : (
            <ul className="mt-3 space-y-3">
              {offerings.map((o) => (
                <li key={o.id} className="rounded-2xl border border-grey-200 p-4">
                  <p className="font-semibold">{o.title}</p>
                  <p className="text-sm text-grey-600">
                    {o.kind === "voice" ? "Voice" : "Text"} · {o.duration_minutes} min · {formatNaira(o.price_minor)}
                  </p>
                  {o.description ? <p className="mt-2 text-sm">{o.description}</p> : null}
                  <p className="mt-3 text-sm font-medium text-grey-600">
                    Booking opens in an upcoming update.
                  </p>
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}
    </article>
  );
}
