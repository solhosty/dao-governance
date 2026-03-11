import Link from "next/link";

type BreadcrumbItem = {
  label: string;
  href?: string;
};

type BreadcrumbsProps = {
  items: BreadcrumbItem[];
  backHref?: string;
  backLabel?: string;
};

export function Breadcrumbs({ items, backHref, backLabel = "Back" }: BreadcrumbsProps) {
  return (
    <div className="flex flex-wrap items-center gap-3 text-sm text-slate-600">
      {backHref ? (
        <Link href={backHref} className="rounded-md border border-white/40 bg-white/60 px-2 py-1 shadow-glass">
          {backLabel}
        </Link>
      ) : null}
      <nav aria-label="Breadcrumb" className="flex items-center gap-1">
        {items.map((item, index) => {
          const isLast = index === items.length - 1;
          return (
            <span key={`${item.label}-${index}`} className="flex items-center gap-1">
              {item.href && !isLast ? (
                <Link className="underline" href={item.href}>
                  {item.label}
                </Link>
              ) : (
                <span className={isLast ? "font-medium text-slate-900" : ""}>{item.label}</span>
              )}
              {!isLast ? <span>/</span> : null}
            </span>
          );
        })}
      </nav>
    </div>
  );
}
