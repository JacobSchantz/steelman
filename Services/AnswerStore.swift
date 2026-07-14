import Foundation
import SwiftUI

@MainActor
final class AnswerStore: ObservableObject {
    @Published private(set) var answers: [Answer] = []

    private let fileURL: URL
    private let audioDir: URL
    private let encoder = JSONEncoder.steelman
    private let decoder = JSONDecoder.steelman

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("steelman_answers.json")
        audioDir = docs.appendingPathComponent("AnswerAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        load()
        if answers.isEmpty {
            answers = Self.seedAnswers
            persist()
        }
    }

    func answers(for questionId: UUID) -> [Answer] {
        answers.filter { $0.questionId == questionId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func answer(id: UUID) -> Answer? {
        answers.first { $0.id == id }
    }

    func audioURL(for answer: Answer) -> URL? {
        guard let name = answer.audioFileName else { return nil }
        let url = audioDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Destination path for a new recording.
    func makeAudioFileURL(for answerId: UUID, ext: String = "m4a") -> URL {
        audioDir.appendingPathComponent("\(answerId.uuidString).\(ext)")
    }

    func save(_ answer: Answer) {
        if let i = answers.firstIndex(where: { $0.id == answer.id }) {
            answers[i] = answer
        } else {
            answers.insert(answer, at: 0)
        }
        persist()
        objectWillChange.send()
    }

    func delete(_ answer: Answer) {
        if let name = answer.audioFileName {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(name))
        }
        answers.removeAll { $0.id == answer.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([Answer].self, from: data) else {
            answers = []
            return
        }
        answers = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(answers) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Seed answers for both sides of each seed question (text-only; TTS in Discover).
    static let seedAnswers: [Answer] = {
        let q1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let q2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let q3 = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        return [
            Answer(
                questionId: q1, claimedSide: .a,
                text: "Banning weekday cars downtown reclaims public space for people, cuts pollution where density is highest, and makes transit and walking the default. Cities that tried it saw calmer streets and more foot traffic for local shops. Emergency and disability access can be designed in with permits — the point is ending default car priority, not trapping residents.",
                analysis: AnswerAnalysis(
                    leanSide: .a, leanConfidence: 0.92,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Argues for reclaiming streets and reducing pollution via a weekday ban."
                )
            ),
            Answer(
                questionId: q1, claimedSide: .b,
                text: "A downtown car ban punishes people who can't easily switch — night-shift workers, parents with gear, small businesses that need deliveries, and disabled drivers when paratransit is thin. Congestion just moves to ring roads. Better tools: congestion pricing, better transit, and targeted delivery windows — without a blanket ban that treats every car trip as frivolous.",
                analysis: AnswerAnalysis(
                    leanSide: .b, leanConfidence: 0.9,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Argues bans harm workers and businesses; prefers pricing and transit."
                )
            ),
            Answer(
                questionId: q1, claimedSide: .a,
                text: "We already ban lots of things in dense cores for collective benefit — smoking, loud industry, trucks on residential streets. Cars are the last sacred cow. A weekday ban is reversible policy, not permanent exile; measure retail sales and air quality and adjust. The strongest honest version of the ban isn't anti-car — it's pro-city.",
                analysis: AnswerAnalysis(
                    leanSide: .a, leanConfidence: 0.88,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Frames the ban as normal urban regulation and empirically reversible."
                )
            ),
            Answer(
                questionId: q1, claimedSide: .b,
                text: "If the goal is cleaner air and safer streets, enforce existing rules: speed limits, truck routes, bus lanes. A full ban is politically brittle and invites black-market drop-offs at the boundary. Steelmanning the ban's best case still leaves a fairness problem: who gets the scarce exceptions, and who decides?",
                analysis: AnswerAnalysis(
                    leanSide: .b, leanConfidence: 0.86,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Prefers enforcement of existing rules over a brittle total ban."
                )
            ),
            Answer(
                questionId: q2, claimedSide: .a,
                text: "Remote-first respects focus work, cuts commute dead time, and expands the talent pool beyond coastal rent prices. The strongest case for the office — spontaneous mentorship — can be scheduled and measured instead of assumed from proximity. Most knowledge work is async writing and code review; the office is a habit, not a law of nature.",
                analysis: AnswerAnalysis(
                    leanSide: .a, leanConfidence: 0.9,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Defends remote-first for focus, equity of location, and async work."
                )
            ),
            Answer(
                questionId: q2, claimedSide: .b,
                text: "Junior people learn by overhearing, and trust forms in unscheduled hallway time. Fully remote companies often reintroduce offices under new names — offsites, hubs — because coordination cost is real. The strongest case for office-first is not surveillance; it's apprenticeship and culture that text can't fully carry.",
                analysis: AnswerAnalysis(
                    leanSide: .b, leanConfidence: 0.89,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Defends office-first for apprenticeship, trust, and coordination."
                )
            ),
            Answer(
                questionId: q3, claimedSide: .a,
                text: "Platforms already age-gate alcohol ads and payments; verifying age for adult content and social feeds is continuous with that duty of care. Kids cannot meaningfully consent to addictive design. Privacy risks are real, but they're engineerable — government ID tokens, zero-knowledge proofs — not an argument for zero duty.",
                analysis: AnswerAnalysis(
                    leanSide: .a, leanConfidence: 0.87,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Supports age verification as an extension of existing platform duties."
                )
            ),
            Answer(
                questionId: q3, claimedSide: .b,
                text: "Mandatory ID checks create a honeypot of identity data, chill anonymous speech, and fail against determined teens with a VPN. The strongest honest version of verification still centralizes power in platforms and governments. Better: default private accounts for minors, parental tools, and design limits — without turning the open web into a checkpoint.",
                analysis: AnswerAnalysis(
                    leanSide: .b, leanConfidence: 0.91,
                    containsProfanity: false, profanityScore: 0,
                    summary: "Opposes mandates; prefers design and parental tools over ID checkpoints."
                )
            ),
        ]
    }()
}
