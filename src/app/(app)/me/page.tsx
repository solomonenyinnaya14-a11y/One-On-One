import type { Metadata } from "next";
import Link from "next/link";
import { ProfileView } from "@/components/app/profile-view";
import { requireSession } from "@/lib/session";
import { signOut } from "../../(auth)/actions";
export const metadata: Metadata = { title: "Profile" };
export default async function MePage() {
  const session = await requireSession(), { profile } = session;
  return <><ProfileView isSelf email={session.email} person={profile} /><p className="mt-5 text-sm text-grey-600">{profile.is_discoverable ? "Your profile is visible in Discovery and username search." : "Your profile is hidden from Discovery and username search."}</p><div className="mt-6 flex flex-col gap-3"><Link href="/me/edit" className="inline-flex min-h-12 items-center justify-center rounded-full bg-navy-900 px-7 font-semibold text-white transition-colors hover:bg-navy-800">Edit profile</Link><form action={signOut}><button className="min-h-12 w-full rounded-full border border-grey-300 bg-white px-7 font-semibold transition-colors hover:bg-grey-50">Sign out</button></form></div></>;
}