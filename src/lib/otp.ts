import type { EmailOtpType } from "@supabase/supabase-js";

const TYPES: readonly EmailOtpType[] = ["signup", "email", "recovery", "invite", "magiclink", "email_change"];

/** Accepts only the email link types Supabase can issue; anything else is null. */
export function parseOtpType(raw: string | null | undefined): EmailOtpType | null {
  return TYPES.find((t) => t === raw) ?? null;
}
