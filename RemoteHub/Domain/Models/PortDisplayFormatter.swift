import Foundation

enum PortDisplayFormatter {
    static let inputFormat = IntegerFormatStyle<Int>.number
        .grouping(.never)
        .locale(Locale(identifier: "en_US_POSIX"))

    static func string(_ port: Int) -> String {
        inputFormat.format(port)
    }

    static func endpoint(host: String, port: Int) -> String {
        "\(host):\(string(port))"
    }
}
