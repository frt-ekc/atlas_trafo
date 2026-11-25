// Sayfa geçişinde veri gelene kadar görünen iskelet. Next.js bunu kendiliğinden kullanır:
// kenar çubuğu ve üst bar yerinde kalır, yalnızca içerik alanı soluk kutularla dolar.
function Kutu({ className }: { className: string }) {
  return <div className={`animate-pulse rounded-lg bg-muted ${className}`} />;
}

export default function Yukleniyor() {
  return (
    <div className="flex flex-col gap-6" role="status" aria-live="polite">
      <span className="sr-only">Sayfa yükleniyor…</span>
      <div className="flex flex-col gap-2">
        <Kutu className="h-8 w-64" />
        <Kutu className="h-4 w-96 max-w-full" />
      </div>
      <div className="grid gap-2.5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="flex items-center justify-between gap-3 rounded-lg border bg-card px-3.5 py-2.5">
            <div className="flex flex-col gap-1.5">
              <Kutu className="h-3.5 w-28" />
              <Kutu className="h-3 w-36" />
            </div>
            <Kutu className="h-6 w-10" />
          </div>
        ))}
      </div>
      <div className="flex flex-col overflow-hidden rounded-lg border bg-card">
        <Kutu className="h-10 rounded-none" />
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="flex items-center gap-4 border-t px-3 py-3">
            <Kutu className="h-4 w-24" />
            <Kutu className="h-4 w-40" />
            <Kutu className="h-4 flex-1" />
            <Kutu className="h-6 w-20 rounded-full" />
          </div>
        ))}
      </div>
    </div>
  );
}
