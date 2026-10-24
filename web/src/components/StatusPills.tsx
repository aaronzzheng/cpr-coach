// Header pills showing which data sources are connected.
interface Pill {
  label: string;
  on: boolean;
}

export function StatusPills({ pills }: { pills: Pill[] }) {
  return (
    <div className="pills">
      {pills.map((p) => (
        <span key={p.label} className={`pill ${p.on ? "on" : "off"}`}>
          <span className="dot" />
          {p.label}
        </span>
      ))}
    </div>
  );
}
