import Foundation

nonisolated enum StrictJSONValidator {
    nonisolated static let maximumNestingDepth = 128

    nonisolated static func validate(_ data: Data) throws {
        var scanner = Scanner(bytes: Array(data))
        try scanner.validate()
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        mutating func validate() throws {
            skipWhitespace()
            try parseValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else {
                throw StrictJSONValidationError("Unexpected trailing JSON content.")
            }
        }

        mutating private func parseValue(depth: Int) throws {
            guard depth <= StrictJSONValidator.maximumNestingDepth else {
                throw StrictJSONValidationError(
                    "JSON nesting exceeds \(StrictJSONValidator.maximumNestingDepth) levels."
                )
            }
            guard let byte = currentByte else {
                throw StrictJSONValidationError("Expected a JSON value.")
            }

            switch byte {
            case 0x7b:
                try parseObject(depth: depth)
            case 0x5b:
                try parseArray(depth: depth)
            case 0x22:
                _ = try parseString()
            case 0x74:
                try consumeLiteral("true")
            case 0x66:
                try consumeLiteral("false")
            case 0x6e:
                try consumeLiteral("null")
            case 0x2d, 0x30 ... 0x39:
                try parseNumber()
            default:
                throw StrictJSONValidationError("Unexpected byte at JSON offset \(index).")
            }
        }

        mutating private func parseObject(depth: Int) throws {
            try consume(0x7b)
            skipWhitespace()
            if consumeIfPresent(0x7d) { return }

            var keys: Set<String> = []
            while true {
                guard currentByte == 0x22 else {
                    throw StrictJSONValidationError("Expected an object key at JSON offset \(index).")
                }
                let key = try parseString()
                guard keys.insert(key).inserted else {
                    throw StrictJSONValidationError("Duplicate JSON object key '\(key)'.")
                }
                skipWhitespace()
                try consume(0x3a)
                skipWhitespace()
                try parseValue(depth: depth + 1)
                skipWhitespace()
                if consumeIfPresent(0x7d) { return }
                try consume(0x2c)
                skipWhitespace()
            }
        }

        mutating private func parseArray(depth: Int) throws {
            try consume(0x5b)
            skipWhitespace()
            if consumeIfPresent(0x5d) { return }

            while true {
                try parseValue(depth: depth + 1)
                skipWhitespace()
                if consumeIfPresent(0x5d) { return }
                try consume(0x2c)
                skipWhitespace()
            }
        }

        mutating private func parseString() throws -> String {
            let start = index
            try consume(0x22)

            while let byte = currentByte {
                if byte == 0x22 {
                    index += 1
                    let literal = Data(bytes[start ..< index])
                    do {
                        return try JSONDecoder().decode(String.self, from: literal)
                    } catch {
                        throw StrictJSONValidationError("Invalid JSON string at offset \(start).")
                    }
                }
                if byte == 0x5c {
                    index += 1
                    guard let escape = currentByte else {
                        throw StrictJSONValidationError("Unterminated JSON escape sequence.")
                    }
                    if escape == 0x75 {
                        index += 1
                        for _ in 0 ..< 4 {
                            guard let hex = currentByte, isHexDigit(hex) else {
                                throw StrictJSONValidationError("Invalid JSON Unicode escape.")
                            }
                            index += 1
                        }
                    } else {
                        guard [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74]
                            .contains(escape) else {
                            throw StrictJSONValidationError("Invalid JSON escape sequence.")
                        }
                        index += 1
                    }
                    continue
                }
                guard byte >= 0x20 else {
                    throw StrictJSONValidationError("Unescaped control character in JSON string.")
                }
                index += 1
            }

            throw StrictJSONValidationError("Unterminated JSON string.")
        }

        mutating private func parseNumber() throws {
            _ = consumeIfPresent(0x2d)
            guard let first = currentByte else {
                throw StrictJSONValidationError("Incomplete JSON number.")
            }
            if first == 0x30 {
                index += 1
            } else if (0x31 ... 0x39).contains(first) {
                index += 1
                _ = consumeDigits()
            } else {
                throw StrictJSONValidationError("Invalid JSON number.")
            }

            if consumeIfPresent(0x2e) {
                guard consumeDigits() > 0 else {
                    throw StrictJSONValidationError("Invalid JSON fraction.")
                }
            }
            if consumeIfPresent(0x65) || consumeIfPresent(0x45) {
                _ = consumeIfPresent(0x2b) || consumeIfPresent(0x2d)
                guard consumeDigits() > 0 else {
                    throw StrictJSONValidationError("Invalid JSON exponent.")
                }
            }
        }

        mutating private func consumeDigits() -> Int {
            let start = index
            while let byte = currentByte, (0x30 ... 0x39).contains(byte) {
                index += 1
            }
            return index - start
        }

        mutating private func consumeLiteral(_ literal: String) throws {
            let expected = Array(literal.utf8)
            guard index + expected.count <= bytes.count,
                  Array(bytes[index ..< index + expected.count]) == expected else {
                throw StrictJSONValidationError("Invalid JSON literal at offset \(index).")
            }
            index += expected.count
        }

        mutating private func consume(_ byte: UInt8) throws {
            guard consumeIfPresent(byte) else {
                throw StrictJSONValidationError("Expected JSON byte \(byte) at offset \(index).")
            }
        }

        mutating private func consumeIfPresent(_ byte: UInt8) -> Bool {
            guard currentByte == byte else { return false }
            index += 1
            return true
        }

        mutating private func skipWhitespace() {
            while let byte = currentByte,
                  byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d {
                index += 1
            }
        }

        private var currentByte: UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        private func isHexDigit(_ byte: UInt8) -> Bool {
            (0x30 ... 0x39).contains(byte)
                || (0x41 ... 0x46).contains(byte)
                || (0x61 ... 0x66).contains(byte)
        }
    }
}

nonisolated private struct StrictJSONValidationError: Error, CustomStringConvertible {
    let description: String

    nonisolated init(_ description: String) {
        self.description = description
    }
}
