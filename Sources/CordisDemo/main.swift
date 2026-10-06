import CordisDemoKit

let entries = try writableEntries()
try await runDemo(entriesURL: entries)
