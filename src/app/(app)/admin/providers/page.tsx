import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { ReviewButtons } from "@/components/app/provider-buttons";
import { Avatar } from "@/components/ui/avatar";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Review providers" };

type Row = {
  user_id: string;
  headline: string | null;
  about: string | null;
  languages: string[];
  submitted_at: string | null;
  profile: { display_name: string; username: string | null; avatar_path: string | null } | null;
};

export default async function AdminProvidersPage() {
  const session = await requireSession();
  // The database answers only for the caller; everyone else just sees a 404.
  const { data: isAdmin } = await session.supabase.rpc("am_i_admin");
  if (!isAdmin) notFound();

  const { data, error } = await session.supabase
    .from("provider_profiles")
    .select("user_id, headline, about, languages, submitted_at, profile:profiles!provider_profiles_user_id_fkey(display_name, username, avatar_path)")
    .eq("status", "pending_review")
    .order("submitted_at", { ascending: true });
  const rows = (data ?? []) as unknown as Row[];

  return (
    <>
      <PageTitle sub="Approving makes a provider and their offerings public.">Provider applications</PageTitle>
      {error ? (
        <ErrorState what="applications" />
      ) : rows.length === 0 ? (
        <EmptyState title="Nothing to review" body="New applications appear here when providers submit them." />
      ) : (
        <ul className="space-y-4">
          {rows.map((r) => (
            <li key={r.user_id} className="card p-5">
              <div className="flex items-center gap-3">
                <Avatar name={r.profile?.display_name ?? "Applicant"} path={r.profile?.avatar_path} />
                <div className="min-w-0">
                  <p className="truncate font-semibold">{r.profile?.display_name}</p>
                  <p className="truncate text-sm text-grey-600">@{r.profile?.username}</p>
                </div>
              </div>
              <p className="mt-4 font-serif text-lg">{r.headline}</p>
              <p className="mt-2 whitespace-pre-line text-sm">{r.about}</p>
              {r.languages.length ? <p className="mt-2 text-sm text-grey-600">Languages: {r.languages.join(", ")}</p> : null}
              <ReviewButtons userId={r.user_id} />
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
