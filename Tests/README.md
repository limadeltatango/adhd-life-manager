# Foundation-only smoke test

On a computer with Swift installed, run:

```bash
swiftc LifeManager.swiftpm/LifeManagerCore.swift Tests/CoreSmokeTests.swift -o /tmp/life-manager-core-smoke
/tmp/life-manager-core-smoke
```

This validates the pure state machine and Codable serialization, not SwiftUI compilation or on-device delivery.
