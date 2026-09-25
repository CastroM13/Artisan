import Foundation
import Yams

enum YAMLCodec {
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try YAMLDecoder().decode(type, from: text)
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        try YAMLEncoder().encode(value)
    }

    static func decodeValue(_ text: String) throws -> [String: YAMLValue] {
        try YAMLDecoder().decode([String: YAMLValue].self, from: text)
    }
}
