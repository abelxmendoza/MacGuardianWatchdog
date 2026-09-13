import Foundation

/// Centralizes shell- and AppleScript-string quoting so paths and commands
/// built from user-controlled data (repositoryPath, in particular - it's a
/// free-text field, not just a folder-picker result) can't break out of the
/// quoting and inject arbitrary commands.
///
/// Before this existed, several call sites hand-rolled `"cd '\(path)'"` or
/// tried to escape a single quote as `\'`, which does nothing in POSIX shell
/// single-quoted strings - `\` has no special meaning there, so the string
/// just terminates early and everything after becomes live shell syntax.
extension String {
    /// Quotes this string as one literal POSIX shell argument/word, safe to
    /// splice into a shell command string (e.g. one passed to `bash -c` or
    /// AppleScript's `do script`) regardless of what characters it contains.
    ///
    /// Uses the standard single-quote technique: wrap in `'...'`, and for
    /// every literal `'` inside, close the quote, emit an escaped quote,
    /// and reopen it (`'\''`).
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes this string for embedding inside an AppleScript string
    /// literal, e.g. the argument to `do script "..."`. This alone does not
    /// make it safe against shell metacharacters once Terminal.app executes
    /// it - any path/command segments inside still need `.shellQuoted` too.
    var appleScriptQuoted: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
