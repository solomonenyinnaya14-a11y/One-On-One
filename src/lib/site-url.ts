type Env = Record<string, string | undefined>;

const LOCAL_FALLBACK = "http://localhost:3000";

function parseUrl(value: string | undefined): URL | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;

  const withProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    return new URL(withProtocol);
  } catch {
    return null;
  }
}

/**
 * The public base URL of this deployment, used for metadata and absolute links.
 *
 * Order: an explicit NEXT_PUBLIC_SITE_URL, then the Vercel production domain
 * (production builds) or the deployment URL (previews), then localhost.
 * A malformed value never throws; it falls through to the next option so a
 * typo in an environment variable cannot break the build.
 */
export function getSiteUrl(env: Env = process.env): URL {
  const vercelUrl =
    env.VERCEL_ENV === "production" ? env.VERCEL_PROJECT_PRODUCTION_URL : env.VERCEL_URL;

  return (
    parseUrl(env.NEXT_PUBLIC_SITE_URL) ?? parseUrl(vercelUrl) ?? new URL(LOCAL_FALLBACK)
  );
}
