import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import Testing

/// `OcaArray2D` is `nX` columns by `nY` rows, stored and serialised as rows.
@Suite struct Array2DTests {
  /// A deliberately non-square grid, so a transposed layout cannot pass.
  private var grid: OcaArray2D<String> {
    OcaArray2D(arrayOfArrays: [["a", "b", "c"], ["d", "e", "f"]])!
  }

  @Test func dimensionsCountColumnsThenRows() {
    #expect(grid.nX == 3)
    #expect(grid.nY == 2)
    #expect(grid.count == 6)
  }

  @Test func subscriptIndexesTheRowsItWasBuiltFrom() {
    #expect(grid[0, 0] == "a")
    #expect(grid[2, 0] == "c")
    #expect(grid[0, 1] == "d")
    #expect(grid[2, 1] == "f")
  }

  @Test func arrayOfArraysInvertsTheInitialiser() {
    #expect(grid.arrayOfArrays == [["a", "b", "c"], ["d", "e", "f"]])
  }

  @Test func raggedRowsAreRejected() {
    #expect(OcaArray2D(arrayOfArrays: [["a", "b"], ["c"]]) == nil)
  }

  @Test func writesLandWhereTheyAreRead() {
    var grid = grid
    grid[1, 1] = "z"
    #expect(grid[1, 1] == "z")
    #expect(grid.arrayOfArrays == [["a", "b", "c"], ["d", "z", "f"]])
  }

  @Test func jsonIsAnArrayOfRows() throws {
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(grid))
    #expect(json as? [[String]] == [["a", "b", "c"], ["d", "e", "f"]])
  }

  @Test func jsonRoundTrips() throws {
    let encoded = try JSONEncoder().encode(grid)
    #expect(try JSONDecoder().decode(OcaArray2D<String>.self, from: encoded) == grid)
  }

  @Test func ocp1RoundTrips() throws {
    let encoded: Data = try Ocp1Encoder().encode(grid)
    #expect(try Ocp1Decoder().decode(OcaArray2D<String>.self, from: encoded) == grid)
  }
}
