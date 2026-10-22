"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { friendlyAuthError } from "@/lib/auth-errors";
import type { FormState } from "@/lib/form-state";
import { safeNextPath } from "@/lib/navigation";
import { getSiteUrl } from "@/lib/site-url";
import { createClient } from "@/lib/supabase/server";
import {
  validateDisplayName,
  validateEmail,
  validatePassword,
} from "@/lib/validation";

const NOT_CONNECTED = "Sign-in isn't connected in this environment yet.";

function text(form: FormData, key: string): string {
  const v = form.get(key);
  return typeof v === "string" ? v : "";
}

async function siteOrigin(): Promise<string> {
  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  if (host && /^[a-z0-9.-]+(:\d+)?$/i.test(host)) return `${proto}://${host}`;
  return getSiteUrl().origin;
}

export async function signIn(_prev: FormState, form: FormData): Promise<FormState> {
  const email = text(form, "email").trim();
  const password = text(form, "password");
  const fieldErrors: Record<string, string> = {};
  const emailError = validateEmail(email);
  if (emailError) fieldErrors.email = emailError;
  if (!password) fieldErrors.password = "Enter your password.";
  if (Object.keys(fieldErrors).length) return { fieldErrors };

  const supabase = await createClient();
  if (!supabase) return { error: NOT_CONNECTED };

  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: friendlyAuthError(error) };

  redirect(safeNextPath(text(form, "next")));
}

export async function signUp(_prev: FormState, form: FormData): Promise<FormState> {
  const name = text(form, "display_name");
  const email = text(form, "email").trim();
  const password = text(form, "password");
  const fieldErrors: Record<string, string> = {};
  const nameError = validateDisplayName(name);
  if (nameError) fieldErrors.display_name = nameError;
  const emailError = validateEmail(email);
  if (emailError) fieldErrors.email = emailError;
  const passwordError = validatePassword(password);
  if (passwordError) fieldErrors.password = passwordError;
  if (Object.keys(fieldErrors).length) return { fieldErrors };

  const supabase = await createClient();
  if (!supabase) return { error: NOT_CONNECTED };

  const origin = await siteOrigin();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { display_name: name.trim() },
      emailRedirectTo: `${origin}/auth/confirm?next=/onboarding`,
    },
  });
  if (error) return { error: friendlyAuthError(error) };

  // With email confirmation switched on there is no session yet.
  if (!data.session) {
    return {
      message: "Check your email. We sent a link to confirm your address, then you can finish setting up.",
    };
  }
  redirect("/onboarding");
}

export async function requestPasswordReset(_prev: FormState, form: FormData): Promise<FormState> {
  const email = text(form, "email").trim();
  const emailError = validateEmail(email);
  if (emailError) return { fieldErrors: { email: emailError } };

  const supabase = await createClient();
  if (!supabase) return { error: NOT_CONNECTED };

  const origin = await siteOrigin();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${origin}/auth/confirm?next=/reset-password`,
  });
  if (error && (error.status === 429 || error.code?.includes("rate_limit"))) {
    return { error: friendlyAuthError(error) };
  }
  // Same answer whether or not the address has an account.
  return { message: "If that address has an account, a reset link is on its way." };
}

export async function updatePassword(_prev: FormState, form: FormData): Promise<FormState> {
  const password = text(form, "password");
  const confirm = text(form, "confirm");
  const passwordError = validatePassword(password);
  if (passwordError) return { fieldErrors: { password: passwordError } };
  if (password !== confirm) return { fieldErrors: { confirm: "The two passwords don't match." } };

  const supabase = await createClient();
  if (!supabase) return { error: NOT_CONNECTED };

  const { data } = await supabase.auth.getUser();
  if (!data.user) {
    return { error: "This reset link has expired. Request a new one." };
  }
  const { error } = await supabase.auth.updateUser({ password });
  if (error) return { error: friendlyAuthError(error) };
  redirect("/home");
}

export async function signOut(): Promise<void> {
  const supabase = await createClient();
  if (supabase) await supabase.auth.signOut();
  redirect("/login");
}
