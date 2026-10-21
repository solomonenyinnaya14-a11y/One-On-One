import { avatarUrl, initials } from "@/lib/avatar";

type AvatarProps = {
  name: string;
  path?: string | null;
  size?: "sm" | "md" | "lg";
};

const sizes = {
  sm: "h-10 w-10 text-sm",
  md: "h-14 w-14 text-lg",
  lg: "h-24 w-24 text-3xl",
} as const;

export function Avatar({ name, path, size = "md" }: AvatarProps) {
  const src = avatarUrl(path);
  const box = `${sizes[size]} shrink-0 rounded-full`;
  if (src) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt="" className={`${box} bg-grey-100 object-cover`} />;
  }
  return (
    <span
      aria-hidden="true"
      className={`${box} inline-flex items-center justify-center bg-navy-900 font-semibold text-white`}
    >
      {initials(name)}
    </span>
  );
}
