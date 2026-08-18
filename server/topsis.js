// Classic TOPSIS. `universities` each carry a `vals` map keyed by criterion code.
// `criteria`: [{ code, weight, direction: 'cost'|'benefit' }].
// Returns the input universities annotated with `cc` (closeness coefficient), sorted desc.
function topsis(universities, criteria) {
  if (!universities.length || !criteria.length) {
    return universities.map(u => ({ ...u, cc: 0 }));
  }
  // 1. Build decision matrix.
  const matrix = universities.map(u => criteria.map(c => Number(u.vals?.[c.code] ?? 0)));

  // 2. Vector-normalise each column.
  const norms = criteria.map((_, j) => {
    const sumSq = matrix.reduce((s, row) => s + row[j] * row[j], 0);
    return Math.sqrt(sumSq) || 1;
  });
  const weightSum = criteria.reduce((s, c) => s + (Number(c.weight) || 0), 0) || 1;

  const weighted = matrix.map(row =>
    row.map((v, j) => (v / norms[j]) * ((Number(criteria[j].weight) || 0) / weightSum)));

  // 3. Ideal best / worst per column (flip for cost criteria).
  const best = criteria.map((c, j) => {
    const col = weighted.map(r => r[j]);
    return c.direction === 'cost' ? Math.min(...col) : Math.max(...col);
  });
  const worst = criteria.map((c, j) => {
    const col = weighted.map(r => r[j]);
    return c.direction === 'cost' ? Math.max(...col) : Math.min(...col);
  });

  // 4. Distances + closeness coefficient.
  return universities.map((u, i) => {
    const dPlus = Math.sqrt(weighted[i].reduce((s, v, j) => s + (v - best[j]) ** 2, 0));
    const dMinus = Math.sqrt(weighted[i].reduce((s, v, j) => s + (v - worst[j]) ** 2, 0));
    const cc = (dPlus + dMinus) === 0 ? 0 : dMinus / (dPlus + dMinus);
    return { ...u, cc };
  }).sort((a, b) => b.cc - a.cc);
}

module.exports = { topsis };
