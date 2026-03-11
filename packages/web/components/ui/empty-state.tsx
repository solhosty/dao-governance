import Link from "next/link";

type EmptyStateAction = {
  href: string;
  label: string;
};

type EmptyStateProps = {
  title: string;
  description: string;
  cta?: EmptyStateAction;
  secondaryCta?: EmptyStateAction;
};

export function EmptyState({
  title,
  description,
  cta,
  secondaryCta,
}: EmptyStateProps) {
  return (
    <section className="rounded-lg border border-dashed border-slate-300 bg-white/60 p-8 text-center shadow-glass backdrop-blur-md">
      <h3 className="text-xl font-semibold">{title}</h3>
      <p className="mt-2 text-sm text-slate-600">{description}</p>
      {cta || secondaryCta ? (
        <div className="mt-5 flex flex-wrap justify-center gap-2">
          {cta ? (
            <Link href={cta.href} className="rounded-md bg-slate-900 px-4 py-2 text-sm text-white">
              {cta.label}
            </Link>
          ) : null}
          {secondaryCta ? (
            <Link
              href={secondaryCta.href}
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm"
            >
              {secondaryCta.label}
            </Link>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
