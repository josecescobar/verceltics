import Foundation
#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

/// A searchable item the app can hand to Spotlight.
///
/// Built as a plain record so the mapping from projects, zones, and domains can
/// be unit tested without CoreSpotlight.
nonisolated struct SpotlightRecord: Equatable, Sendable {
    enum Kind: String, Sendable {
        case project
        case zone
        case domain
        case deployment
    }

    let kind: Kind
    let identifier: String
    let title: String
    let subtitle: String
    let keywords: [String]

    var uniqueIdentifier: String { "\(kind.rawValue):\(identifier)" }

    var workspace: PrimaryWorkspace {
        switch kind {
        case .project, .zone, .deployment: .hosting
        case .domain: .registrars
        }
    }
}

nonisolated enum SpotlightRecordBuilder {
    static let domainIdentifier = "com.apoorvdarshan.verceltics"

    static func projects(_ projects: [Project]) -> [SpotlightRecord] {
        projects.map { project in
            SpotlightRecord(
                kind: .project,
                identifier: project.id,
                title: project.name,
                subtitle: [project.primaryDomain, project.sourceScope?.name]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                keywords: [project.name, project.primaryDomain, project.framework, "vercel", "project"]
                    .compactMap { $0 }
            )
        }
    }

    static func zones(_ zones: [CloudflareZone]) -> [SpotlightRecord] {
        zones.map { zone in
            SpotlightRecord(
                kind: .zone,
                identifier: zone.id,
                title: zone.name,
                subtitle: [zone.status, zone.account?.name]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                keywords: [zone.name, zone.status, "cloudflare", "zone", "dns"].compactMap { $0 }
            )
        }
    }

    static func domains(_ domains: [RegistrarDomain]) -> [SpotlightRecord] {
        domains.map { domain in
            var keywords = [domain.name, "domain", "registrar"]
            if let status = domain.status { keywords.append(status) }
            return SpotlightRecord(
                kind: .domain,
                identifier: domain.name.lowercased(),
                title: domain.name,
                subtitle: domain.expiresAt.map {
                    "Expires \($0.formatted(date: .abbreviated, time: .omitted))"
                } ?? (domain.status ?? "Domain"),
                keywords: keywords
            )
        }
    }

    static func snapshot(_ snapshot: AmbientSnapshot) -> [SpotlightRecord] {
        let deployments = snapshot.deployments.map { item in
            SpotlightRecord(
                kind: .deployment,
                identifier: item.trackingKey,
                title: item.projectName,
                subtitle: "\(item.provider.displayName) · \(item.state.displayName)",
                keywords: [item.projectName, item.provider.displayName, item.statusText, "deploy"]
            )
        }
        let domains = snapshot.domains.map { domain in
            SpotlightRecord(
                kind: .domain,
                identifier: domain.name.lowercased(),
                title: domain.name,
                subtitle: "Expires \(domain.expiresAt.formatted(date: .abbreviated, time: .omitted))",
                keywords: [domain.name, "domain", "expiry"]
            )
        }
        return deployments + domains
    }

    static func route(forUniqueIdentifier identifier: String) -> AmbientRoute {
        if identifier.hasPrefix("\(SpotlightRecord.Kind.domain.rawValue):") {
            return .workspace(.registrars)
        }
        if identifier.hasPrefix("\(SpotlightRecord.Kind.deployment.rawValue):") {
            return .latestDeploy
        }
        return .workspace(.hosting)
    }
}

nonisolated enum AmbientSpotlightIndex {
    static func replace(domain: String, with records: [SpotlightRecord]) {
#if canImport(CoreSpotlight)
        let items = records.map { record -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = record.title
            attributes.contentDescription = record.subtitle
            attributes.keywords = record.keywords
            return CSSearchableItem(
                uniqueIdentifier: record.uniqueIdentifier,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !items.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(items)
        }
#endif
    }

    static func indexProjects(_ projects: [Project]) {
        replace(domain: "\(SpotlightRecordBuilder.domainIdentifier).project", with: SpotlightRecordBuilder.projects(projects))
    }

    static func indexZones(_ zones: [CloudflareZone]) {
        replace(domain: "\(SpotlightRecordBuilder.domainIdentifier).zone", with: SpotlightRecordBuilder.zones(zones))
    }

    static func indexDomains(_ domains: [RegistrarDomain]) {
        replace(domain: "\(SpotlightRecordBuilder.domainIdentifier).domain", with: SpotlightRecordBuilder.domains(domains))
    }

    static func indexSnapshot(_ snapshot: AmbientSnapshot) {
        replace(domain: "\(SpotlightRecordBuilder.domainIdentifier).snapshot", with: SpotlightRecordBuilder.snapshot(snapshot))
    }
}
