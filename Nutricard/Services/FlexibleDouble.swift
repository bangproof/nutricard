import Foundation

/// Decodes a number that APIs sometimes send as a string ("12.5"), and tolerates anything else as nil.
struct FlexibleDouble: Decodable, Hashable {
    let value: Double?

    init(_ value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}

enum UPC {
    /// UPC-A codes are often read as EAN-13 with a leading zero; compare without leading zeros.
    static func equivalent(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let a = String(lhs.filter(\.isNumber).drop { $0 == "0" })
        let b = String(rhs.filter(\.isNumber).drop { $0 == "0" })
        return !a.isEmpty && a == b
    }

    /// Codes to try, e.g. "0012345678905" → ["0012345678905", "012345678905"].
    static func lookupVariants(_ code: String) -> [String] {
        let digits = code.filter(\.isNumber)
        var variants = [digits]
        if digits.count == 13, digits.hasPrefix("0") { variants.append(String(digits.dropFirst())) }
        if digits.count == 12 { variants.append("0" + digits) }
        return variants
    }
}

enum HTTP {
    static let userAgent = "NutriCard/1.0 (iOS app; https://github.com/bangproof/nutricard)"

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }
}

enum HTTPError: LocalizedError {
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .status(429): return "Too many requests. Please wait a moment and try again."
        case .status(403): return "The server refused the request (check your API key)."
        case .status(let code): return "The server returned an error (\(code))."
        }
    }
}
