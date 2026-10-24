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

const MESSAGE_ERRORS: Record<string, string> = {
  "28000": "Please sign in again.",
  "22023": "Write a message between 1 and 4000 characters.",
  "P0002": "This conversation is no longer available.",
  "54000": "You're sending messages too quickly. Wait a moment and try again.",
};

/** Opens (or reuses) the conversation with a person, then goes to it. */
export async function startConversation(targetId: string): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");
  const { data, error } = await session.supabase.rpc("start_conversation", { p_other: targetId });
  if (error || !data) {
    if (error?.message.includes("not_accepting_free_chats"))
      return { error: "This person isn't accepting free messages right now." };
    if (error?.message.includes("conversation_not_allowed") || error?.message.includes("recipient_unavailable"))
      return { error: "You can't message this person." };
    if (error?.code === "54000") return { error: "You've started too many new conversations today. Try again tomorrow." };
    return { error: MESSAGE_ERRORS[error?.code ?? ""] ?? "We couldn't open this conversation. Please try again." };
  }
  redirect(`/inbox/${data as string}`);
}

export async function sendMessage(
  conversationId: string,
  body: string,
): Promise<FormState & { id?: string }> {
  const session = await getSession();
  if (!session) return { error: "Please sign in again." };
  const { data, error } = await session.supabase.rpc("send_message", {
    p_conversation: conversationId,
    p_body: body,
  });
  if (error) {
    const m = error.message;
    if (m.includes("request_limit_reached"))
      return { error: "You've sent the maximum number of messages in a request. Wait for a reply." };
    if (m.includes("conversation_declined")) return { error: "This person declined your message request." };
    if (m.includes("conversation_not_allowed") || m.includes("recipient_unavailable") || m.includes("account_not_active"))
      return { error: "You can't send messages in this conversation." };
    return { error: MESSAGE_ERRORS[error.code] ?? "Your message wasn't sent. Please try again." };
  }
  return { id: data as string };
}

export async function markConversationRead(conversationId: string): Promise<void> {
  const session = await getSession();
  if (!session) return;
  await session.supabase.rpc("mark_conversation_read", { p_conversation: conversationId });
  revalidatePath("/inbox");
}

export async function respondToRequest(conversationId: string, accept: boolean): Promise<FormState> {
  const session = await getSession();
  if (!session) return { error: "Please sign in again." };
  const { error } = await session.supabase.rpc("respond_to_message_request", {
    p_conversation: conversationId,
    p_accept: accept,
  });
  if (error) return { error: "That didn't work. Please try again." };
  revalidatePath("/inbox");
  revalidatePath(`/inbox/${conversationId}`);
  return {};
}
