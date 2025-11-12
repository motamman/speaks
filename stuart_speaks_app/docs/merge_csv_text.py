#!/usr/bin/env python3
"""
Merge text from CSV transcript files into a single text file for vocabulary import.
Extracts the "Text" column from all CSV files and merges them.
"""

import csv
import glob
import os

# Find all CSV files in the docs directory
script_dir = os.path.dirname(os.path.abspath(__file__))
csv_files = glob.glob(os.path.join(script_dir, "*.csv"))

print(f"Found {len(csv_files)} CSV files:")
for f in csv_files:
    print(f"  - {os.path.basename(f)}")

# Extract text from all CSV files
all_text = []

for csv_file in csv_files:
    print(f"\nProcessing: {os.path.basename(csv_file)}")

    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        # Check if "Text" column exists
        if 'Text' not in reader.fieldnames:
            print(f"  WARNING: No 'Text' column found, skipping")
            continue

        row_count = 0
        for row in reader:
            text = row['Text'].strip()
            if text:
                all_text.append(text)
                row_count += 1

        print(f"  Extracted {row_count} text entries")

# Merge all text with spaces
merged_text = ' '.join(all_text)

# Write to output file
output_file = os.path.join(script_dir, 'merged_vocabulary.txt')
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(merged_text)

print(f"\n✓ Merged text written to: {output_file}")
print(f"  Total characters: {len(merged_text):,}")
print(f"  Total words (approx): {len(merged_text.split()):,}")
