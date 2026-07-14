import Foundation

let normalizationCases = [
    ("v0.4.0", "0.4.0"),
    (" V1.2.3 \n", "1.2.3"),
    ("0.4.0", "0.4.0")
]

for (input, expected) in normalizationCases {
    guard UpdateChecker.normalizedVersion(input) == expected else {
        fputs("FAIL: version normalization for \(input)\n", stderr)
        exit(1)
    }
}

let comparisonCases = [
    ("0.4.1", "0.4.0", true),
    ("0.10.0", "0.9.9", true),
    ("1.0.0", "1.0.0", false),
    ("0.3.9", "0.4.0", false)
]

for (candidate, current, expected) in comparisonCases {
    guard UpdateChecker.isVersion(candidate, newerThan: current) == expected else {
        fputs("FAIL: version comparison \(candidate) vs \(current)\n", stderr)
        exit(1)
    }
}

print("PASS: update version normalization and comparison")
