/** Only same-site, absolute paths are allowed as a post-login destination. */
export function safeNextPath(raw: string | null | undefined, fallback = "/discover"): string {
  if (!raw) return fallback;
  if (!raw.startsWith("/") || raw.startsWith("//") || raw.startsWith("/\\")) return fallback;
  if (/[\u0000-\u001f]/.test(raw)) return fallback;
  return raw;
}
export const appTabs = [
  { key: "discover", label: "Discover", href: "/discover" },
  { key: "requests", label: "Requests", href: "/requests" },
  { key: "messages", label: "Messages", href: "/inbox" },
  { key: "profile", label: "Profile", href: "/me" },
] as const;
export type AppTabKey = (typeof appTabs)[number]["key"];
export function activeTab(pathname: string): AppTabKey | null {
  if (pathname === "/home" || pathname.startsWith("/discover") || pathname.startsWith("/u/")) return "discover";
  if (pathname.startsWith("/requests")) return "requests";
  if (pathname.startsWith("/inbox")) return "messages";
  if (pathname.startsWith("/me")) return "profile";
  return null;
}