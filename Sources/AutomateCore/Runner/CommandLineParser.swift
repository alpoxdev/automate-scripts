import Foundation

public struct CommandInvocation: Equatable, Sendable {
    public var command: String
    public var arguments: [String]

    public init(command: String, arguments: [String] = []) {
        self.command = command
        self.arguments = arguments
    }
}

public enum CommandLineParser: Sendable {
    public static func normalized(commandText: String, argumentsText: String = "") -> CommandInvocation {
        normalized(commandText: commandText, arguments: split(argumentsText))
    }

    public static func normalized(commandText: String, arguments: [String]) -> CommandInvocation {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard arguments.isEmpty else {
            return CommandInvocation(command: command, arguments: arguments)
        }

        let tokens = split(command)
        guard let executable = tokens.first else {
            return CommandInvocation(command: command, arguments: [])
        }
        return CommandInvocation(command: executable, arguments: Array(tokens.dropFirst()))
    }

    public static func split(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                escaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if escaped {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
