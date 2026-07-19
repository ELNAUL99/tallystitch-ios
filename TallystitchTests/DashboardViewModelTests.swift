import XCTest
import TallystitchCore
@testable import Tallystitch

// The first service-layer test in the app target — possible only because
// DashboardViewModel takes an injected DashboardDataProviding instead of
// reaching for the global Supabase client. The mock proves the seam works;
// the aggregation itself is pinned in TallystitchCore's DashboardMathTests.
@MainActor
final class DashboardViewModelTests: XCTestCase {

    struct MockData: DashboardDataProviding {
        var orders: [SalesService.SaleRow] = []
        var materials: [TallystitchCore.Material] = []
        var thrown: Error?

        func fetchOrders(since: Date) async throws -> [SalesService.SaleRow] {
            if let thrown { throw thrown }
            return orders
        }
        func fetchMaterials() async throws -> [TallystitchCore.Material] {
            if let thrown { throw thrown }
            return materials
        }
    }

    private func material(
        name: String, stock: Double, threshold: Double?
    ) -> TallystitchCore.Material {
        .init(id: UUID().uuidString, userId: "u", name: name, unit: "g",
              costPerUnit: 1, stockOnHand: stock, lowStockThreshold: threshold)
    }

    private func order(lines: [(String?, Double, Double)]) -> SalesService.SaleRow {
        .init(id: UUID().uuidString, source: "manual", externalOrderId: nil,
              orderDate: Date(), grossAmount: nil,
              orderItems: lines.map { name, qty, price in
                  .init(quantity: qty, unitSalePrice: price,
                        products: name.map { .init(name: $0) })
              })
    }

    func testLoadAggregatesOrdersAndFiltersLowStock() async {
        let mock = MockData(
            orders: [
                order(lines: [("Candle", 2, 22), ("Soap", 1, 9.5)]),
                order(lines: [("Candle", 1, 22)]),
            ],
            materials: [
                material(name: "Wax", stock: 100, threshold: 200),   // low
                material(name: "Wick", stock: 100, threshold: 10),   // fine
                material(name: "Oil", stock: 5, threshold: nil),     // no alert
            ]
        )
        let vm = DashboardViewModel(data: mock)

        await vm.load()

        XCTAssertTrue(vm.loaded)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.revenue, 2 * 22 + 9.5 + 22, accuracy: 1e-9)
        XCTAssertEqual(vm.byProduct.first?.name, "Candle")
        XCTAssertEqual(vm.byProduct.first?.units, 3)
        XCTAssertEqual(vm.lowStock.map(\.name), ["Wax"])
    }

    func testLoadSurfacesErrorsAndStillFinishesLoading() async {
        struct Boom: Error {}
        let vm = DashboardViewModel(data: MockData(thrown: Boom()))

        await vm.load()

        XCTAssertTrue(vm.loaded)
        XCTAssertNotNil(vm.error)
        XCTAssertEqual(vm.revenue, 0)
        XCTAssertTrue(vm.byProduct.isEmpty)
    }
}
