/** Two circles: one filled, one outlined. One person, then another. */
export function BrandMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 40 24"
      aria-hidden="true"
      focusable="false"
      className={className}
    >
      <circle cx="12" cy="12" r="10" fill="currentColor" />
      <circle
        cx="28"
        cy="12"
        r="9"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
      />
    </svg>
  );
}
