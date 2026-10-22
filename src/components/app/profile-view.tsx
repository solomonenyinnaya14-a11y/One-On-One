import Link from "next/link";
import { Avatar } from "@/components/ui/avatar";
import { formatNaira } from "@/lib/format";

export type ProfileViewPerson = {
  display_name: string;
  username: string | null;
  avatar_path: string | null;
  bio: string | null;
  expertise: string | null;
  interests: string[];
};

export type ProfileViewProvider = {
  headline: string | null;
  about: string | null;
  rating_count: number;
  rating_sum: number;
  /** Shown to the owner only. */
  statusLabel?: string;
};

export type ProfileViewOffering = {
  id: string;
  kind: "text" | "voice";
  title: string;
  description: string | null;
  duration_minutes: number;
  price_minor: number;
  /** Shown to the owner only, for example "Live" or "Paused". */
  badge?: string;
};

type Props = {
  person: ProfileViewPerson;
  provider: ProfileViewProvider | null;
  offerings: ProfileViewOffering[];
  /** The owner sees their own profile the way others do, plus status. */
  isSelf?: boolean;
  email?: string | null;
  actions?: React.ReactNode;
};

/** One profile layout for everyone, so you see your own provider information the same way others do. */
export function ProfileView({ person, provider, offerings, isSelf, email, actions }: Props) {
  const rating =
    provider && provider.rating_count > 0 ? (provider.rating_sum / provider.rating_count).toFixed(1) : null;

  return (
    <article>
      <header className="flex items-start gap-5">
        <Avatar name={person.display_name} path={person.avatar_path} size="lg" />
        <div className="min-w-0 flex-1">
          <h1 className="font-serif text-3xl font-medium leading-tight">{person.display_name}</h1>
          <p className="text-grey-600">@{person.username}</p>
          {email ? <p className="mt-1 truncate text-sm text-grey-600">{email}</p> : null}
          {provider ? (
            <p className="mt-1 text-sm font-semibold text-navy-900">
              Provider
              {provider.statusLabel ? ` · ${provider.statusLabel}` : ""}
              {rating ? ` · ${rating} (${provider.rating_count} reviews)` : ""}
            </p>
          ) : null}
        </div>
      </header>

      {actions ? <div className="mt-6">{actions}</div> : null}

      {provider?.headline ? <p className="mt-8 font-serif text-xl">{provider.headline}</p> : null}
      {provider?.about || person.bio ? (
        <p className="mt-3 whitespace-pre-line text-ink">{provider?.about ?? person.bio}</p>
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

      {provider ? (
        <section aria-labelledby="offerings-h" className="mt-10">
          <div className="flex items-baseline justify-between">
            <h2 id="offerings-h" className="text-lg font-semibold">Paid conversations</h2>
            {isSelf ? (
              <Link href="/create" className="text-sm font-semibold text-navy-900 underline underline-offset-4">Manage</Link>
            ) : null}
          </div>
          {offerings.length === 0 ? (
            <p className="mt-2 text-grey-600">
              {isSelf ? "You haven't created an offering yet." : "This provider hasn't listed a conversation yet."}
            </p>
          ) : (
            <ul className="mt-3 space-y-3">
              {offerings.map((o) => (
                <li key={o.id} className="card p-4">
                  <div className="flex items-start justify-between gap-3">
                    <p className="font-semibold">{o.title}</p>
                    {o.badge ? <span className="shrink-0 rounded-full bg-grey-100 px-3 py-1 text-xs font-semibold">{o.badge}</span> : null}
                  </div>
                  <p className="text-sm text-grey-600">
                    {o.kind === "voice" ? "Voice" : "Text"} · {o.duration_minutes} min · {formatNaira(o.price_minor)}
                  </p>
                  {o.description ? <p className="mt-2 text-sm">{o.description}</p> : null}
                  {!isSelf ? (
                    <p className="mt-3 text-sm font-medium text-grey-600">Booking opens in an upcoming update.</p>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}
    </article>
  );
}
