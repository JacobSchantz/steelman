import Foundation

/// OpenRouter-backed analysis: profanity + which side of the question the answer leans toward.
/// Token storage mirrors keepMovin's AIRecommendationService (Keychain).
@MainActor
final class AnswerAnalysisService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private static let tokenKey = "openrouter_api_token"
    private static let model = "openai/gpt-4o-mini"

    static var apiToken: String? {
        get {
            if let legacy = UserDefaults.standard.string(forKey: tokenKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
                TokenKeychain.set(legacy, for: tokenKey)
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
            let value = TokenKeychain.get(tokenKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                TokenKeychain.set(trimmed, for: tokenKey)
            } else {
                TokenKeychain.delete(tokenKey)
            }
            UserDefaults.standard.removeObject(forKey: tokenKey)
        }
    }

    static var hasToken: Bool { apiToken != nil }

    /// Analyze text for lean + profanity. Falls back to heuristic if no token.
    func analyze(
        question: Question,
        text: String,
        claimedSide: ArgumentSide?
    ) async -> AnswerAnalysis {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AnswerAnalysis(
                leanSide: claimedSide ?? .a,
                leanConfidence: 0.2,
                containsProfanity: false,
                profanityScore: 0,
                summary: "Empty answer."
            )
        }

        if let token = Self.apiToken {
            do {
                return try await Self.fetchAnalysis(
                    token: token,
                    question: question,
                    text: trimmed
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        return Self.heuristicAnalysis(question: question, text: trimmed, claimedSide: claimedSide)
    }

    // MARK: - Network

    private static func fetchAnalysis(
        token: String,
        question: Question,
        text: String
    ) async throws -> AnswerAnalysis {
        let system = """
        You classify short debate answers. Return ONLY valid JSON with keys:
        lean_side ("a" or "b"), lean_confidence (0-1), contains_profanity (bool),
        profanity_score (0-1), summary (one short sentence).
        Side a is: \(question.sideALabel)
        Side b is: \(question.sideBLabel)
        Judge lean by the strongest honest reading of the answer's position, not mere mention.
        Flag profanity for slurs, sexual content, or aggressive swear-heavy abuse — not mild frustration.
        """

        let user = """
        Question: \(question.prompt)

        Answer:
        \(text)
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/JacobSchantz/steelman", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Steelman", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.serverError(http.statusCode, detail)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: contentData) as? [String: Any]
        else {
            throw AnalysisError.invalidResponse
        }

        let leanRaw = (json["lean_side"] as? String)?.lowercased() ?? "a"
        let lean: ArgumentSide = leanRaw.hasPrefix("b") ? .b : .a
        let conf = (json["lean_confidence"] as? Double)
            ?? (json["lean_confidence"] as? Int).map(Double.init)
            ?? 0.5
        let profane = json["contains_profanity"] as? Bool ?? false
        let pScore = (json["profanity_score"] as? Double)
            ?? (json["profanity_score"] as? Int).map(Double.init)
            ?? (profane ? 0.8 : 0)
        let summary = json["summary"] as? String ?? "Analyzed answer."

        return AnswerAnalysis(
            leanSide: lean,
            leanConfidence: min(max(conf, 0), 1),
            containsProfanity: profane,
            profanityScore: min(max(pScore, 0), 1),
            summary: summary
        )
    }

    /// Offline / no-token fallback so the app stays usable.
    private static func heuristicAnalysis(
        question: Question,
        text: String,
        claimedSide: ArgumentSide?
    ) -> AnswerAnalysis {
        let lower = text.lowercased()
        let profanityList = ["fuck", "shit", "asshole", "bitch", "cunt", "nigger", "faggot"]
        let hits = profanityList.filter { lower.contains($0) }.count
        let contains = hits > 0

        let aWords = question.sideALabel.lowercased().split(separator: " ").map(String.init)
        let bWords = question.sideBLabel.lowercased().split(separator: " ").map(String.init)
        let aScore = aWords.filter { lower.contains($0) }.count
        let bScore = bWords.filter { lower.contains($0) }.count

        let lean: ArgumentSide
        let conf: Double
        if aScore != bScore {
            lean = aScore > bScore ? .a : .b
            conf = 0.55
        } else if let claimed = claimedSide {
            lean = claimed
            conf = 0.45
        } else {
            lean = .a
            conf = 0.3
        }

        return AnswerAnalysis(
            leanSide: lean,
            leanConfidence: conf,
            containsProfanity: contains,
            profanityScore: contains ? min(0.4 + Double(hits) * 0.2, 1) : 0,
            summary: "Heuristic lean toward \(question.label(for: lean)) (no AI token)."
        )
    }

    enum AnalysisError: LocalizedError {
        case invalidResponse
        case serverError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The AI returned an unexpected response."
            case .serverError(let code, let detail):
                return "OpenRouter error (\(code)): \(detail)"
            }
        }
    }
}
