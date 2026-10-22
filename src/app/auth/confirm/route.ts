import { NextResponse, type NextRequest } from "next/server";
import { safeNextPath } from "@/lib/navigation";
import { parseOtpType } from "@/lib/otp";
import { createClient } from "@/lib/supabase/server";

/**
 * Email links (confirm address, reset password) land here with a one-time
 * token_hash. Unlike the PKCE `code` flow this does not depend on a cookie from
 * the browser that started the sign-up, so it works when the email link opens
 * in a different browser (for example Chrome instead of Safari on an iPhone).
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const tokenHash = searchParams.get("token_hash");
  const type = parseOtpType(searchParams.get("type"));
  const next = safeNextPath(searchParams.get("next"), "/home");

  if (tokenHash && type) {
    const supabase = await createClient();
    if (supabase) {
      const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
      if (!error) return NextResponse.redirect(`${origin}${next}`);
    }
  }

  // PKCE-style links (?code=) still work when opened in the same browser.
  const code = searchParams.get("code");
  if (code) {
    const supabase = await createClient();
    if (supabase) {
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      if (!error) return NextResponse.redirect(`${origin}${next}`);
    }
  }
  return NextResponse.redirect(`${origin}/login?error=link`);
}
