#!/bin/bash

# Coverage check script for Crescendo test suite
# Runs tests with coverage and checks thresholds

set -e

echo "Running tests with coverage..."
flutter test --coverage

if [ ! -f "coverage/lcov.info" ]; then
  echo "Error: coverage/lcov.info not found"
  exit 1
fi

echo ""
echo "Coverage report generated successfully!"
echo ""

# Parse overall coverage
# This is a simplified check - in production you'd use lcov tools
total_lines=$(grep -c "^DA:" coverage/lcov.info || echo "0")
covered_lines=$(grep "^DA:" coverage/lcov.info | grep -v ",0$" | wc -l || echo "0")

if [ "$total_lines" -gt 0 ]; then
  coverage_percent=$(awk "BEGIN {printf \"%.2f\", ($covered_lines / $total_lines) * 100}")
  echo "Overall coverage: $coverage_percent% ($covered_lines / $total_lines lines)"
  
  # Check threshold (80%)
  threshold=80
  if (( $(echo "$coverage_percent < $threshold" | bc -l) )); then
    echo "❌ Coverage below threshold ($threshold%)"
    exit 1
  else
    echo "✅ Coverage meets threshold ($threshold%)"
  fi
else
  echo "Warning: No coverage data found"
  exit 1
fi

echo ""
echo "To view detailed coverage report:"
echo "  genhtml coverage/lcov.info -o coverage/html"
echo "  open coverage/html/index.html"
