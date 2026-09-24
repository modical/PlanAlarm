import UniformTypeIdentifiers

extension UTType {
    /// `.dayplan` files (UTF-8 JSON). Declared as an exported type in Info.plist.
    static let dayplan = UTType(exportedAs: "com.habashi.planalarm.dayplan", conformingTo: .json)
}
