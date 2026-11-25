// Çalışan önerileri: sayfaya bir kez yazılır, CalisanSecici (sicil alanı) buradan okur.
// Gizli bir <datalist>; ekranda görünmez.
export type ListeCalisani = { sicil_no: string; ad: string; soyad: string };

export function CalisanListesi({ id, calisanlar }: { id: string; calisanlar: ListeCalisani[] }) {
  return (
    <datalist id={id}>
      {calisanlar.map((c) => (
        <option key={c.sicil_no} value={c.sicil_no}>
          {c.ad} {c.soyad}
        </option>
      ))}
    </datalist>
  );
}
