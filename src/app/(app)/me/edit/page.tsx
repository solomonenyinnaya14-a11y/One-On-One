import type { Metadata } from "next";
import Link from "next/link";
import { updateProfile } from "@/app/(app)/actions";
import { AvatarUploader } from "@/components/app/avatar-uploader";
import { ProfileForm } from "@/components/app/profile-form";
import { PageTitle } from "@/components/app/states";
import { getSession } from "@/lib/session";

export const metadata: Metadata = { title: "Edit profile" };

export default async function EditProfilePage() {
  const session = (await getSession())!;
  const { profile } = session;
  return (
    <>
      <p className="mb-2">
        <Link href="/me" className="text-sm font-semibold text-navy-900 underline underline-offset-4">
          ← Profile
        </Link>
      </p>
      <PageTitle>Edit profile</PageTitle>
      <div className="mb-8">
        <AvatarUploader userId={session.userId} name={profile.display_name} path={profile.avatar_path} />
      </div>
      <ProfileForm action={updateProfile} profile={profile} mode="edit" />
    </>
  );
}
