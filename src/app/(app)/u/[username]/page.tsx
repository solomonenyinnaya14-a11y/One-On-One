import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { MessageButton } from "@/components/app/message-button";
import { ProfileView } from "@/components/app/profile-view";
import { getOfferings, getPersonByUsername } from "@/lib/queries";
import { requireSession } from "@/lib/session";

type Params = { params: Promise<{ username: string }> };

export const metadata: Metadata = { title: "Profile" };

export default async function PublicProfilePage({ params }: Params) {
  const { username } = await params;
  const session = await requireSession();
  if (username.toLowerCase() === session.profile.username) redirect("/me");

  const person = await getPersonByUsername(session.supabase, username);
  // Hidden, blocked, suspended and unknown accounts all look the same.
  if (!person) notFound();

  const offerings = person.provider ? await getOfferings(session.supabase, person.id) : [];

  return (
    <ProfileView
      person={person}
      provider={person.provider}
      offerings={offerings}
      actions={<MessageButton targetId={person.id} />}
    />
  );
}
