"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
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

export async function updateReportStatus(formData: FormData): Promise<void> {
  const session = await requireSession();
  const reportId = String(formData.get("report_id") ?? "");
  const status = String(formData.get("status") ?? "");
  const { error } = await session.supabase.rpc("admin_update_report_status", {
    p_report: reportId,
    p_status: status,
  });
  if (error) redirect("/admin?error=not-authorized");
  revalidatePath("/admin");
  redirect("/admin");
}

export async function grantAdministrator(formData: FormData): Promise<void> {
  const session = await requireSession();
  const userId = String(formData.get("user_id") ?? "");
  const { error } = await session.supabase.rpc("owner_grant_admin", { p_user: userId });
  if (error) redirect("/admin/settings?error=unable-to-grant");
  revalidatePath("/admin/settings");
  redirect("/admin/settings?updated=1");
}

export async function revokeAdministrator(formData: FormData): Promise<void> {
  const session = await requireSession();
  const userId = String(formData.get("user_id") ?? "");
  const { error } = await session.supabase.rpc("owner_revoke_admin", { p_user: userId });
  if (error) redirect("/admin/settings?error=unable-to-revoke");
  revalidatePath("/admin/settings");
  redirect("/admin/settings?updated=1");
}
