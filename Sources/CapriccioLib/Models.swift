//
//  Models.swift
//  SwiftGherkin
//
//  Created by iainsmith on 26/03/2018.
//

import Foundation
import Gherkin
import Consumer

private let __EXAMPLE_TAGS_KEY = "__EXAMPLE_TAGS"
private var __lastExampleKeys: [String]? = nil

/// A model that represents a single Gherkin feature file
extension Gherkin.Feature {
    public init(string: String) throws {
        guard let result = try gherkin.match(string).transform(_transform) as? Gherkin.Feature else {
            throw GherkinError.standard
        }

        let updatedScenarios: [Gherkin.Scenario] = result.scenarios.compactMap { scenario in
            var finalScenario: Gherkin.Scenario

            switch scenario {
            case let .simple(simpleScenario):
                finalScenario = Gherkin.Feature.include(featureTags: result.tags, on: simpleScenario)
            case let .outline(outlineScenario):
                finalScenario = Gherkin.Feature.include(featureTags: result.tags, on: outlineScenario)
            }

            return finalScenario
        }

        self.init(name: result.name, description: result.textDescription, scenarios: updatedScenarios, tags: result.tags)
    }

    public init(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw GherkinError.standard }
        try self.init(string: text)
    }

    private static func include(featureTags: [Gherkin.Tag]?, on simpleScenario: ScenarioSimple) -> Gherkin.Scenario {
        let newTags = merge(featureTags: featureTags, and: simpleScenario.tags)

        let newScenario = ScenarioSimple(name: simpleScenario.name,
                                         description: simpleScenario.textDescription,
                                         steps: simpleScenario.steps,
                                         tags: newTags)
        return Gherkin.Scenario.simple(newScenario)
    }

    private static func include(featureTags: [Gherkin.Tag]?, on outlineScenario: ScenarioOutline) -> Gherkin.Scenario {
        let newTags = merge(featureTags: featureTags, and: outlineScenario.tags)

        let newScenario = ScenarioOutline(name: outlineScenario.name,
                                          description: outlineScenario.textDescription,
                                          steps: outlineScenario.steps,
                                          examples: outlineScenario.examples,
                                          tags: newTags)
        return Gherkin.Scenario.outline(newScenario)
    }
    static func merge(featureTags: [Gherkin.Tag]?, and scenarioTags: [Gherkin.Tag]?) -> [Gherkin.Tag]? {
        return Array(scenarioTags ?? [] + (featureTags ?? []))
    }
}

enum GherkinError: Error {
    case standard
}


func _transform(label: GherkinLabel, values: [Any]) -> Any? {
    switch label {
    case .feature:
        let strings: [String] = filterd(values, is: String.self)!
        guard let name = strings.first else { return nil }
        var description: String? = values.safely(1) as? String ?? nil
        description?.trimWhitespace()
        let scenarios: [Gherkin.Scenario] = filterd(values, is: Gherkin.Scenario.self)!
        let tags: [Gherkin.Tag]? = filterd(values, is: Gherkin.Tag.self)
        let feature = Gherkin.Feature(name: name, description: description, scenarios: scenarios, tags: tags)
        return feature
    case .step:
        let name = StepName(rawValue: (values[0] as! String).lowercased())!
        let text = values[1] as! String
        return Gherkin.Step(name: name, text: text)
    case .scenario:
        let strings: [String] = filterd(values, is: String.self)!
        let name = strings[0]
        var description: String? = strings.safely(1) ?? nil
        description?.trimWhitespace()
        let steps: [Gherkin.Step] = filterd(values, is: Gherkin.Step.self)!
        let tags: [Gherkin.Tag]? = filterd(values, is: Gherkin.Tag.self)
        return Gherkin.Scenario.simple(ScenarioSimple(name: name, description: description, steps: steps, tags: tags))
    case .scenarioOutline:
        let strings: [String] = filterd(values, is: String.self)!
        let name = strings[0]
        var description: String? = strings.safely(1) ?? nil
        description?.trimWhitespace()
        let steps: [Gherkin.Step] = filterd(values, is: Gherkin.Step.self)!
        let tags: [Gherkin.Tag]? = filterd(values, is: Gherkin.Tag.self)
        if let tags, tags.compactMap({$0.name}).contains("ZHOMEIOS-2579") {
            print(tags)
        }

        let exampleGroups: [[Gherkin.Example]] = values.compactMap { $0 as? [Gherkin.Example] }
        let allExamples = exampleGroups.flatMap { $0 }
        __lastExampleKeys = nil

        return Gherkin.Scenario.outline(ScenarioOutline(name: name, description: description, steps: steps, examples: allExamples, tags: tags))
    case .name:
        return values.first
    case .description:
        return values.first
    case .examples:
        let exampleTags: [Gherkin.Tag] = filterd(values, is: Gherkin.Tag.self) ?? []

        let stringArrays: [[String]] = values.compactMap { $0 as? [String] }

        let keysOpt: [String]?
        let flatValues: [String]
        if stringArrays.count == 2 {
            keysOpt = stringArrays[0]
            flatValues = stringArrays[1]
        } else if stringArrays.count == 1 {
            keysOpt = nil
            flatValues = stringArrays[0]
        } else {
            return []
        }

        let keys: [String]
        if let k = keysOpt?.map({ $0.trimmedWhitespace() }), !k.isEmpty {
            keys = k
            __lastExampleKeys = k
        } else if let inherited = __lastExampleKeys {
            keys = inherited
        } else {
            return []
        }

        let batches = flatValues.chuncked(by: keys.count)

        let tagsString = exampleTags.map { $0.name.trimmedWhitespace() }.joined(separator: " @")

        let examples: [[String: String]] = batches.map { row in
            var dict = Dictionary(uniqueKeysWithValues: zip(keys, row.map { $0.trimmedWhitespace() }))
            dict[__EXAMPLE_TAGS_KEY] = tagsString
            return dict
        }

        return examples.map { Gherkin.Example(values: $0) }
    case .exampleKeys:
        return (values as! [String]).map { $0.trimmedWhitespace() }
    case .exampleValues:
        return (values as! [String]).map { $0.trimmedWhitespace() }
    case .tag:
        return Gherkin.Tag((values[0] as! String).trimmedWhitespace())
    }
}

extension String {
    mutating func trimWhitespace() {
        self = trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trimmedWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func filterd<T, E>(_ values: [Any], is filteredType: E.Type) -> [T]? {
    guard let result = Array(values.filter { type(of: $0) == filteredType }) as? [T] else { return nil }
    return result
}

extension Array {
    func safely(_ index: Index) -> Element? {
        if index + 1 <= count {
            return self[index]
        }

        return nil
    }

    func chuncked(by: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: by).map { current in
            let end = current + by
            return Array(self[current ..< end])
        }
    }
}

enum GherkinLabel: String {
    case feature, scenario, scenarioOutline, name, description, tag, step, examples, exampleKeys, exampleValues
}

typealias GherkinConsumer = Consumer<GherkinLabel>

func makeParser() -> GherkinConsumer {
    let newLinesSet = CharacterSet.newlines
    let whitespaceCharacters = CharacterSet.whitespaces

    let whitespace: GherkinConsumer = .discard(.zeroOrMore(.character(in: whitespaceCharacters)))
    let nonDiscardedNewLines: GherkinConsumer = .zeroOrMore(.character(in: newLinesSet))
    let newLines: GherkinConsumer = .discard(nonDiscardedNewLines)
    let newLinesSetAndArrows = newLinesSet.union(CharacterSet(charactersIn: "|"))

    let anyCharacters: GherkinConsumer = .oneOrMore(.anyCharacter(except: newLinesSetAndArrows))
    let text: GherkinConsumer = .flatten(anyCharacters)

    func makeLabelAndDescription(startText: String, ignoreText: GherkinConsumer) -> GherkinConsumer {
        let start = GherkinConsumer.string(startText)
        return [
            .label(.name, .flatten([.discard(start), whitespace, text, newLines])),
            .optional(.label(.description, .flatten(.oneOrMore([.not(ignoreText), text, .replace("\n", " "), newLines])))),
        ]
    }

    let tagText: GherkinConsumer = .flatten(.oneOrMore(.anyCharacter(except: newLinesSet.union(CharacterSet(charactersIn: "@")))))

    let tag: GherkinConsumer = .label(.tag, .sequence([.discard("@"), tagText, .optional(whitespace), .optional(newLines)]))

    let feature: GherkinConsumer = makeLabelAndDescription(startText: "Feature:", ignoreText: "Scenario:" | "Scenario Outline:" | ["@", text])

    let stepKeywords: GherkinConsumer = .sequence([whitespace, "Given" | "When" | "Then" | "And" | "But"])
    let step: GherkinConsumer = .label(.step, [stepKeywords, whitespace, text, newLines])

    let scenarioName: GherkinConsumer = makeLabelAndDescription(startText: "Scenario:", ignoreText: stepKeywords)
    let scenario: GherkinConsumer = .label(.scenario, [
        .zeroOrMore(tag),
        scenarioName,
        .oneOrMore(step),
    ]
    )

    let discardedPipe: GherkinConsumer = .discard("|")

    let tableRow: GherkinConsumer = [
        whitespace,
        .interleaved(discardedPipe, text),
        newLines,
    ]

    let exampleBlock: GherkinConsumer = .label(.examples, [
        .zeroOrMore(tag),
        whitespace,
        .discard("Examples:"),
        newLines,
        .label(.exampleKeys, tableRow),
        .label(.exampleValues, .oneOrMore(tableRow)),
        newLines,
    ])

    let scenarioOutlineName = makeLabelAndDescription(startText: "Scenario Outline:", ignoreText: stepKeywords)
    let scenarioOutline: GherkinConsumer = .label(.scenarioOutline, [
        .zeroOrMore(tag),
        scenarioOutlineName,
        .oneOrMore(step),
        .oneOrMore(exampleBlock),
    ])

    let anyScenario: GherkinConsumer = scenario | scenarioOutline
    let gherkin: GherkinConsumer = .label(.feature, [
        .zeroOrMore(tag),
        feature,
        .oneOrMore(anyScenario),
    ])
    return gherkin
}

let gherkin = makeParser()
