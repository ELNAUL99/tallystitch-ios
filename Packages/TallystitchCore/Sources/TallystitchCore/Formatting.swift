import Foundation

// Money + number formatting — mirror of web's src/lib/format.ts. Currency
// formatting is locale-aware via NumberFormatter; the quantity / percent
// helpers are pure so they can be unit-tested without locale assumptions.

public enum Formatting {
    public static func currency(_ value: Double?, code: String = "USD") -> String {
        guard let value = value, !value.isNaN else { return "—" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        fmt.maximumFractionDigits = 2
        return fmt.string(from: NSNumber(value: value)) ?? "\(code) \(value)"
    }

    /// Drop trailing zeros for whole numbers; otherwise fixed fraction digits.
    public static func qty(_ value: Double?, fractionDigits: Int = 2) -> String {
        guard let value = value, !value.isNaN else { return "—" }
        let factor = pow(10.0, Double(fractionDigits))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.\(fractionDigits)f", rounded)
    }

    public static func percent(_ value: Double?) -> String {
        guard let value = value, !value.isNaN else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }
}
