import Testing

// Preserve the assertion call site when reporting failures from reusable helpers.
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, sourceLocation: sourceLocation)
}
func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, sourceLocation: sourceLocation)
}
func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
func expectNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value != nil, sourceLocation: sourceLocation)
}
func expectLessThanOrEqual<T: Comparable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual <= expected, sourceLocation: sourceLocation)
}
func expectGreaterThan<T: Comparable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual > expected, sourceLocation: sourceLocation)
}
func expectThrowsError<T>(_ operation: @autoclosure () throws -> T,
                         sourceLocation: SourceLocation = #_sourceLocation,
                         _ handler: (Error) -> Void = { _ in }) {
    do {
        _ = try operation()
        Issue.record("Expected an error, but operation succeeded", sourceLocation: sourceLocation)
    } catch { handler(error) }
}
