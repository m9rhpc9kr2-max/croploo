/**
 * USDA's real, officially published release cadence — WASDE has fixed
 * monthly dates; Crop Progress runs weekly (Mondays) through the
 * growing season. Neither publisher exposes a machine-readable
 * calendar API, so this is the schedule itself, not a stand-in for one.
 * Shared by routes/usda.js (the /usda/calendar endpoint) and
 * alertsEngine.js (USDA_RELEASE alerts).
 */
const WASDE_RELEASE_DATES_2026 = [
  "2026-01-12", "2026-02-10", "2026-03-10", "2026-04-09", "2026-05-12", "2026-06-11",
  "2026-07-10", "2026-08-12", "2026-09-11", "2026-10-09", "2026-11-10", "2026-12-10",
];

export function upcomingReleases(days) {
  const now = new Date();
  const horizon = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
  const releases = [];

  for (const d of WASDE_RELEASE_DATES_2026) {
    const date = new Date(d);
    if (date >= now && date <= horizon) {
      releases.push({ report_type: "WASDE", release_date: d });
    }
  }

  for (
    let d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    d <= horizon;
    d.setDate(d.getDate() + 1)
  ) {
    const isMonday = d.getDay() === 1;
    const inSeason = d.getMonth() >= 3 && d.getMonth() <= 10; // Apr–Nov
    if (isMonday && inSeason) {
      releases.push({ report_type: "CROP_PROGRESS", release_date: d.toISOString().slice(0, 10) });
    }
  }

  releases.sort((a, b) => (a.release_date < b.release_date ? -1 : 1));
  return releases;
}
