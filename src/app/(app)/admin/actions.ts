"use server";

import { revalidatePath } from "next/cache";
import type { FormState } from "@/lib/form-state";
import { requireSession } from "@/lib/session";

/** Admin only (enforced by the database): approve or reject a provider application. */
export async function reviewProvider(userId: string, approve: boolean, reason: string): Promise<FormState> {
  const session = await requireSession();
  const { error } = await session.supabase.rpc("admin_review_provider", {
    p_user: userId,
    p_approve: approve,
    p_reason: reason || null,
  });
  if (error) {
    if (error.message.includes("rejection_reason_required")) return { error: "Add a reason so the applicant knows what to change." };
    if (error.message.includes("not_pending_review")) return { error: "This application was already reviewed." };
    return { error: "You can't do that." };
  }
  revalidatePath("/admin/providers");
  return {};
}
