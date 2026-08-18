import { addEqualityTesters } from "@effect/vitest"

// Teaches Vitest's `expect` about Effect's `Equal` protocol, so `toEqual` on Options, Eithers,
// Data classes etc. compares by value rather than by structure.
addEqualityTesters()
