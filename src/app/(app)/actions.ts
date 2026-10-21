"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { isOwnAvatarPath } from "@/lib/avatar";
import type { FormState } from "@/lib/form-state";
import { getSession } from "@/lib/session";
import {
  normalizeUsername,
  parseInterests,
  validateBio,
  validateDisplayName,
  validateUsername,
} from "@/lib/validation";

function text(form: FormData, key: string): string {
  const v = form.get(key);
  return typeof v === "string" ? v : "";
}

type ProfileFields = {
  fieldErrors: Record<string, string>;
  update: Record<string, unknown>;
};

function readProfileFields(form: FormData, withPrivacy: boolean): ProfileFields {
  const fieldErrors: Record<string, string> = {};
  const username = normalizeUsername(text(form, "username"));
  const displayName = text(form, "display_name").trim();
  const bio = text(form, "bio").trim();
  const expertise = text(form, "expertise").trim();

  const usernameError = validateUsername(username);
  if (usernameError) fieldErrors.username = usernameError;
  const nameError = validateDisplayName(displayName);
  if (nameError) fieldErrors.display_name = nameError;
  const bioError = validateBio(bio);
  if (bioError) fieldErrors.bio = bioError;
  if (expertise.length > 80) fieldErrors.expertise = "Keep this under 80 characters.";

  const update: Record<string, unknown> = {
    username,
    display_name: displayName,
    bio: bio || null,
    expertise: expertise || null,
    interests: parseInterests(text(form, "interests")),
  };
  if (withPrivacy) {
    update.accepts_free_chats = form.get("accepts_free_chats") === "on";
    update.is_discoverable = form.get("is_discoverable") === "on";
  }
  return { fieldErrors, update };
}

async function saveProfile(form: FormData, withPrivacy: boolean, finishOnboarding: boolean): Promise<FormState | null> {
  const session = await getSession();
  if (!session) redirect("/login");
  if (session.profile.status !== "active") return { error: "Your account can't be changed right now." };

  const { fieldErrors, update } = readProfileFields(form, withPrivacy);
  if (Object.keys(fieldErrors).length) return { fieldErrors };

  const { error } = await session.supabase.from("profiles").update(update).eq("id", session.userId);
  if (error) {
    if (error.code === "23505") return { fieldErrors: { username: "That username is taken. Try another." } };
    if (error.code === "23514") return { fieldErrors: { username: "That username isn't allowed." } };
    return { error: "We couldn't save your profile. Please try again." };
  }

  if (finishOnboarding) {
    const { error: doneError } = await session.supabase.rpc("complete_onboarding");
    if (doneError) return { error: "We couldn't finish setting up your account. Please try again." };
  }
  return null;
}

export async function completeOnboarding(_prev: FormState, form: FormData): Promise<FormState> {
  const failure = await saveProfile(form, false, true);
  if (failure) return failure;
  redirect("/home");
}

export async function updateProfile(_prev: FormState, form: FormData): Promise<FormState> {
  const failure = await saveProfile(form, true, false);
  if (failure) return failure;
  revalidatePath("/", "layout");
  return { message: "Saved." };
}

/** Called after the browser has uploaded a photo into the person's own folder. */
export async function setAvatar(path: string): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");
  if (!isOwnAvatarPath(path, session.userId)) return { error: "That photo couldn't be used." };

  const { error } = await session.supabase
    .from("profiles")
    .update({ avatar_path: path })
    .eq("id", session.userId);
  if (error) return { error: "We couldn't save your photo. Please try again." };
  revalidatePath("/", "layout");
  return { message: "Photo updated." };
}

export async function removeAvatar(): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");
  const { error } = await session.supabase
    .from("profiles")
    .update({ avatar_path: null })
    .eq("id", session.userId);
  if (error) return { error: "We couldn't remove your photo. Please try again." };
  revalidatePath("/", "layout");
  return { message: "Photo removed." };
}

export async function setFollow(targetId: string, username: string, follow: boolean): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");
  const { error } = follow
    ? await session.supabase.rpc("follow_user", { p_target: targetId })
    : await session.supabase.rpc("unfollow_user", { p_target: targetId });
  if (error) {
    if (error.code === "P0002") return { error: "This person is no longer available." };
    if (error.code === "54000") return { error: "You're following too many people." };
    return { error: "That didn't work. Please try again." };
  }
  revalidatePath(`/u/${username}`);
  return {};
}
