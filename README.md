# Steelmanning Rules

*Steelmanning = building the strongest honest version of an argument before you judge it. Here's when it's worth doing and where we draw the line.*

## Do it when there's something real to reconstruct

1. **Both sides have a defensible core.** If smart, honest people land on different sides, there's something worth building. Go for it.

2. **You can't guess how it ends.** If the strongest version might actually surprise you or change your confidence, that's the good stuff.

3. **It makes you roll your eyes.** The views you dismiss fastest are the ones where you've probably never heard the best version. Eye-rolling is a green light, not a red one.

## Still worth it, even when one side clearly wins

4. **"Obvious" stuff is worth arguing for.** You might *believe* vaccines work or the moon landing happened—but can you actually make the case? Defending the consensus turns a borrowed belief into one you own. Knowing you're right isn't the same as knowing *why*.

5. **False beliefs still teach you something—about reasoning.** Don't steelman *that the earth is flat*. Steelman *why a reasonable person, trusting their own eyes, once concluded it was.* The factual case dies; the lesson about how honest people get fooled survives. That lesson includes humility about your own beliefs.

## The one hard line

6. **If the strongest honest version IS the harm, stop.** Most uncomfortable, taboo, or offensive ideas have a real core worth digging out—don't flinch from those, that's just cowardice dressed up as caution. But a few things have no separable core: the best version of "this group should be eliminated" is still just the thing itself. You're not uncovering insight, you're writing propaganda with better grammar. The test: when it's fully built, is it an *idea* or a *weapon*? If it's a weapon, you've left the realm of thinking.

## The two rules that keep it honest

These aren't about *when* to steelman—they're the discipline that separates this from a debate club where people just dig in.

7. **You don't get your opinion until you've earned it.** You can't state your real position until you've steelmanned the other side *to that side's satisfaction*—built their case well enough that someone who actually holds it would say "yes, that's what I mean." Until then you haven't understood the thing you're disagreeing with; you've only understood your version of it.

8. **Every steelman has to meet its strongest rebuttal, or it doesn't count.** Building the best version of an argument isn't the finish line—you have to walk it up to the hardest objection and answer that too. A steelman that quietly avoids the one thing that would break it is just a nicer-sounding strawman of your own side.

## The quick gut-check before you post

- Is there a real second side, or is one side just an error? *(Error = skip, or steelman the reasoning, not the claim.)*
- Will building this teach me something—even just how to argue better?
- When it's done, is it something you'd hand someone as a reason to *act*? If that thought is alarming, that's your answer.

---

*Bottom line: go almost everywhere. Discomfort isn't the limit—harm is. The line isn't "topics we don't touch," it's "the point where the strongest version stops being a thought and starts being ammunition."*

---

## iOS app

Native SwiftUI app whose core loop is **Discover** — the same full-screen vertical feed + now-playing chrome as keepMovin's Discover tab, but every card is one viewpoint on a question.

### Product

| Surface | Role |
|---|---|
| **Discover** | Vertical feed of argument clips. Hear side A → must hear side B (for that question) before A again. Text answers play via TTS; audio answers play as files. |
| **Questions** | Browse / add debate prompts with two side labels. |
| **Answer** | Submit text and/or **on-device dictation** (Apple Speech / same approach as ATG `speech_to_text`); OpenRouter AI scores **lean side** + **profanity**. |
| **Rules** | The eight steelmanning rules. |

### Alternating-side rule

`ArgumentDeckBuilder` only enqueues an answer for a question when its side is allowed under the last-heard side for that question. The feed is ordered so you never get the same side twice in a row for the same prompt without the opposite in between.

### AI analysis

`AnswerAnalysisService` calls OpenRouter (`openai/gpt-4o-mini`) when a token is saved in Keychain (Answer tab → OpenRouter token). Without a token, a local heuristic still classifies lean + basic profanity so the app works offline.

### KeepMovin ports

- Full-screen `scrollTargetBehavior(.viewAligned)` feed
- `NowPlayingContent` + `BufferedScrubber` player chrome
- `ClipPreviewPlayer` (segment cache / preload / transport)
- `ArgumentDeckCache` (snapshot + segment pre-download)

### Build

```bash
xcodegen generate
open Steelman.xcodeproj

# Device (testables)
testables build ios
# or: ./build_local.sh
```

- **Bundle ID:** `com.steelman.app`
- **Testables path:** `testables/`
- **PAT key:** `github_pat_for_steelman_testables`
