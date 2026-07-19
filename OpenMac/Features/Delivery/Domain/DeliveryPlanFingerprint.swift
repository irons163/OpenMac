import CryptoKit
import Foundation

nonisolated enum DeliveryPlanFingerprint {
    nonisolated private struct ApprovedContent: Encodable {
        let id: UUID
        let revision: Int
        let tasks: [DeliveryTask]
        let dependencyEdges: [DependencyEdge]
    }

    nonisolated static func make(for plan: DeliveryPlan) -> String? {
        let content = ApprovedContent(
            id: plan.id,
            revision: plan.revision,
            tasks: plan.tasks,
            dependencyEdges: plan.dependencyEdges
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(content) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        let hexadecimal = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in digest {
            bytes.append(hexadecimal[Int(byte >> 4)])
            bytes.append(hexadecimal[Int(byte & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
