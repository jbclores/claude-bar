import Foundation

/// A value shared across threads behind a lock.
public final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    public init(_ value: Value) {
        self.value = value
    }

    public func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    public func update<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
