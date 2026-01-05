# Conduit Dependency Build Issue

## Problem

The Conduit dependency (commit `233f044` on `main` branch) has a build error preventing SwiftAgents from compiling:

```
error: unknown attribute 'Observable'
 --> /path/to/Conduit/Sources/Conduit/ChatSession.swift:230:2
  |
230 | @Observable
    |  ^ error: unknown attribute 'Observable'
231 | public final class ChatSession<Provider: AIProvider & TextGenerator>: @unchecked Sendable
```

## Root Cause

The `ChatSession.swift` file in Conduit is missing the `import Observation` statement required for the `@Observable` macro.

## Solution

### Upstream Fix Required

The Conduit repository (`christopherkarani/Conduit`) needs to be fixed:

**File:** `Sources/Conduit/ChatSession.swift`

**Current (broken):**
```swift
// ChatSession.swift
// Conduit

import Foundation

// ... rest of file ...

@Observable
public final class ChatSession<Provider: AIProvider & TextGenerator>: @unchecked Sendable
```

**Fixed:**
```swift
// ChatSession.swift
// Conduit

import Foundation
import Observation  // ← ADD THIS LINE

// ... rest of file ...

@Observable
public final class ChatSession<Provider: AIProvider & TextGenerator>: @unchecked Sendable
```

### Package.swift Update Required

Once the Conduit repository is fixed, update `Package.swift` to pin to a specific commit or tagged release instead of the unstable `branch: "main"`:

**Current (unstable):**
```swift
.package(url: "https://github.com/christopherkarani/Conduit.git", branch: "main")
```

**Recommended (after fix):**
```swift
// Option 1: Use a specific commit hash
.package(url: "https://github.com/christopherkarani/Conduit.git", revision: "abc123...")

// Option 2: Use semantic versioning (preferred, once tagged)
.package(url: "https://github.com/christopherkarani/Conduit.git", from: "0.7.0")
```

## Workaround for Development

If you need to develop locally before the upstream fix:

1. Clone the Conduit repository locally
2. Apply the fix (add `import Observation`)
3. Use a local package override in `Package.swift`:

```swift
// Add to Package.swift temporarily
dependencies: [
    // ... other dependencies ...
    .package(path: "../Conduit")  // Local path
]
```

## Status

- **Issue Identified:** 2026-01-05
- **Upstream PR:** (To be created in christopherkarani/Conduit)
- **SwiftAgents Impact:** Complete build failure, all tests blocked
- **Test Suite Status:** ✅ Comprehensive test suite created (ready once build is fixed)

## Test Coverage Added

Despite the build failure, comprehensive tests have been added and are ready to run once the dependency is fixed:

- ✅ `ConduitConfigurationTests.swift` - 272 lines, comprehensive validation
- ✅ `ConduitErrorTests.swift` - 243 lines, error mapping tests
- ✅ `ConduitTypeMappersTests.swift` - 386 lines, type conversion tests
- ✅ `ConduitProviderTests.swift` - 336 lines, provider functionality
- ✅ `ConduitToolConverterTests.swift` - 343 lines, tool conversion
- ✅ `ConduitProviderTypeTests.swift` - 432 lines, provider type tests
- ✅ `MockConduitProvider.swift` - 333 lines, mock implementation

**Total:** ~2,345 lines of test coverage following TDD principles.

## Next Steps

1. **Immediate:** Create PR in `christopherkarani/Conduit` adding `import Observation`
2. **After merge:** Update SwiftAgents `Package.swift` to pin to fixed commit
3. **Verify:** Run `swift build` and `swift test` to confirm fix
4. **Long-term:** Request tagged release from Conduit (v0.7.0 or similar)
5. **Final:** Update SwiftAgents to use semantic versioning

## References

- Conduit Repository: https://github.com/christopherkarani/Conduit
- SwiftAgents PR #16: https://github.com/christopherkarani/SwiftAgents/pull/16
- Swift Observation Framework: https://developer.apple.com/documentation/observation
