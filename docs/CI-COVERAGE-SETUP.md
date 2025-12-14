# Test Coverage Reporting Setup Guide

This guide explains how to add comprehensive test coverage reporting to the SwiftAgents CI workflow.

## Overview

The coverage reporting setup includes:
- **Code coverage collection** during test execution
- **Multiple report formats**: HTML, JSON, lcov, and text
- **Coverage threshold enforcement** (minimum 70% by default)
- **CI artifact uploads** for easy access to reports
- **Automatic PR comments** with coverage summary (optional)

## Quick Start

### Option 1: Using the Coverage Script Locally

Run the coverage script to generate reports locally:

```bash
./scripts/generate-coverage-report.sh
```

This will:
1. Run tests with code coverage enabled
2. Generate HTML, JSON, lcov, and text reports
3. Check coverage against minimum threshold (70%)
4. Save all reports to `.build/coverage/`

View the HTML report:
```bash
open .build/coverage/html/index.html
```

### Option 2: Add to GitHub Actions Workflow

Since I cannot modify the workflow file directly due to GitHub App permissions, you'll need to manually add the coverage steps to `.github/workflows/swift.yml`.

## CI Workflow Integration

Add the following steps to the `build-and-test` job in `.github/workflows/swift.yml`:

### Step 1: Update the Test Step

Replace line 43-44:
```yaml
- name: Run tests
  run: swift test --parallel
```

With:
```yaml
- name: Run tests with coverage
  run: swift test --enable-code-coverage
```

### Step 2: Add Coverage Report Generation

Add these steps after the test step (around line 45):

```yaml
- name: Generate coverage reports
  run: |
    # Find test binary
    TEST_BINARY=$(find .build/debug -name "SwiftAgentsPackageTests.xctest" | head -n 1)
    BINARY_NAME=$(basename "$TEST_BINARY" .xctest)
    ACTUAL_BINARY="$TEST_BINARY/Contents/MacOS/$BINARY_NAME"

    # Generate text summary
    xcrun llvm-cov report \
      "$ACTUAL_BINARY" \
      -instr-profile=.build/debug/codecov/default.profdata \
      -ignore-filename-regex=".build|Tests" \
      -use-color

    # Create coverage directory
    mkdir -p .build/coverage

    # Generate HTML report
    xcrun llvm-cov show \
      "$ACTUAL_BINARY" \
      -instr-profile=.build/debug/codecov/default.profdata \
      -ignore-filename-regex=".build|Tests" \
      -format=html \
      -output-dir=.build/coverage/html

    # Generate lcov report
    xcrun llvm-cov export \
      "$ACTUAL_BINARY" \
      -instr-profile=.build/debug/codecov/default.profdata \
      -ignore-filename-regex=".build|Tests" \
      -format=lcov \
      > .build/coverage/coverage.lcov

    # Generate JSON report
    xcrun llvm-cov export \
      "$ACTUAL_BINARY" \
      -instr-profile=.build/debug/codecov/default.profdata \
      -ignore-filename-regex=".build|Tests" \
      -format=text \
      > .build/coverage/coverage.json

- name: Extract coverage percentage
  id: coverage
  run: |
    TEST_BINARY=$(find .build/debug -name "SwiftAgentsPackageTests.xctest" | head -n 1)
    BINARY_NAME=$(basename "$TEST_BINARY" .xctest)
    ACTUAL_BINARY="$TEST_BINARY/Contents/MacOS/$BINARY_NAME"

    COVERAGE=$(xcrun llvm-cov report \
      "$ACTUAL_BINARY" \
      -instr-profile=.build/debug/codecov/default.profdata \
      -ignore-filename-regex=".build|Tests" | \
      tail -n 1 | \
      awk '{print $NF}' | \
      sed 's/%//')

    echo "percentage=$COVERAGE" >> $GITHUB_OUTPUT
    echo "Coverage: $COVERAGE%"

- name: Upload coverage reports
  uses: actions/upload-artifact@v4
  with:
    name: coverage-reports
    path: |
      .build/coverage/
    retention-days: 30

- name: Check coverage threshold
  run: |
    MIN_COVERAGE=70
    CURRENT_COVERAGE=${{ steps.coverage.outputs.percentage }}

    echo "Current Coverage: $CURRENT_COVERAGE%"
    echo "Minimum Required: $MIN_COVERAGE%"

    if (( $(echo "$CURRENT_COVERAGE < $MIN_COVERAGE" | bc -l) )); then
      echo "❌ Coverage is below minimum threshold!"
      exit 1
    else
      echo "✅ Coverage meets minimum threshold"
    fi
```

### Step 3: (Optional) Add PR Comment with Coverage

To automatically post coverage results as PR comments, add this step:

```yaml
- name: Comment coverage on PR
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v7
  with:
    script: |
      const coverage = '${{ steps.coverage.outputs.percentage }}';
      const minCoverage = '70';
      const status = parseFloat(coverage) >= parseFloat(minCoverage) ? '✅' : '❌';

      const comment = `## ${status} Code Coverage Report

      **Current Coverage:** ${coverage}%
      **Minimum Required:** ${minCoverage}%

      📊 [View detailed coverage report](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})

      <details>
      <summary>Coverage by Module</summary>

      Download the artifacts from the workflow run to view detailed HTML reports.
      </details>`;

      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: comment
      });
```

## Complete Updated Job Example

Here's what the complete `build-and-test` job should look like:

```yaml
build-and-test:
  name: Build & Test
  runs-on: macos-26

  steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Show Swift version
      run: swift --version

    - name: Cache Swift packages
      uses: actions/cache@v4
      with:
        path: .build
        key: ${{ runner.os }}-swift-${{ hashFiles('Package.resolved') }}
        restore-keys: |
          ${{ runner.os }}-swift-

    - name: Resolve dependencies
      run: swift package resolve

    - name: Build (warnings as errors)
      run: swift build -Xswiftc -warnings-as-errors

    - name: Run tests with coverage
      run: swift test --enable-code-coverage

    - name: Generate coverage reports
      run: ./scripts/generate-coverage-report.sh

    - name: Extract coverage percentage
      id: coverage
      run: |
        TEST_BINARY=$(find .build/debug -name "SwiftAgentsPackageTests.xctest" | head -n 1)
        BINARY_NAME=$(basename "$TEST_BINARY" .xctest)
        ACTUAL_BINARY="$TEST_BINARY/Contents/MacOS/$BINARY_NAME"

        COVERAGE=$(xcrun llvm-cov report \
          "$ACTUAL_BINARY" \
          -instr-profile=.build/debug/codecov/default.profdata \
          -ignore-filename-regex=".build|Tests" | \
          tail -n 1 | \
          awk '{print $NF}' | \
          sed 's/%//')

        echo "percentage=$COVERAGE" >> $GITHUB_OUTPUT
        echo "Coverage: $COVERAGE%"

    - name: Upload coverage reports
      uses: actions/upload-artifact@v4
      with:
        name: coverage-reports
        path: .build/coverage/
        retention-days: 30

    - name: Check coverage threshold
      run: |
        MIN_COVERAGE=70
        CURRENT_COVERAGE=${{ steps.coverage.outputs.percentage }}

        if (( $(echo "$CURRENT_COVERAGE < $MIN_COVERAGE" | bc -l) )); then
          echo "❌ Coverage is below minimum threshold: $CURRENT_COVERAGE% < $MIN_COVERAGE%"
          exit 1
        else
          echo "✅ Coverage meets minimum threshold: $CURRENT_COVERAGE% >= $MIN_COVERAGE%"
        fi
```

## Integration with Third-Party Services

### Codecov Integration

1. Sign up at [codecov.io](https://codecov.io/)
2. Add the Codecov GitHub App to your repository
3. Add this step after coverage generation:

```yaml
- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: .build/coverage/coverage.lcov
    flags: unittests
    name: SwiftAgents
    fail_ci_if_error: true
    token: ${{ secrets.CODECOV_TOKEN }}
```

### Coveralls Integration

```yaml
- name: Upload to Coveralls
  uses: coverallsapp/github-action@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    path-to-lcov: .build/coverage/coverage.lcov
```

## Configuration Options

### Adjusting Coverage Threshold

Edit the `MIN_COVERAGE` variable in:
- `scripts/generate-coverage-report.sh` (line 15)
- CI workflow coverage check step

### Excluding Files from Coverage

To exclude additional files or directories, modify the `-ignore-filename-regex` parameter:

```yaml
-ignore-filename-regex=".build|Tests|Generated|Mocks"
```

### Report Retention

Adjust artifact retention in the upload step:

```yaml
retention-days: 30  # Keep reports for 30 days (default: 90)
```

## Viewing Coverage Reports

### In CI

1. Go to the workflow run in GitHub Actions
2. Scroll to the bottom to "Artifacts"
3. Download the `coverage-reports` artifact
4. Open `html/index.html` in a browser

### Locally

```bash
./scripts/generate-coverage-report.sh
open .build/coverage/html/index.html
```

## Troubleshooting

### Binary Not Found

If the test binary isn't found, check the find command:
```bash
find .build/debug -name "*Tests.xctest"
```

### Coverage Data Not Generated

Ensure tests run with `--enable-code-coverage`:
```bash
swift test --enable-code-coverage
```

### Permission Denied

Make the script executable:
```bash
chmod +x scripts/generate-coverage-report.sh
```

## Additional Resources

- [Swift Code Coverage Documentation](https://www.swift.org/documentation/code-coverage/)
- [llvm-cov Documentation](https://llvm.org/docs/CommandGuide/llvm-cov.html)
- [Codecov Swift Guide](https://docs.codecov.com/docs/swift)

## Next Steps

1. Update `.github/workflows/swift.yml` with the coverage steps above
2. Set your desired coverage threshold (currently 70%)
3. Consider integrating with Codecov or Coveralls for trend tracking
4. Add coverage badges to your README.md
