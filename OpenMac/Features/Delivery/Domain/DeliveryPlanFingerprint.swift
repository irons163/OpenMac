import CryptoKit
import Foundation

nonisolated enum DeliveryPlanFingerprint {
    nonisolated private struct ApprovedContent: Encodable {
        let id: UUID
        let revision: Int
        let tasks: [DeliveryTask]
        let dependencyEdges: [DependencyEdge]
        let createdAt: Date
    }

    nonisolated static func make(for plan: DeliveryPlan) -> String? {
        let content = ApprovedContent(
            id: plan.id,
            revision: plan.revision,
            tasks: plan.tasks,
            dependencyEdges: plan.dependencyEdges,
            createdAt: plan.createdAt
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

nonisolated enum DeliveryApprovalScopeFingerprint {
    nonisolated private struct ApprovedScope: Encodable {
        let runID: UUID
        let runCreatedAt: Date
        let brief: FeatureBrief
        let repositoryIdentity: DeliveryRepositoryIdentitySnapshot
        let planFingerprint: String
        let approvedAt: Date
        let approvedBy: String
    }

    nonisolated static func make(
        runID: UUID,
        runCreatedAt: Date,
        brief: FeatureBrief,
        repositoryIdentity: DeliveryRepositoryIdentitySnapshot,
        planFingerprint: String,
        approvedAt: Date,
        approvedBy: String
    ) -> String? {
        let scope = ApprovedScope(
            runID: runID,
            runCreatedAt: runCreatedAt,
            brief: brief,
            repositoryIdentity: repositoryIdentity,
            planFingerprint: planFingerprint,
            approvedAt: approvedAt,
            approvedBy: approvedBy
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(scope) else {
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
