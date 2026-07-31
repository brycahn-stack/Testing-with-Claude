import Foundation

/// Turns spoken lifting shorthand into structured sets.
///
/// This is rules, not a model, and that's a deliberate call: gym language is an
/// unusually rigid little grammar over a bounded vocabulary. "5x5 at 225",
/// "three sets of eight", "225 for 5", "8, 8, 6 at 185" — a handful of patterns
/// covers most of what anyone actually says between sets. So the useful half of
/// the Health tab ships today instead of waiting on an LLM.
///
/// The contract when it fails: **nothing is invented and nothing is lost.** An
/// unparsed memo yields no exercises, `WorkoutLog.isUnstructured` goes true, and
/// the Health tab shows the raw words. A wrong number in a training log is worse
/// than no number, because you'd train off it.
public enum SetExtractor {

    /// Below this, a leading number in "A x B" reads as a set count; at or above
    /// it, as a weight. An empty barbell is 45 lb, so 40 is a safe divide —
    /// nobody does 225 sets and nobody benches 5 lb.
    static let weightThreshold = 40.0

    // MARK: - Entry point

    public static func extract(from transcript: String) -> [LoggedExercise] {
        let text = normalize(transcript)
        let mentions = exerciseMentions(in: text)
        guard !mentions.isEmpty else { return [] }

        // Speech that names a unit wins; otherwise the user's preferred unit.
        let defaultUnit: WeightUnit = text.contains(" kg")
            ? .kilograms
            : HealthPreferences.defaultWeightUnit
        let nsText = text as NSString

        // Each exercise owns the text between its own name and the next one.
        var starts = mentions.map { $0.range.location + $0.range.length }
        var ends = (0..<mentions.count).map { index in
            index + 1 < mentions.count ? mentions[index + 1].range.location : nsText.length
        }

        // Except for a trailing "4 sets of" — in "…and 4 sets of dips" that
        // count belongs to the exercise that *follows* it, not the one before.
        for index in 0..<max(0, mentions.count - 1) {
            let upToNext = nsText.substring(to: ends[index])
            guard let match = danglingCountRegex?.firstMatch(
                    in: upToNext,
                    range: NSRange(location: 0, length: (upToNext as NSString).length)),
                  match.range.location >= starts[index]
            else { continue }
            ends[index] = match.range.location
            starts[index + 1] = match.range.location
        }

        var exercises: [LoggedExercise] = []
        for (index, mention) in mentions.enumerated() {
            var segment = ends[index] > starts[index]
                ? nsText.substring(with: NSRange(location: starts[index], length: ends[index] - starts[index]))
                : ""

            // "did 5x5 squats at 225" puts the numbers *before* the name. Only
            // the first exercise can own that prefix — after that, text between
            // two names belongs to the one it follows.
            if index == 0, mention.range.location > 0 {
                segment = nsText.substring(to: mention.range.location) + " " + segment
            }

            let sets = parseSets(in: segment, defaultUnit: defaultUnit)
            guard !sets.isEmpty else { continue }
            exercises.append(LoggedExercise(name: mention.name, sets: sets))
        }

        return exercises
    }

    /// "4 sets of " sitting immediately before an exercise name.
    private static let danglingCountRegex = try? NSRegularExpression(
        pattern: #"\d+\s+(?:sets?|reps?)\s+of\s+$"#
    )

    // MARK: - Set parsing

    /// Runs the patterns most-specific first, blanking each match so later
    /// patterns can't double-count the same digits.
    static func parseSets(in segment: String, defaultUnit: WeightUnit) -> [ExerciseSet] {
        var working = segment
        /// Sets tagged with where they were found, so the final order matches
        /// the order they were spoken rather than the order patterns ran.
        var located: [(location: Int, set: ExerciseSet)] = []

        func unit(_ token: String?) -> WeightUnit {
            switch token {
            case "kg": return .kilograms
            case "lb": return .pounds
            default:   return defaultUnit
            }
        }

        // (a) "8 , 8 , 6 @ 185" — a rep list sharing one weight.
        consume(#"((?:\d+\s+,\s+)+\d+)\s+@\s+(\d+(?:\.\d+)?)(?:\s+(lb|kg))?"#, in: &working) { groups, location in
            guard let list = groups[1], let weight = groups[2].flatMap(Double.init) else { return }
            let reps = list.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            for rep in reps {
                located.append((location, ExerciseSet(reps: rep, weight: weight, unit: unit(groups[3]))))
            }
        }

        // (b) "5 x 5 @ 225" — sets × reps at a weight.
        consume(#"(\d+)\s+x\s+(\d+)\s+@\s+(\d+(?:\.\d+)?)(?:\s+(lb|kg))?"#, in: &working) { groups, location in
            guard let count = groups[1].flatMap(Int.init),
                  let reps = groups[2].flatMap(Int.init),
                  let weight = groups[3].flatMap(Double.init), count <= 20 else { return }
            for _ in 0..<count {
                located.append((location, ExerciseSet(reps: reps, weight: weight, unit: unit(groups[4]))))
            }
        }

        // (d) "3 sets of 8 @ 185" / "3 sets of 8".
        consume(#"(\d+)\s+sets?\s+of\s+(\d+)(?:\s+@\s+(\d+(?:\.\d+)?))?(?:\s+(lb|kg))?"#, in: &working) { groups, location in
            guard let count = groups[1].flatMap(Int.init),
                  let reps = groups[2].flatMap(Int.init), count <= 20 else { return }
            let weight = groups[3].flatMap(Double.init)
            for _ in 0..<count {
                located.append((location, ExerciseSet(reps: reps, weight: weight, unit: unit(groups[4]))))
            }
        }

        // (e) "225 for 5" — one set, weight first. Universal gym shorthand.
        consume(#"(\d+(?:\.\d+)?)(?:\s+(lb|kg))?\s+for\s+(\d+)"#, in: &working) { groups, location in
            guard let weight = groups[1].flatMap(Double.init),
                  let reps = groups[3].flatMap(Int.init) else { return }
            located.append((location, ExerciseSet(reps: reps, weight: weight, unit: unit(groups[2]))))
        }

        // (c) Bare "A x B". The threshold decides which number is which:
        // "225 x 5" is a weight for five reps; "5 x 5" is five sets of five.
        consume(#"(\d+(?:\.\d+)?)\s+x\s+(\d+)(?:\s+(lb|kg))?"#, in: &working) { groups, location in
            guard let first = groups[1].flatMap(Double.init),
                  let second = groups[2].flatMap(Int.init) else { return }
            if first >= weightThreshold {
                located.append((location, ExerciseSet(reps: second, weight: first, unit: unit(groups[3]))))
            } else if Int(first) <= 20 {
                for _ in 0..<Int(first) {
                    located.append((location, ExerciseSet(reps: second, weight: nil, unit: unit(groups[3]))))
                }
            }
        }

        // (g) "12 reps" / "12 reps @ 95".
        consume(#"(\d+)\s+reps?(?:\s+@\s+(\d+(?:\.\d+)?))?(?:\s+(lb|kg))?"#, in: &working) { groups, location in
            guard let reps = groups[1].flatMap(Int.init) else { return }
            located.append((location, ExerciseSet(reps: reps, weight: groups[2].flatMap(Double.init), unit: unit(groups[3]))))
        }

        // (f) "4 sets" with no rep count — the set happened, reps unknown.
        consume(#"(\d+)\s+sets?\b"#, in: &working) { groups, location in
            guard let count = groups[1].flatMap(Int.init), count <= 20 else { return }
            for _ in 0..<count {
                located.append((location, ExerciseSet(reps: nil, weight: nil, unit: defaultUnit)))
            }
        }

        var sets = located.sorted { $0.location < $1.location }.map(\.set)

        // (i) Nothing matched, but one lone number sits next to the name:
        // "did 20 pushups" is twenty reps, "squat 225" is a weight. The
        // threshold decides which, the same way it does for "A x B".
        if sets.isEmpty {
            guard let (value, unit) = loneNumber(in: working) else { return [] }
            return value >= weightThreshold
                ? [ExerciseSet(reps: nil, weight: value, unit: unit ?? defaultUnit)]
                : [ExerciseSet(reps: Int(value), weight: nil, unit: unit ?? defaultUnit)]
        }

        // (h) "5 sets of squats at 225" leaves the weight stranded after the
        // name. If exactly one weight is left over, it belongs to the sets that
        // didn't get one.
        if sets.contains(where: { $0.weight == nil }),
           let (stranded, strandedUnit) = strandedWeight(in: working, defaultUnit: defaultUnit) {
            for index in sets.indices where sets[index].weight == nil {
                sets[index].weight = stranded
                sets[index].unit = strandedUnit
            }
        }

        return sets
    }

    /// A weight left in the segment after every set pattern has taken its share.
    ///
    /// Tried most-explicit first. The bare-number pass is last and only accepts
    /// values at or above the threshold, so "bench 3x8 185" finds its weight
    /// while "rested 2 minutes" is ignored.
    private static func strandedWeight(in text: String, defaultUnit: WeightUnit) -> (Double, WeightUnit)? {
        let passes: [(pattern: String, bare: Bool)] = [
            (#"@\s+(\d+(?:\.\d+)?)(?:\s+(lb|kg))?"#, false),
            (#"(\d+(?:\.\d+)?)\s+(lb|kg)\b"#, false),
            (#"(?<![\d.])(\d+(?:\.\d+)?)(?![\d.])"#, true)
        ]

        for pass in passes {
            var candidates: [(Double, WeightUnit)] = []
            enumerate(pass.pattern, in: text) { groups, _ in
                guard let value = groups[1].flatMap(Double.init) else { return }
                guard !pass.bare || value >= weightThreshold else { return }
                candidates.append((value, namedUnit(groups[2]) ?? defaultUnit))
            }
            // More than one leftover weight is ambiguous — better to attach none
            // than to attach the wrong one.
            if candidates.count == 1 { return candidates[0] }
        }
        return nil
    }

    /// Exactly one number left in a segment, or nil if there are none or several.
    private static func loneNumber(in text: String) -> (Double, WeightUnit?)? {
        var candidates: [(Double, WeightUnit?)] = []
        enumerate(#"(?<![\d.])(\d+(?:\.\d+)?)(?![\d.])(?:\s+(lb|kg))?"#, in: text) { groups, _ in
            guard let value = groups[1].flatMap(Double.init) else { return }
            candidates.append((value, namedUnit(groups[2])))
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func namedUnit(_ token: String?) -> WeightUnit? {
        switch token {
        case "kg": return .kilograms
        case "lb": return .pounds
        default:   return nil
        }
    }

    // MARK: - Exercise vocabulary

    struct Mention {
        let name: String
        let range: NSRange
    }

    /// Canonical name → the ways people say it. Hyphens are normalized to
    /// spaces before matching, so "pull-ups" and "pull ups" are the same key.
    static let vocabulary: [String: [String]] = [
        "Squat": ["squat", "squats", "back squat", "back squats", "squatted"],
        "Front Squat": ["front squat", "front squats"],
        "Bench Press": ["bench", "benched", "bench press", "flat bench", "bench presses"],
        "Incline Bench Press": ["incline bench", "incline press", "incline bench press"],
        "Deadlift": ["deadlift", "deadlifts", "deadlifted", "deads"],
        "Romanian Deadlift": ["romanian deadlift", "romanian deadlifts", "rdl", "rdls"],
        "Overhead Press": ["overhead press", "ohp", "military press", "shoulder press", "strict press"],
        "Barbell Row": ["barbell row", "barbell rows", "bent over row", "bent over rows"],
        "Dumbbell Row": ["dumbbell row", "dumbbell rows", "db row", "db rows"],
        "Pull Up": ["pull up", "pull ups", "pullup", "pullups"],
        "Chin Up": ["chin up", "chin ups", "chinup", "chinups"],
        "Push Up": ["push up", "push ups", "pushup", "pushups"],
        "Dip": ["dip", "dips"],
        "Lunge": ["lunge", "lunges", "walking lunge", "walking lunges"],
        "Leg Press": ["leg press", "leg presses"],
        "Leg Curl": ["leg curl", "leg curls", "hamstring curl", "hamstring curls"],
        "Leg Extension": ["leg extension", "leg extensions", "quad extension", "quad extensions"],
        "Calf Raise": ["calf raise", "calf raises"],
        "Bicep Curl": ["curl", "curls", "bicep curl", "bicep curls", "barbell curl", "dumbbell curl"],
        "Tricep Extension": ["tricep extension", "tricep extensions", "skull crusher",
                             "skull crushers", "tricep pushdown", "pushdown", "pushdowns"],
        "Lat Pulldown": ["lat pulldown", "lat pulldowns", "pulldown", "pulldowns"],
        "Face Pull": ["face pull", "face pulls"],
        "Hip Thrust": ["hip thrust", "hip thrusts"],
        "Lateral Raise": ["lateral raise", "lateral raises", "side raise", "side raises", "lat raise"],
        "Plank": ["plank", "planks"]
    ]

    /// Aliases longest-first, so "front squat" claims the text before "squat"
    /// can, and "incline bench" beats "bench".
    private static let aliasesByLength: [(alias: String, name: String)] = {
        vocabulary
            .flatMap { name, aliases in aliases.map { (alias: $0, name: name) } }
            .sorted { $0.alias.count > $1.alias.count }
    }()

    /// Every exercise named in the text, in the order they were spoken and with
    /// no two claiming the same characters.
    static func exerciseMentions(in text: String) -> [Mention] {
        var claimed: [NSRange] = []
        var mentions: [Mention] = []

        for entry in aliasesByLength {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: entry.alias) + #"\b"#
            enumerate(pattern, in: text) { _, range in
                let overlaps = claimed.contains { NSIntersectionRange($0, range).length > 0 }
                guard !overlaps else { return }
                claimed.append(range)
                mentions.append(Mention(name: entry.name, range: range))
            }
        }

        return mentions.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Normalization

    /// Speech into something the patterns can read: digits instead of words,
    /// spaced separators, one spelling per unit.
    static func normalize(_ text: String) -> String {
        var result = text.lowercased()

        // Hyphens and dashes are word joiners here, not punctuation.
        for dash in ["-", "–", "—"] {
            result = result.replacingOccurrences(of: dash, with: " ")
        }
        result = result.replacingOccurrences(of: "×", with: " x ")

        // Separators get their own space so patterns can rely on \s+.
        for symbol in ["@", ","] {
            result = result.replacingOccurrences(of: symbol, with: " \(symbol) ")
        }
        // A period between digits is a decimal; anywhere else it's punctuation.
        result = replacing(#"(?<!\d)\.(?!\d)"#, in: result, with: " ")
        for symbol in ["!", "?", ";", ":"] {
            result = result.replacingOccurrences(of: symbol, with: " ")
        }

        // One spelling per unit.
        result = replacing(#"\b(pounds|pound|lbs|lb)\b"#, in: result, with: "lb")
        result = replacing(#"\b(kilograms|kilogram|kilos|kilo|kgs|kg)\b"#, in: result, with: "kg")

        // "at" and "times"/"by" are spoken forms of "@" and "x".
        result = replacing(#"\bat\b"#, in: result, with: "@")
        result = replacing(#"\btimes\b"#, in: result, with: "x")
        result = replacing(#"\bby\b"#, in: result, with: "x")

        result = numbersFromWords(result)
        // "5x5" has no spaces to rely on until we add them.
        result = replacing(#"(\d)\s*x\s*(\d)"#, in: result, with: "$1 x $2")
        result = combineSpokenNumbers(result)

        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100
    ]

    static func numbersFromWords(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                numberWords[String(word)].map(String.init) ?? String(word)
            }
            .joined(separator: " ")
    }

    /// Rebuilds numbers people speak in pieces: "two twenty five" → 225,
    /// "one hundred thirty five" → 135, "twenty five" → 25.
    ///
    /// Only fires on *adjacent* numeric tokens where the middle is a round ten,
    /// which is what keeps "3 sets of 8" from collapsing into 38.
    static func combineSpokenNumbers(_ text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        var output: [String] = []
        var index = 0

        func number(_ offset: Int) -> Int? {
            guard index + offset < tokens.count else { return nil }
            return Int(tokens[index + offset])
        }
        func isRoundTen(_ value: Int?) -> Bool {
            guard let value else { return false }
            return value >= 20 && value <= 90 && value % 10 == 0
        }
        func isDigit(_ value: Int?) -> Bool {
            guard let value else { return false }
            return value >= 1 && value <= 9
        }

        while index < tokens.count {
            guard let head = number(0) else {
                output.append(tokens[index])
                index += 1
                continue
            }

            // "two hundred twenty five" → 2, 100, 20, 5
            if isDigit(head), number(1) == 100 {
                var value = head * 100
                var consumed = 2
                if isRoundTen(number(2)) {
                    value += number(2) ?? 0
                    consumed += 1
                    if isDigit(number(3)) { value += number(3) ?? 0; consumed += 1 }
                } else if isDigit(number(2)) {
                    value += number(2) ?? 0
                    consumed += 1
                }
                output.append(String(value))
                index += consumed
                continue
            }

            // "two twenty five" → 225
            if isDigit(head), isRoundTen(number(1)) {
                var value = head * 100 + (number(1) ?? 0)
                var consumed = 2
                if isDigit(number(2)) { value += number(2) ?? 0; consumed += 1 }
                output.append(String(value))
                index += consumed
                continue
            }

            // "twenty five" → 25
            if isRoundTen(head), isDigit(number(1)) {
                output.append(String(head + (number(1) ?? 0)))
                index += 2
                continue
            }

            output.append(tokens[index])
            index += 1
        }

        return output.joined(separator: " ")
    }

    // MARK: - Regex helpers

    /// Runs `body` for each match, then blanks the matched ranges so the next
    /// pattern can't reuse the same digits. Blanks are equal-length, so ranges
    /// stay valid.
    private static func consume(
        _ pattern: String,
        in text: inout String,
        body: ([Int: String], Int) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !results.isEmpty else { return }

        for result in results {
            var groups: [Int: String] = [:]
            for index in 1..<result.numberOfRanges where result.range(at: index).location != NSNotFound {
                groups[index] = nsText.substring(with: result.range(at: index))
            }
            body(groups, result.range.location)
        }

        let mutable = NSMutableString(string: text)
        for result in results.reversed() {
            mutable.replaceCharacters(in: result.range,
                                      with: String(repeating: " ", count: result.range.length))
        }
        text = mutable as String
    }

    /// Read-only pass over matches.
    private static func enumerate(
        _ pattern: String,
        in text: String,
        body: ([Int: String], NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        for result in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            var groups: [Int: String] = [:]
            for index in 1..<result.numberOfRanges where result.range(at: index).location != NSNotFound {
                groups[index] = nsText.substring(with: result.range(at: index))
            }
            body(groups, result.range)
        }
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }
}

// MARK: - Meals

/// The meal counterpart, deliberately thin.
///
/// Meals are the opposite of training: they have a real home in HealthKit (an
/// `HKCorrelation` of type `.food`), but the numbers are much harder to hear —
/// "a chicken salad" carries no calorie count, and guessing one would be worse
/// than leaving it blank. So this picks up only what was explicitly said and
/// leaves the rest for the model.
public enum NutritionExtractor {
    public static func extract(from transcript: String) -> Nutrition {
        let text = SetExtractor.normalize(transcript)
        return Nutrition(
            calories: value(in: text, patterns: [#"(\d+(?:\.\d+)?)\s+calories"#, #"(\d+(?:\.\d+)?)\s+cals?\b"#]),
            proteinGrams: grams(of: "protein", in: text),
            carbGrams: grams(of: "carbs?|carbohydrates?", in: text),
            fatGrams: grams(of: "fat", in: text)
        )
    }

    /// "forty grams of protein" and "protein was 40 grams" both count.
    private static func grams(of nutrient: String, in text: String) -> Double? {
        value(in: text, patterns: [
            #"(\d+(?:\.\d+)?)\s+g(?:rams)?\s+of\s+(?:\#(nutrient))"#,
            #"(?:\#(nutrient))\s+(?:was\s+|@\s+)?(\d+(?:\.\d+)?)\s*g(?:rams)?"#
        ])
    }

    private static func value(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
                  match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound
            else { continue }
            if let value = Double(nsText.substring(with: match.range(at: 1))) { return value }
        }
        return nil
    }
}
