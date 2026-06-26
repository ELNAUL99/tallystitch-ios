import Foundation

// Identical demo dataset to the web/RN (candle + soap maker). Kept as plain
// value types so AccountService.SampleData can insert it with is_sample=true.
enum Sample {
    struct Mat { let name: String; let unit: String; let cost: Double; let stock: Double; let low: Double? }
    struct RecipeLine { let name: String; let qty: Double }
    struct Prod { let name: String; let sku: String; let price: Double; let recipe: [RecipeLine] }
    struct OrderLine { let product: String; let qty: Double; let price: Double }
    struct SampleOrder { let daysAgo: Int; let lines: [OrderLine]; let shipping: Double }

    static let materials: [Mat] = [
        Mat(name: "Soy wax", unit: "g", cost: 0.012, stock: 5000, low: 1000),
        Mat(name: "Cotton wick", unit: "piece", cost: 0.18, stock: 60, low: 20),
        Mat(name: "Lavender oil", unit: "ml", cost: 0.45, stock: 250, low: 50),
        Mat(name: "Amber jar (8oz)", unit: "piece", cost: 1.80, stock: 40, low: 12),
        Mat(name: "Olive oil base", unit: "g", cost: 0.009, stock: 8000, low: 1500),
        Mat(name: "Lye (NaOH)", unit: "g", cost: 0.020, stock: 1200, low: 300),
        Mat(name: "Mold liner", unit: "sheet", cost: 0.30, stock: 80, low: 20),
    ]

    static let products: [Prod] = [
        Prod(name: "Lavender Soy Candle (8oz)", sku: "CDL-LAV-8", price: 22.0, recipe: [
            RecipeLine(name: "Soy wax", qty: 220),
            RecipeLine(name: "Cotton wick", qty: 1),
            RecipeLine(name: "Lavender oil", qty: 6),
            RecipeLine(name: "Amber jar (8oz)", qty: 1),
        ]),
        Prod(name: "Lavender Olive-oil Soap Bar", sku: "SOAP-LAV", price: 9.5, recipe: [
            RecipeLine(name: "Olive oil base", qty: 90),
            RecipeLine(name: "Lye (NaOH)", qty: 12),
            RecipeLine(name: "Lavender oil", qty: 3),
            RecipeLine(name: "Mold liner", qty: 0.5),
        ]),
        Prod(name: "Unscented Olive-oil Soap Bar", sku: "SOAP-PL", price: 8.0, recipe: [
            RecipeLine(name: "Olive oil base", qty: 90),
            RecipeLine(name: "Lye (NaOH)", qty: 12),
            RecipeLine(name: "Mold liner", qty: 0.5),
        ]),
    ]

    static let orders: [SampleOrder] = [
        SampleOrder(daysAgo: 2, lines: [OrderLine(product: "Lavender Soy Candle (8oz)", qty: 2, price: 22.0), OrderLine(product: "Lavender Olive-oil Soap Bar", qty: 1, price: 9.5)], shipping: 5.5),
        SampleOrder(daysAgo: 5, lines: [OrderLine(product: "Lavender Olive-oil Soap Bar", qty: 3, price: 9.5)], shipping: 4.0),
        SampleOrder(daysAgo: 9, lines: [OrderLine(product: "Unscented Olive-oil Soap Bar", qty: 2, price: 8.0)], shipping: 4.0),
        SampleOrder(daysAgo: 14, lines: [OrderLine(product: "Lavender Soy Candle (8oz)", qty: 1, price: 22.0)], shipping: 5.5),
        SampleOrder(daysAgo: 21, lines: [OrderLine(product: "Lavender Olive-oil Soap Bar", qty: 2, price: 9.5), OrderLine(product: "Unscented Olive-oil Soap Bar", qty: 1, price: 8.0)], shipping: 5.0),
    ]
}
