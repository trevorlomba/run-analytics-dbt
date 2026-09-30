"""Generate a synthetic dataset in the same raw format as extract_sheet.py.

The output mimics the real export, spreadsheet debris included (a repeated
header row, #REF!/#VALUE! cells, blank HR before the monitor was in use), so
the full project can build and test without any personal data. Seeded, so
output is deterministic.

Usage: python scripts/make_sample_data.py   # writes data/sample/*.csv
"""
import csv
import datetime as dt
import math
import random
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "sample"
rng = random.Random(42)

SESSION_COLS = ["activity_id", "activity_name", "run_date", "session_distance_m",
                "session_moving_time_s", "session_elapsed_time_s", "session_elev_gain_m",
                "session_avg_hr", "session_max_hr"]
SPLIT_COLS = ["distance_m", "elapsed_time_s", "pace", "{pace_col}", "grade_adj_pace",
              "avg_hr", "avg_grade_pct", "elev_gain_m", "elev_loss_m"]
DAY_TYPES = ["Rest", "Lift Only", "Run Only", "Lift + Run"]
# Current targets, then the previous window's targets (same shape as the sheet).
GOALS = {
    "Rest":       ((1550, 180, 75, 55),  (1650, 180, 80, 60),  (2275, 180, 230, 70)),
    "Lift Only":  ((1700, 180, 100, 57), (1800, 180, 110, 62), (2540, 180, 300, 70)),
    "Run Only":   ((1750, 180, 120, 57), (1850, 180, 130, 62), (2625, 180, 320, 70)),
    "Lift + Run": ((1900, 180, 145, 60), (2000, 180, 155, 65), (2800, 180, 350, 75)),
}
HR_START = dt.date(2026, 9, 1)  # HR monitor "arrives" partway through, like the real data
# Track sessions run on Tuesdays, with no lap button pressed: reps have to be
# found from the stream alone. (reps, rep distance m, recovery kind, recovery amount)
WORKOUTS = [(8, 800, "jog_m", 400), (6, 1000, "stand_s", 90), (10, 400, "jog_m", 200)]


def write(name, header, rows):
    with (OUT / f"{name}.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"{name}.csv ({len(rows)} rows)")


def fmt_pace(sec):
    # The sheet's text format: minutes "." seconds, e.g. 5:14 -> "5.14"
    return f"{int(sec // 60)}.{int(sec % 60):02d}"


def simulate_run(run_date, activity_id):
    """Second-by-second samples for one run: distance, HR, altitude, speed."""
    target_km = rng.choice([3, 4, 5, 5, 6, 8]) + rng.random() * 2
    base_speed = 1000 / rng.uniform(300, 345)          # ~5:00-5:45 per km
    has_hr = run_date >= HR_START
    samples, dist, t = [], 0.0, 0
    while dist < target_km * 1000:
        speed = max(0.0, base_speed + 0.25 * math.sin(t / 90) + rng.gauss(0, 0.08))
        if t < 3:
            speed = 0.0
        # HR drifts upward over the run (cardiac drift), which drives decoupling.
        hr = round(120 + 25 * min(t / 300, 1) + t / 400 + rng.gauss(0, 2)) if has_hr else None
        alt = round(20 + 8 * math.sin(dist / 700), 1)
        samples.append((t, round(dist, 1), hr, alt, round(speed, 2)))
        dist += speed * 2
        t += 2                                          # 0.5 Hz, not 1 Hz: tests time-weighting
    return samples


def simulate_workout(run_date, workout):
    """Warm-up, reps with jog or standing recoveries, cool-down. Track GPS reads
    a little long and speed is noisy, like the real thing."""
    reps, rep_m, recovery, amount = workout
    rep_speed = {400: 5.0, 800: 4.7, 1000: 4.55}[rep_m]
    easy = 1000 / rng.uniform(320, 345)
    plan = [("m", 2000, easy)]
    for i in range(reps):
        # Slight fade over the session, plus rep-to-rep wobble.
        plan.append(("m", rep_m, rep_speed * (1 - 0.004 * i) * (1 + rng.gauss(0, 0.012))))
        if i < reps - 1:
            plan.append(("m", amount, 2.3) if recovery == "jog_m" else ("s", amount, 0.0))
    plan.append(("m", 1600, easy * 0.95))

    has_hr = run_date >= HR_START
    samples, true_dist, speed, hr, t = [], 0.0, 0.0, 110.0, 0
    for kind, amount_, target in plan:
        seg_start_d, seg_start_t = true_dist, t
        while (true_dist - seg_start_d if kind == "m" else t - seg_start_t) < amount_:
            speed += 0.6 * (target - speed)                 # a couple of seconds to change pace
            gps_speed = max(0.0, speed + rng.gauss(0, 0.12 if target else 0.05))
            hr += 0.15 * (95 + 17 * speed - hr)
            samples.append((t, round(true_dist * 1.015, 1),
                            round(hr + rng.gauss(0, 1.5)) if has_hr else None,
                            round(20 + rng.gauss(0, 0.2), 1), round(gps_speed, 2)))
            true_dist += speed * 2
            t += 2
    return samples


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    laps, km_rows, mile_rows, streams = [], [], [], []

    run_dates, day = [], dt.date(2026, 7, 20)
    while day <= dt.date(2026, 9, 17):
        if rng.random() < 0.55:
            run_dates.append(day)
        day += dt.timedelta(days=1)

    tuesdays = [d for d in run_dates if d.weekday() == 1]
    workouts = {d: WORKOUTS[k % len(WORKOUTS)] for k, d in enumerate(tuesdays)}

    for i, run_date in enumerate(run_dates):
        activity_id = 30000000000 + i * 7919
        name = rng.choice(["Morning Run", "Evening Run", "Afternoon Run", "River Loop"])
        s = simulate_workout(run_date, workouts[run_date]) if run_date in workouts else simulate_run(run_date, activity_id)
        distance = s[-1][1]
        elapsed = s[-1][0]
        moving = sum(2 for x in s if x[4] > 0.5)
        hrs = [x[2] for x in s if x[2] is not None]
        avg_hr = str(round(sum(hrs) / len(hrs), 1)) if hrs else ""
        max_hr = str(max(hrs)) if hrs else ""
        elev = round(sum(max(0, b[3] - a[3]) for a, b in zip(s, s[1:])), 1)
        session = [activity_id, name, run_date.isoformat(), distance, moving, elapsed, elev, avg_hr, max_hr]

        laps.append(session + [1, "Lap 1", elapsed, moving, distance,
                               round(distance / moving, 3), round(max(x[4] for x in s), 3),
                               avg_hr, max_hr, "", "", elev])
        for x in s:
            streams.append([activity_id, name, x[0], x[1], "" if x[2] is None else x[2], x[3], x[4], "", ""])

        for unit_m, rows, pace_div in ((1000, km_rows, 1000), (1609.344, mile_rows, 1609.344)):
            n, start = 1, s[0]
            for a, b in zip(s, s[1:]):
                if b[1] >= n * unit_m or b is s[-1]:
                    seg_d = round(b[1] - start[1], 1)
                    seg_t = b[0] - start[0]
                    if seg_d > 0:
                        pace = seg_t / seg_d * pace_div
                        seg_hr = [x[2] for x in s if start[0] <= x[0] <= b[0] and x[2] is not None]
                        rows.append(session + [n, seg_d, seg_t, fmt_pace(pace), round(pace / 60, 3),
                                               fmt_pace(pace * 0.99),
                                               round(sum(seg_hr) / len(seg_hr), 1) if seg_hr else "",
                                               round(rng.gauss(0, 0.5), 2), round(rng.uniform(0, 8), 1),
                                               round(rng.uniform(0, 8), 1)])
                    n, start = n + 1, b

    # Daily nutrition log, with the same debris as the real sheet.
    run_days = set(run_dates)
    dailies, day = [], dt.date(2026, 4, 20)
    while day <= dt.date(2026, 9, 20):
        lift = rng.random() < 0.3
        day_type = ("Lift + Run" if lift else "Run Only") if day in run_days else ("Lift Only" if lift else "Rest")
        current, previous, maintenance = GOALS[day_type]
        cal_goal, p_goal, c_goal, f_goal = current if day >= dt.date(2026, 8, 19) else previous
        p = round(p_goal * rng.uniform(0.85, 1.08), 1)
        c = round(c_goal * rng.uniform(0.8, 1.25), 1)
        f = round(f_goal * rng.uniform(0.8, 1.25), 1)
        cal = round(4 * p + 4 * c + 9 * f + rng.gauss(0, 30))
        row = [""] * 26
        row[0], row[3] = day.isoformat(), day_type
        row[12:16] = [p, c, f, cal]
        row[20] = maintenance[0]
        dailies.append(row)
        day += dt.timedelta(days=1)
    dailies.insert(40, ["DATE"] + ["#VALUE!"] * 2 + ["Rest"] + ["#VALUE!"] * 18 + [""] * 4)
    for _ in range(2):
        dailies.append([""] * 4 + ["#REF!"] * 4 + [""] * 8 + ["180", "130", "60", "1900", "#REF!", "#REF!"] + [""] * 4)

    goals = [[dt_] + list(GOALS[dt_][0]) + list(GOALS[dt_][1]) + list(GOALS[dt_][2]) for dt_ in DAY_TYPES]

    split_cols = lambda unit, pace_col: SESSION_COLS + [unit] + [c.format(pace_col=pace_col) for c in SPLIT_COLS]
    write("strava_laps", SESSION_COLS + ["lap", "name", "elapsed_time_s", "moving_time_s", "distance_m",
                                         "avg_speed_ms", "max_speed_ms", "avg_heartrate", "max_heartrate",
                                         "avg_cadence", "avg_watts", "total_elevation_gain_m"], laps)
    write("strava_km_splits", split_cols("km", "pace_min_km"), km_rows)
    write("strava_mile_splits", split_cols("mile", "pace_min_mile"), mile_rows)
    write("strava_streams", ["activity_id", "activity_name", "time", "distance", "heartrate",
                             "altitude", "velocity_smooth", "cadence", "watts"], streams)
    write("nutrition_dailies", ["Date", "Month", "Lookback", "Day Type", "Protein Goal", "Carbs Goal",
                                "Fat Goal", "Calories Goal", "Protein 3DA Goal", "Carbs 3DA Goal",
                                "Fat 3DA Goal", "Calories 3DA Goal", "Protein", "Carbs", "Fat", "Calories",
                                "Protein 3DA", "Carbs 3DA", "Fat 3DA", "Calories 3DA", "Maintenance Calories",
                                "Maintenance Calories 3DA", "Today Calories", "Today Protein",
                                "Today Carbs", "Today Fat"], dailies)
    write("nutrition_goals", ["Day Type", "Calories", "Protein (g)", "Carbs (g)", "Fat (g)",
                              "Calories (5/1/26 - 8/18/26)", "Protein (g) (5/1/26 - 8/18/26)",
                              "Carbs (g) (5/1/26 - 8/18/26)", "Fat (g) (5/1/26 - 8/18/26)",
                              "Maintenance Calories", "Maintenance Protein (g)", "Maintenance Carbs (g)",
                              "Maintenance Fat (g)"], goals)


if __name__ == "__main__":
    main()
