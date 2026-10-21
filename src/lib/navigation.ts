/** Only same-site, absolute paths are allowed as a post-login destination. */
export function safeNextPath(raw: string | null | undefined, fallback = "/home"): string {
  if (!raw) return fallback;
  if (!raw.startsWith("/") || raw.startsWith("//") || raw.startsWith("/\\")) return fallback;
  if (/[\u0000-\u001f]/.test(raw)) return fallback;
  return raw;
}

export const appTabs = [
  { key: "home", label: "Home", href: "/home" },
  { key: "discover", label: "Discover", href: "/discover" },
  { key: "create", label: "Create", href: "/create" },
  { key: "inbox", label: "Inbox", href: "/inbox" },
  { key: "profile", label: "Profile", href: "/me" },
] as const;

export type AppTabKey = (typeof appTabs)[number]["key"];

/** Which tab a path belongs to (null for pages outside the five tabs). */
export function activeTab(pathname: string): AppTabKey | null {
  if (pathname === "/home") return "home";
  if (pathname.startsWith("/discover") || pathname.startsWith("/u/")) return "discover";
  if (pathname.startsWith("/create")) return "create";
  if (pathname.startsWith("/inbox")) return "inbox";
  if (pathname.startsWith("/me")) return "profile";
  return null;
}
