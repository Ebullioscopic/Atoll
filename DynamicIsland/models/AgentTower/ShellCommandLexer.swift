/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// One simple command: its words, plus how it was joined to what came before.
struct ShellCommand: Equatable, Sendable {
    /// Words after quote removal. `argv[0]` is the program, when there is one.
    let argv: [String]
    /// True when this command reads the previous one's output.
    let isPipeTarget: Bool
    /// True when any word was quoted, so a literal string cannot be mistaken for
    /// a program name.
    let hadQuotedWord: Bool

    /// The program being run, with any path stripped: `/bin/rm` → `rm`.
    var program: String? {
        guard let first = argv.first, !first.isEmpty else { return nil }
        // `FOO=bar cmd` — skip leading assignments to find the real program.
        for word in argv {
            if word.contains("="), !word.hasPrefix("-"),
               let equals = word.firstIndex(of: "="),
               word.distance(from: word.startIndex, to: equals) > 0,
               !word.prefix(upTo: equals).contains("/") {
                continue
            }
            return (word as NSString).lastPathComponent
        }
        return (first as NSString).lastPathComponent
    }

    /// Words after the program, ignoring leading environment assignments.
    var arguments: [String] {
        var seenProgram = false
        var result: [String] = []
        for word in argv {
            if !seenProgram {
                if word.contains("="), !word.hasPrefix("-"),
                   let equals = word.firstIndex(of: "="),
                   word.distance(from: word.startIndex, to: equals) > 0,
                   !word.prefix(upTo: equals).contains("/") {
                    continue
                }
                seenProgram = true
                continue
            }
            result.append(word)
        }
        return result
    }
}

/// Splits a shell command line into the simple commands it will actually run.
///
/// Exists because substring matching cannot tell a command from a string that
/// merely mentions one. `echo "rm -rf /"` runs `echo`; `# rm -rf /` runs nothing.
/// A classifier that flags either of those trains the user to ignore its
/// warnings, which is worse than having no classifier — so the risk rules in
/// ``DestructiveCommandClassifier`` are written against this structure instead of
/// against raw text.
///
/// Deliberately not a shell parser: no expansion, no subshell recursion, no
/// redirection semantics. It only has to be right about *where the words are*.
enum ShellCommandLexer {
    /// Notes about constructs that hide what a command does.
    struct Obfuscation: Equatable, Sendable {
        /// `$(…)` or backticks.
        var hasCommandSubstitution = false
        /// `eval`.
        var hasEval = false
        /// `\x41` or `\101` escapes, or a `base64 -d` / `xxd -r` decode.
        var hasEncodedPayload = false

        var isEmpty: Bool {
            !hasCommandSubstitution && !hasEval && !hasEncodedPayload
        }
    }

    struct Result: Equatable, Sendable {
        var commands: [ShellCommand] = []
        var obfuscation = Obfuscation()
    }

    /// Lexes `line` into simple commands.
    static func lex(_ line: String) -> Result {
        var result = Result()
        var argv: [String] = []
        var current = ""
        var hasCurrent = false
        var hadQuotedWord = false
        var currentIsPipeTarget = false
        var nextIsPipeTarget = false

        func finishWord() {
            guard hasCurrent else { return }
            argv.append(current)
            current = ""
            hasCurrent = false
        }

        func finishCommand() {
            finishWord()
            guard !argv.isEmpty else {
                // No words were collected, so the pending pipe target still
                // applies to the next real command.
                if nextIsPipeTarget {
                    currentIsPipeTarget = true
                    nextIsPipeTarget = false
                }
                return
            }
            result.commands.append(
                ShellCommand(argv: argv, isPipeTarget: currentIsPipeTarget, hadQuotedWord: hadQuotedWord)
            )
            argv = []
            hadQuotedWord = false
            currentIsPipeTarget = nextIsPipeTarget
            nextIsPipeTarget = false
        }

        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]

            switch character {
            case "\\":
                // Escaped character: take the next one literally.
                let next = line.index(after: index)
                if next < line.endIndex {
                    let escaped = line[next]
                    if escaped == "x" || escaped.isNumber {
                        result.obfuscation.hasEncodedPayload = true
                    }
                    current.append(escaped)
                    hasCurrent = true
                    index = line.index(after: next)
                    continue
                }
                index = next

            case "'":
                // Single quotes are fully literal.
                hadQuotedWord = true
                hasCurrent = true
                index = line.index(after: index)
                while index < line.endIndex, line[index] != "'" {
                    current.append(line[index])
                    index = line.index(after: index)
                }
                if index < line.endIndex { index = line.index(after: index) }

            case "\"":
                // Double quotes still expand, so substitutions inside them count.
                hadQuotedWord = true
                hasCurrent = true
                index = line.index(after: index)
                while index < line.endIndex, line[index] != "\"" {
                    if line[index] == "$", line.index(after: index) < line.endIndex,
                       line[line.index(after: index)] == "(" {
                        result.obfuscation.hasCommandSubstitution = true
                    }
                    if line[index] == "`" {
                        result.obfuscation.hasCommandSubstitution = true
                    }
                    current.append(line[index])
                    index = line.index(after: index)
                }
                if index < line.endIndex { index = line.index(after: index) }

            case "#":
                // A comment, but only where a word could start.
                if !hasCurrent {
                    while index < line.endIndex, line[index] != "\n" {
                        index = line.index(after: index)
                    }
                    continue
                }
                current.append(character)
                hasCurrent = true
                index = line.index(after: index)

            case "`":
                result.obfuscation.hasCommandSubstitution = true
                index = line.index(after: index)

            case "$":
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "(" {
                    result.obfuscation.hasCommandSubstitution = true
                }
                current.append(character)
                hasCurrent = true
                index = next

            case ";", "\n":
                finishCommand()
                index = line.index(after: index)

            case "|":
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "|" {
                    // `||` is a separator, not a pipe.
                    finishCommand()
                    index = line.index(after: next)
                } else {
                    nextIsPipeTarget = true
                    finishCommand()
                    index = next
                }

            case "&":
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "&" {
                    finishCommand()
                    index = line.index(after: next)
                } else {
                    // Background: still a command boundary.
                    finishCommand()
                    index = next
                }

            case " ", "\t":
                finishWord()
                index = line.index(after: index)

            case "(", ")", "{", "}":
                // Grouping. Treated as a boundary so `( rm -rf / )` still yields
                // `rm` as a command rather than one long word.
                finishCommand()
                index = line.index(after: index)

            default:
                current.append(character)
                hasCurrent = true
                index = line.index(after: index)
            }
        }
        finishCommand()

        for command in result.commands {
            if command.program == "eval" { result.obfuscation.hasEval = true }
            if let program = command.program, program == "base64" || program == "xxd" || program == "uudecode" {
                let flags = command.arguments.joined(separator: " ")
                if flags.contains("-d") || flags.contains("-D") || flags.contains("--decode") || flags.contains("-r") {
                    result.obfuscation.hasEncodedPayload = true
                }
            }
        }

        return result
    }
}
