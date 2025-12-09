import csv
import os
import json
import argparse
from typing import List, Tuple


def compute_take_accuracy(csv_path: str, threshold_cents: float = 25.0) -> float:
    """
    Returns accuracy (%) for a single take CSV:
    % of notes whose |cents_error| <= threshold_cents.
    """
    total_notes = 0
    within_threshold = 0

    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if "cents_error" not in row:
                continue
            try:
                cents_error = float(row["cents_error"])
            except (ValueError, TypeError):
                continue

            total_notes += 1
            if abs(cents_error) <= threshold_cents:
                within_threshold += 1

    if total_notes == 0:
        return 0.0

    return (within_threshold / total_notes) * 100.0


def find_csv_files(takes_dir: str) -> List[str]:
    if not os.path.isdir(takes_dir):
        raise FileNotFoundError(f"takes directory not found: {takes_dir}")
    csvs = [
        os.path.join(takes_dir, f)
        for f in os.listdir(takes_dir)
        if f.lower().endswith(".csv")
    ]
    csvs.sort()
    return csvs


def build_index(takes_dir: str, threshold_cents: float) -> Tuple[list, list]:
    csv_files = find_csv_files(takes_dir)

    labels = []
    scores = []

    for csv_path in csv_files:
        accuracy = compute_take_accuracy(csv_path, threshold_cents)
        label = os.path.splitext(os.path.basename(csv_path))[0]
        labels.append(label)
        scores.append(round(accuracy, 2))

    return labels, scores


def main():
    parser = argparse.ArgumentParser(
        description="Build JSON index of vocal take accuracies from takes/ folder."
    )
    parser.add_argument(
        "--takes_dir",
        default="takes",
        help="Directory containing take CSVs (default: takes)",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=25.0,
        help="Cents threshold for counting a note as 'accurate' (default: 25).",
    )
    parser.add_argument(
        "--output",
        default="takes_index.json",
        help="Output JSON file (default: takes_index.json)",
    )
    args = parser.parse_args()

    labels, scores = build_index(args.takes_dir, args.threshold)

    if not labels:
        print("No CSVs found in takes directory or no valid data.")
        return

    data = {
        "labels": labels,
        "scores": scores,
        "threshold_cents": args.threshold,
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    print(f"✅ Wrote {args.output} with {len(labels)} takes.")
    for label, score in zip(labels, scores):
        print(f"  {label}: {score:.2f}%")


if __name__ == "__main__":
    main()