"""Render the dashboard from the dbt marts and dbt's own test results.

Run after `dbt build` (it reads run_analytics.duckdb and target/run_results.json):

    python scripts/build_dashboard.py --out dist/dashboard.html          # personal data
    python scripts/build_dashboard.py --sample --standalone --out docs/index.html   # synthetic, for GitHub Pages
"""
import argparse
import datetime as dt
import decimal
import json
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent

# Plain-language explanations for warn-level monitors, keyed by test name.
WARNING_TEXT = {
    "warn_strava_sync_is_fresh": "Strava sync looks stalled. Food logging continued after the last imported run.",
    "warn_logged_calories_match_macros": "Logged calories are more than 15% off the 4/4/9 macro math on these days.",
}


def rows(con, sql):
    cur = con.execute(sql)
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def grouped(con, sql, by_unit=False):
    """Group row tuples by activity id (and split unit), dropping the key columns."""
    out = {}
    for r in con.execute(sql).fetchall():
        if by_unit:
            out.setdefault(r[0], {}).setdefault(r[1], []).append(list(r[2:]))
        else:
            out.setdefault(r[0], []).append(list(r[1:]))
    return out


def streams(con, days=45):
    """{activity_id: [dt_s[], d_dm[], v_cms[]]} for valid GPS runs in the last `days` days."""
    out, last = {}, {}
    for a, t, d, v in con.execute(f"""
            select cast(s.activity_id as varchar), s.elapsed_s,
                   cast(round(s.distance_m * 10) as integer), cast(round(s.speed_m_s * 100) as integer)
            from stg_strava__streams as s
            inner join fct_runs as r using (activity_id)
            where r.is_valid_run and not r.is_manual_entry
              and r.run_date >= (select max(run_date) from fct_runs) - interval {int(days)} day
              and s.distance_m is not null and s.speed_m_s is not null
            order by 1, 2""").fetchall():
        dt_, dd, vv = out.setdefault(a, [[], [], []])
        prev_t, prev_d = last.get(a, (0, 0))
        dt_.append(t - prev_t)
        dd.append(d - prev_d)
        vv.append(v)
        last[a] = (t, d)
    return out


def jsonable(v):
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()[:10]
    if isinstance(v, float):
        return round(v, 4)
    if isinstance(v, decimal.Decimal):
        return float(v)
    return v


def test_health():
    results = json.loads((ROOT / "target" / "run_results.json").read_text())["results"]
    tests = [r for r in results if r["unique_id"].split(".")[0] in ("test", "unit_test")]
    count = lambda s: sum(1 for r in tests if r["status"] == s)
    warnings = [
        {"test": r["unique_id"].split(".")[2], "failures": r.get("failures") or 0,
         "message": WARNING_TEXT.get(r["unique_id"].split(".")[2], "Warn-level check returned rows.")}
        for r in tests if r["status"] == "warn"
    ]
    return {"pass": count("pass"), "warn": count("warn"),
            "fail": count("fail") + count("error"), "total": len(tests), "warnings": warnings}


def main(out, sample, standalone):
    con = duckdb.connect(str(ROOT / "run_analytics.duckdb"), read_only=True)
    data = {
        "meta": {
            "dataset": "sample" if sample else "personal",
            "built_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
            **rows(con, """select min(date_day) as date_min, max(date_day) as date_max,
                                  (select max(run_date) from fct_runs) as latest_run,
                                  (select max(log_date) from fct_daily_nutrition) as latest_log
                           from dim_date""")[0],
        },
        "health": test_health(),
        # Everything below is daily or per-run grain; the page filters by date
        # range and rolls weeks up itself, so the week start and units can change.
        "load": rows(con, """
            select date_day, run_km, acute_7d_km,
                   case when acute_chronic_ratio is not null then chronic_28d_km / 4 end as chronic_weekly_km,
                   acute_chronic_ratio
            from fct_training_load_daily order by date_day"""),
        "nutrition": rows(con, """
            select log_date, day_type, calories, calories_goal, protein_g, protein_g_goal,
                   hit_calorie_goal, hit_protein_goal
            from fct_daily_nutrition order by log_date"""),
        "runs": rows(con, """
            select cast(activity_id as varchar) as activity_id, run_date, activity_name,
                   distance_km * 1000 as distance_m, moving_time_s, elapsed_time_s, elev_gain_m,
                   avg_hr, max_hr, aerobic_decoupling_pct, is_negative_split, is_valid_run, is_manual_entry,
                   workout_label
            from fct_runs order by run_date, activity_id"""),
        # Compact arrays keep the embedded payload small (thousands of rows).
        "splits": grouped(con, """
            select cast(activity_id as varchar), split_unit, distance_m, elapsed_time_s,
                   grade_adj_pace_s_per_unit, avg_hr, elev_gain_m, elev_loss_m, is_partial_split
            from fct_run_splits order by activity_id, split_unit, split_number""", by_unit=True),
        "reps": grouped(con, """
            select cast(activity_id as varchar), rep_distance_m, rep_time_s, rep_time_vs_avg_s,
                   round(avg_hr), recovery_time_s, recovery_distance_m, is_fastest_rep,
                   case when nominal_distance_m is not null then round(gps_distance_m) end
            from fct_workout_reps order by activity_id, rep_number"""),
        # Raw speed streams for recent runs, so the page can re-find reps from a hint
        # ("4 x 800"). Delta-encoded ints keep ~45 days to a few hundred KB.
        "streams": streams(con),
        "profile": grouped(con, """
            select cast(activity_id as varchar), round(distance_m), round(pace_s_per_km, 1),
                   round(altitude_m, 1), round(avg_hr)
            from fct_run_route_profile order by activity_id, segment_index"""),
    }

    def clean(o):
        if isinstance(o, dict):
            return {k: clean(v) for k, v in o.items()}
        if isinstance(o, list):
            return [clean(v) for v in o]
        return jsonable(o)

    payload = json.dumps(clean(data), separators=(",", ":")).replace("</", "<\\/")
    html = (ROOT / "dashboard" / "template.html").read_text().replace("/*__DATA__*/null", payload)
    if standalone:
        # The template is a page body; wrap it for hosts that serve it as-is (GitHub Pages).
        html = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
                '<meta name="viewport" content="width=device-width, initial-scale=1">\n</head>\n<body>\n'
                + html + "\n</body>\n</html>\n")
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)
    print(f"wrote {out} ({len(html) // 1024} KB, {data['health']['total']} tests, {len(data['runs'])} runs)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="dist/dashboard.html")
    ap.add_argument("--sample", action="store_true", help="label the page as synthetic sample data")
    ap.add_argument("--standalone", action="store_true", help="wrap in a full HTML document")
    a = ap.parse_args()
    main(a.out, a.sample, a.standalone)
