interface NetworkMeshProps {
  className?: string;
}

// Deterministic, faint network mesh used purely as decorative flair.
// A handful of nodes with thin connecting lines, drawn in the accent color
// at low opacity. Rendered behind content (no interaction).
export default function NetworkMesh({ className = '' }: NetworkMeshProps) {
  // Fixed layout so it stays stable across renders (viewBox 0..1000 x 0..300).
  const nodes = [
    [60, 70], [180, 40], [300, 110], [420, 50], [540, 130], [660, 60],
    [780, 120], [900, 50], [140, 200], [340, 230], [520, 210], [700, 240], [880, 190],
    [240, 150], [460, 160], [640, 170],
  ] as const;

  // Connect each node to its 2 nearest neighbours.
  const lines: string[] = [];
  nodes.forEach((n, i) => {
    const d = nodes
      .map((m, j) => ({ j, dist: Math.hypot(m[0] - n[0], m[1] - n[1]) }))
      .filter((o) => o.j !== i)
      .sort((a, b) => a.dist - b.dist)
      .slice(0, 2);
    d.forEach((o) => {
      const key = i < o.j ? `${i}-${o.j}` : `${o.j}-${i}`;
      if (!lines.includes(key)) lines.push(key);
    });
  });

  return (
    <svg
      className={className}
      viewBox="0 0 1000 300"
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
      focusable="false"
    >
      <g stroke="var(--accent)" strokeWidth="1" opacity="0.5">
        {lines.map((key) => {
          const [a, b] = key.split('-').map(Number);
          return <line key={key} x1={nodes[a][0]} y1={nodes[a][1]} x2={nodes[b][0]} y2={nodes[b][1]} />;
        })}
      </g>
      <g fill="var(--accent)" opacity="0.7">
        {nodes.map((n, i) => (
          <circle key={i} cx={n[0]} cy={n[1]} r={i % 4 === 0 ? 3 : 2} />
        ))}
      </g>
    </svg>
  );
}
