"""Render the dashboard from the dbt marts and dbt's own test results.

Run after `dbt build` (it reads run_analytics.duckdb and target/run_results.json):

    python scripts/build_dashboard.py --out dist/dashboard.html          # personal data
    python scripts/build_dashboard.py --sample --standalone --out docs/index.html   # synthetic, for GitHub Pages
"""
import argparse
import datetime as dt
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


def jsonable(v):
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()[:10]
    if isinstance(v, float):
        return round(v, 4)
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
        "kpis": rows(con, """
            select
                (select count(*) from fct_runs where is_valid_run) as runs,
                (select sum(distance_km) from fct_runs where is_valid_run) as km,
                (select avg(case when hit_protein_goal then 1.0 else 0 end)
                   from fct_daily_nutrition where goal_id is not null) as protein_hit,
                (select avg(case when hit_calorie_goal then 1.0 else 0 end)
                   from fct_daily_nutrition where goal_id is not null) as calorie_hit,
                (select count(*) from fct_daily_nutrition where goal_id is not null) as goal_days
        """)[0],
        "weekly": rows(con, """
            select week_start, runs, run_km, long_run_km, avg_pace_s_per_km,
                   days_logged, avg_calories, avg_protein_g, protein_goal_hit_rate, calorie_goal_hit_rate
            from mart_weekly_summary order by week_start"""),
        "load": rows(con, """
            select date_day, run_km, acute_7d_km,
                   case when acute_chronic_ratio is not null then chronic_28d_km / 4 end as chronic_weekly_km,
                   acute_chronic_ratio
            from fct_training_load_daily order by date_day"""),
        "nutrition": rows(con, """
            select log_date, day_type, calories, calories_goal, protein_g, protein_g_goal, hit_calorie_goal
            from fct_daily_nutrition order by log_date"""),
        "runs": rows(con, """
            select run_date, activity_name, distance_km, avg_pace_s_per_km, avg_hr,
                   aerobic_decoupling_pct, is_negative_split, is_valid_run
            from fct_runs order by run_date desc, activity_id desc"""),
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
