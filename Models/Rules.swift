import Foundation

/// The steelmanning discipline from the project README — when to do it,
/// the hard line, and the honesty rules that keep it from becoming debate club.
struct SteelmanRule: Identifiable, Hashable {
    let id: Int
    let title: String
    let body: String
    let section: Section

    enum Section: String, CaseIterable, Identifiable {
        case when = "When there's something real"
        case stillWorthIt = "Still worth it"
        case hardLine = "The hard line"
        case honesty = "Keep it honest"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .when: return "sparkles"
            case .stillWorthIt: return "lightbulb.fill"
            case .hardLine: return "hand.raised.fill"
            case .honesty: return "checkmark.seal.fill"
            }
        }
    }
}

enum SteelmanRules {
    static let all: [SteelmanRule] = [
        SteelmanRule(
            id: 1,
            title: "Both sides have a defensible core",
            body: "If smart, honest people land on different sides, there's something worth building. Go for it.",
            section: .when
        ),
        SteelmanRule(
            id: 2,
            title: "You can't guess how it ends",
            body: "If the strongest version might actually surprise you or change your confidence, that's the good stuff.",
            section: .when
        ),
        SteelmanRule(
            id: 3,
            title: "It makes you roll your eyes",
            body: "The views you dismiss fastest are the ones where you've probably never heard the best version. Eye-rolling is a green light, not a red one.",
            section: .when
        ),
        SteelmanRule(
            id: 4,
            title: "\"Obvious\" stuff is worth arguing for",
            body: "You might believe vaccines work or the moon landing happened—but can you actually make the case? Defending the consensus turns a borrowed belief into one you own.",
            section: .stillWorthIt
        ),
        SteelmanRule(
            id: 5,
            title: "False beliefs still teach you something",
            body: "Don't steelman that the earth is flat. Steelman why a reasonable person, trusting their own eyes, once concluded it was. The factual case dies; the lesson about how honest people get fooled survives.",
            section: .stillWorthIt
        ),
        SteelmanRule(
            id: 6,
            title: "If the strongest honest version IS the harm, stop",
            body: "Most uncomfortable ideas have a real core worth digging out. But a few have no separable core—the best version is still just the thing itself. When it's fully built, is it an idea or a weapon? If it's a weapon, you've left the realm of thinking.",
            section: .hardLine
        ),
        SteelmanRule(
            id: 7,
            title: "You don't get your opinion until you've earned it",
            body: "You can't state your real position until you've steelmanned the other side to that side's satisfaction—built their case well enough that someone who actually holds it would say \"yes, that's what I mean.\"",
            section: .honesty
        ),
        SteelmanRule(
            id: 8,
            title: "Every steelman has to meet its strongest rebuttal",
            body: "Building the best version of an argument isn't the finish line—you have to walk it up to the hardest objection and answer that too. A steelman that quietly avoids the one thing that would break it is just a nicer-sounding strawman.",
            section: .honesty
        ),
    ]

    static func rules(in section: SteelmanRule.Section) -> [SteelmanRule] {
        all.filter { $0.section == section }
    }
}
