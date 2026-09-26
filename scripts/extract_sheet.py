"""Extract the Macro Tracker workbook export into raw CSVs, one per tab.

Values are written as-is (strings, blanks, spreadsheet errors and all):
cleaning and typing happens in the dbt staging layer, not here.

Usage: python scripts/extract_sheet.py [path/to/export.xlsx]
"""
import csv
import datetime as dt
import sys
from pathlib import Path

import openpyxl

TABS = {
    "Laps": "strava_laps",
    "KM Splits": "strava_km_splits",
    "Mile Splits": "strava_mile_splits",
    "Streams": "strava_streams",
    "Dailies": "nutrition_dailies",
    "Goals Table": "nutrition_goals",
}
OUT = Path(__file__).resolve().parent.parent / "data" / "raw"


def to_text(value):
    if value is None:
        return ""
    if isinstance(value, dt.datetime):
        return value.date().isoformat() if value.time() == dt.time() else value.isoformat()
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def main(path):
    OUT.mkdir(parents=True, exist_ok=True)
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    for tab, name in TABS.items():
        rows = wb[tab].iter_rows(values_only=True)
        header = next(rows)
        # Keep only named columns; sheet tabs carry trailing helper columns.
        keep = [i for i, h in enumerate(header) if h not in (None, "")]
        out_file = OUT / f"{name}.csv"
        with out_file.open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([header[i] for i in keep])
            count = 0
            for row in rows:
                values = [to_text(row[i]) if i < len(row) else "" for i in keep]
                if any(values):
                    writer.writerow(values)
                    count += 1
        print(f"{tab:12} -> {out_file.name} ({count} rows)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "../run-log/log.xlsx")
