import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { MessageButton } from "@/components/app/message-button";
import { SafetyControls } from "@/components/app/safety-controls";
import { ProfileView } from "@/components/app/profile-view";
import { getPersonByUsername } from "@/lib/queries";
import { requireSession } from "@/lib/session";
type Params = { params: Promise<{ username: string }> };
export const metadata: Metadata = { title: "Profile" };
export default async function PublicProfilePage({ params }: Params) {
  const { username } = await params, session = await requireSession();
  if (username.toLowerCase() === session.profile.username) redirect("/me");
  const person = await getPersonByUsername(session.supabase, username);
  if (!person) notFound();
  return <ProfileView person={person} actions={<><MessageButton targetId={person.id} /><SafetyControls targetId={person.id} targetName={person.display_name} /></>} />;
}