export const siteConfig = {
  name: "One On One",
  headline: "Find your people. Start a conversation.",
  description: "Discover people by name or username, send a message request, and chat privately once they accept.",
} as const;
export const routes = { home: "/", explore: "/explore", getStarted: "/register", signIn: "/login", becomeProvider: "/login" } as const;
export const primaryNav = [{ label: "How it works", href: "/#how-it-works" }, { label: "Privacy", href: "/#privacy" }] as const;
export const ctaLabels = { explore: "Get started", becomeProvider: "Sign in" } as const;