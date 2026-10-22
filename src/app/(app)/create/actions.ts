"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { FormState } from "@/lib/form-state";
import {
  parseLanguages,
  validateAbout,
  validateHeadline,
  validateOffering,
} from "@/lib/provider-validation";
import { requireSession } from "@/lib/session";

function text(form: FormData, key: string): string {
  const v = form.get(key);
  return typeof v === "string" ? v : "";
}

const GENERIC = "That didn't work. Please try again.";

/** Saves the provider profile (creating it the first time) and the chosen topics. */
export async function saveProviderProfile(_prev: FormState, form: FormData): Promise<FormState> {
  const session = await requireSession();
  const headline = text(form, "headline");
  const about = text(form, "about");
  const languages = parseLanguages(text(form, "languages"));
  const topicIds = form
    .getAll("topics")
    .filter((v): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v))
    .slice(0, 10);

  const fieldErrors: Record<string, string> = {};
  const hErr = validateHeadline(headline);
  if (hErr) fieldErrors.headline = hErr;
  const aErr = validateAbout(about);
  if (aErr) fieldErrors.about = aErr;
  if (Object.keys(fieldErrors).length) return { fieldErrors };

  const { supabase, userId } = session;
  const { data: existing } = await supabase
    .from("provider_profiles")
    .select("user_id, status")
    .eq("user_id", userId)
    .maybeSingle();

  if (existing) {
    if (existing.status === "suspended") return { error: "Your provider profile is suspended." };
    const { error } = await supabase
      .from("provider_profiles")
      .update({ headline: headline.trim(), about: about.trim(), languages })
      .eq("user_id", userId);
    if (error) return { error: GENERIC };
  } else {
    const { error } = await supabase
      .from("provider_profiles")
      .insert({ user_id: userId, headline: headline.trim(), about: about.trim(), languages });
    if (error) return { error: GENERIC };
  }

  // Replace topics: simple and bounded (at most 10).
  const del = await supabase.from("provider_topics").delete().eq("provider_id", userId);
  if (del.error) return { error: GENERIC };
  if (topicIds.length) {
    const ins = await supabase
      .from("provider_topics")
      .insert(topicIds.map((topic_id) => ({ provider_id: userId, topic_id })));
    if (ins.error) return { error: "We couldn't save your topics. Please try again." };
  }

  revalidatePath("/create");
  return { message: "Saved." };
}

export async function submitApplication(): Promise<FormState> {
  const session = await requireSession();
  const { error } = await session.supabase
    .from("provider_profiles")
    .update({ status: "pending_review" })
    .eq("user_id", session.userId);
  if (error) {
    return { error: "Complete your headline and about text, save them, then submit again." };
  }
  revalidatePath("/create");
  return {};
}

export async function withdrawApplication(): Promise<FormState> {
  const session = await requireSession();
  const { error } = await session.supabase
    .from("provider_profiles")
    .update({ status: "draft" })
    .eq("user_id", session.userId);
  if (error) return { error: GENERIC };
  revalidatePath("/create");
  return {};
}

function offeringFields(form: FormData) {
  return validateOffering({
    kind: text(form, "kind"),
    title: text(form, "title"),
    description: text(form, "description"),
    duration: text(form, "duration"),
    price: text(form, "price"),
    topicId: text(form, "topic_id"),
  });
}

export async function createOffering(_prev: FormState, form: FormData): Promise<FormState> {
  const session = await requireSession();
  const { value, errors } = offeringFields(form);
  if (!value) return { fieldErrors: errors };

  const { error } = await session.supabase.rpc("create_offering", {
    p_kind: value.kind,
    p_title: value.title,
    p_description: value.description,
    p_duration_minutes: value.durationMinutes,
    p_price_minor: value.priceMinor,
    p_topic_id: value.topicId,
  });
  if (error) {
    const m = error.message;
    if (m.includes("subscription_required"))
      return {
        error:
          "Your first paid conversation is free. Adding more needs an active provider subscription, which isn't available to purchase yet.",
      };
    if (m.includes("too_many_offerings")) return { error: "You've reached the limit of 20 offerings." };
    if (m.includes("provider_profile_required")) return { error: "Set up your provider profile first." };
    if (m.includes("invalid_topic") || m.includes("invalid_offering"))
      return { error: "Check the details and try again." };
    return { error: GENERIC };
  }
  revalidatePath("/create");
  redirect("/create");
}

export async function updateOffering(id: string, _prev: FormState, form: FormData): Promise<FormState> {
  const session = await requireSession();
  const { value, errors } = offeringFields(form);
  if (!value) return { fieldErrors: errors };

  const { error, data } = await session.supabase
    .from("offerings")
    .update({
      title: value.title,
      description: value.description,
      topic_id: value.topicId,
      duration_minutes: value.durationMinutes,
      price_minor: value.priceMinor,
    })
    .eq("id", id)
    .eq("provider_id", session.userId)
    .select("id");
  if (error || !data?.length) return { error: GENERIC };
  revalidatePath("/create");
  revalidatePath(`/create/offerings/${id}`);
  return { message: "Saved. New bookings use these details; existing bookings are unchanged." };
}

export async function setOfferingActive(id: string, active: boolean): Promise<FormState> {
  const session = await requireSession();
  const { error, data } = await session.supabase
    .from("offerings")
    .update({ is_active: active })
    .eq("id", id)
    .eq("provider_id", session.userId)
    .select("id");
  if (error || !data?.length) return { error: GENERIC };
  revalidatePath("/create");
  return {};
}
