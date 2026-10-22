import type { Metadata } from "next";
import Link from "next/link";
import { Avatar } from "@/components/ui/avatar";
import { requireSession } from "@/lib/session";
import { signOut } from "../../(auth)/actions";

export const metadata: Metadata = { title: "Profile" };

export default async function MePage() {
  const session = await requireSession();
  const { profile } = session;

  return (
    <>
      <header className="flex items-start gap-5">
        <Avatar name={profile.display_name} path={profile.avatar_path} size="lg" />
        <div className="min-w-0 flex-1">
          <h1 className="font-serif text-3xl font-medium leading-tight">{profile.display_name}</h1>
          <p className="text-grey-600">@{profile.username}</p>
          {session.email ? <p className="mt-1 truncate text-sm text-grey-600">{session.email}</p> : null}
        </div>
      </header>


      {profile.bio ? <p className="mt-6 whitespace-pre-line">{profile.bio}</p> : null}
      {profile.expertise ? (
        <p className="mt-3 text-sm text-grey-600">
          <span className="font-semibold text-ink">Knows about:</span> {profile.expertise}
        </p>
      ) : null}
      {profile.interests.length > 0 ? (
        <ul className="mt-3 flex flex-wrap gap-2" aria-label="Interests">
          {profile.interests.map((i) => (
            <li key={i} className="rounded-full bg-grey-100 px-3 py-1 text-sm">{i}</li>
          ))}
        </ul>
      ) : null}

      <p className="mt-6 text-sm text-grey-600">
        {profile.is_discoverable ? "You appear in Discover and search." : "You are hidden from Discover and search."}
      </p>

      <div className="mt-8 flex flex-col gap-3">
        <Link href="/me/edit" className="inline-flex min-h-12 items-center justify-center rounded-full bg-navy-900 px-7 font-semibold text-white">
          Edit profile
        </Link>
        <form action={signOut}>
          <button className="min-h-12 w-full rounded-full border-2 border-ink px-7 font-semibold">Sign out</button>
        </form>
      </div>
    </>
  );
}
