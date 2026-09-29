import Testing

// Swift Testing's receiver-capturing macros currently require Copyable in some
// call forms. Evaluate to Bool before assertion instead of weakening ownership.
func verify(_ condition: Bool, fileID: String = #fileID, filePath: String = #filePath,
            line: Int = #line, column: Int = #column) {
    #expect(condition, sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                                     line: line, column: column))
}
