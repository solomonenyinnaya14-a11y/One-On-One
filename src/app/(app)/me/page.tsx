import type { Metadata } from "next";
import Link from "next/link";
import { ProfileView } from "@/components/app/profile-view";
import { getMyOfferings, getMyProvider } from "@/lib/provider-queries";
import { offeringStatus } from "@/lib/provider-validation";
import { requireSession } from "@/lib/session";
import { signOut } from "../../(auth)/actions";

export const metadata: Metadata = { title: "Profile" };

const STATUS_LABEL: Record<string, string> = {
  draft: "Draft",
  pending_review: "Under review",
  approved: "Approved",
  rejected: "Needs changes",
  suspended: "Suspended",
};

export default async function MePage() {
  const session = await requireSession();
  const { profile } = session;
  // Same sources as the Create tab: your own provider record and ALL your offerings.
  const [{ data: isAdmin }, provider, mine] = await Promise.all([
    session.supabase.rpc("am_i_admin"),
    getMyProvider(session.supabase, session.userId),
    getMyOfferings(session.supabase, session.userId),
  ]);
  const approved = provider?.status === "approved";

  return (
    <>
      <ProfileView
        isSelf
        email={session.email}
        person={profile}
        provider={provider ? { ...provider, statusLabel: STATUS_LABEL[provider.status] } : null}
        offerings={mine.offerings.map((o) => ({ ...o, badge: offeringStatus(o, approved).label }))}
      />

      <p className="mt-6 text-sm text-grey-600">
        {profile.is_discoverable ? "You appear in Discover and search." : "You are hidden from Discover and search."}
      </p>

      <div className="mt-8 flex flex-col gap-3">
        <Link href="/me/edit" className="inline-flex min-h-12 items-center justify-center rounded-full bg-navy-900 px-7 font-semibold text-white">
          Edit profile
        </Link>
        {isAdmin ? (
          <Link href="/admin/providers" className="inline-flex min-h-12 items-center justify-center rounded-full border-2 border-ink bg-white px-7 font-semibold">
            Review provider applications
          </Link>
        ) : null}
        <form action={signOut}>
          <button className="min-h-12 w-full rounded-full border-2 border-ink px-7 font-semibold">Sign out</button>
        </form>
      </div>
    </>
  );
}
