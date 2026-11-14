import Foundation
import RookModels

/// Loads JSON fixtures that mirror real API responses. Shapes are taken from the Lambda
/// `toResponse`-style mappers in `packages/lambdas/*/src/index.ts`; values are synthetic (no PII).
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try RookJSON.makeDecoder().decode(T.self, from: data(name))
    }

    enum FixtureError: Error { case missing(String) }
}
