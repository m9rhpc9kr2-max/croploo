/** Minimal CSV encoder — no external dependency needed for this app's
 * simple flat rows. Quotes any value containing a comma, quote, or
 * newline and escapes embedded quotes per RFC 4180. */
function cell(value) {
  const s = value === null || value === undefined ? "" : String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** columns: [{ key, header }]; rows: array of plain objects. */
export function toCsv(rows, columns) {
  const lines = [columns.map((c) => cell(c.header)).join(",")];
  for (const row of rows) {
    lines.push(columns.map((c) => cell(row[c.key])).join(","));
  }
  return lines.join("\r\n");
}

export function sendCsv(res, filename, csv) {
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
  res.send(csv);
}
