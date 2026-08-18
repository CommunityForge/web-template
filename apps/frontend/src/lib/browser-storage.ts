import * as KeyValueStore from "effect/unstable/persistence/KeyValueStore"

/**
 * The browser's `localStorage` as a `KeyValueStore`, built here once and imported by every feature runtime that
 * persists something.
 *
 * The single definition is the point: runtimes created by `Atom.runtime` share one Layer MemoMap per registry, so a
 * layer _value_ imported from here is built once no matter how many runtimes ask for it. Calling
 * `KeyValueStore.layerStorage` per feature would instead produce distinct layers, and so one store per feature over the
 * same `localStorage`.
 */
export const layerLocalStorage = KeyValueStore.layerStorage(() => window.localStorage)
