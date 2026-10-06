/// Ordered list with O(1) removal by token (port of cordis `utils.ts`
/// `DisposableList`). Elements are identified by the token returned from
/// `push`, not by identity, so closures can be stored.
struct DisposableList<Element> {
  private var counter: UInt64 = 0
  private var map: [UInt64: Element] = [:]

  var count: Int { map.count }
  var isEmpty: Bool { map.isEmpty }

  /// Elements in insertion order.
  var values: [Element] {
    map.keys.sorted().map { map[$0]! }
  }

  @discardableResult
  mutating func push(_ element: Element) -> UInt64 {
    counter += 1
    map[counter] = element
    return counter
  }

  @discardableResult
  mutating func delete(_ token: UInt64) -> Bool {
    map.removeValue(forKey: token) != nil
  }

  /// Empties the list and returns its elements newest first, like cordis's
  /// `clear()`, so that teardown starts with the most recent effect.
  mutating func clear() -> [Element] {
    let result = Array(values.reversed())
    map.removeAll()
    return result
  }
}
