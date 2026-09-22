import Foundation

enum AccountProvider: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case vercel
    case cloudflare
    case netlify
    case railway
    case render
    case digitalOcean
    case heroku
    case fly
    case firebase
    case awsAmplify

    var id: Self { self }

    var displayName: String {
        switch self {
        case .vercel: "Vercel"
        case .cloudflare: "Cloudflare"
        case .netlify: "Netlify"
        case .railway: "Railway"
        case .render: "Render"
        case .digitalOcean: "DigitalOcean"
        case .heroku: "Heroku"
        case .fly: "Fly.io"
        case .firebase: "Firebase"
        case .awsAmplify: "AWS Amplify"
        }
    }

    var isGenericHostingProvider: Bool {
        self != .vercel && self != .cloudflare
    }
}
