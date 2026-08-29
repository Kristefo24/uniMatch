// Great-circle distance in km between two lat/lng points (Haversine formula).
// Straight-line, no external routing service — good enough for relative ranking.
function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Classic TOPSIS. `universities` each carry a `vals` map keyed by criterion code.
// `criteria`: [{ code, weight, direction: 'cost'|'benefit' }].
// Returns the input universities annotated with `cc` (closeness coefficient), sorted desc.
function topsis(universities, criteria) {
  if (!universities.length || !criteria.length) {
    return universities.map(u => ({ ...u, cc: 0 }));
  }
  // 1. Build decision matrix. A genuinely missing value is substituted with
  // the worst REAL value seen in its column (respecting direction) -- never
  // 0 -- so a university with no data on a cost criterion (lower is better)
  // can't look artificially perfect just for having nothing recorded. A
  // real, honestly-entered 0 is left untouched.
  const rawCols = criteria.map(c => universities.map(u => {
    const v = u.vals?.[c.code];
    return (v === undefined || v === null) ? null : Number(v);
  }));
  const fallback = criteria.map((c, j) => {
    const known = rawCols[j].filter(v => v !== null);
    if (!known.length) return 0; // nobody has data for this criterion at all
    return c.direction === 'cost' ? Math.max(...known) : Math.min(...known);
  });
  const matrix = universities.map((u, i) => criteria.map((c, j) => rawCols[j][i] === null ? fallback[j] : rawCols[j][i]));

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

  // 4. Distances + closeness coefficient, plus which single criterion this
  // university sits closest to (its strongest contributor) and furthest
  // from (its weakest) the ideal-best -- lets the UI explain a ranking
  // instead of showing a bare number.
  return universities.map((u, i) => {
    const dPlus = Math.sqrt(weighted[i].reduce((s, v, j) => s + (v - best[j]) ** 2, 0));
    const dMinus = Math.sqrt(weighted[i].reduce((s, v, j) => s + (v - worst[j]) ** 2, 0));
    const cc = (dPlus + dMinus) === 0 ? 0 : dMinus / (dPlus + dMinus);
    const distToBest = weighted[i].map((v, j) => Math.abs(v - best[j]));
    const bestJ = distToBest.indexOf(Math.min(...distToBest));
    const worstJ = distToBest.indexOf(Math.max(...distToBest));
    return { ...u, cc, bestCode: criteria[bestJ]?.code || null, worstCode: criteria[worstJ]?.code || null };
  }).sort((a, b) => b.cc - a.cc);
}

module.exports = { topsis, haversineKm };
