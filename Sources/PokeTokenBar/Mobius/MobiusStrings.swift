import Foundation

/// Temporary way-station for the user-facing strings that came over with the Mobius account
/// switching code. Phase 7 of `docs/reference/mobius-integration.md` moves them to
/// PokeTokenBar's own `L` struct (7 languages); until then these two functions return the key
/// unchanged, so the strings render in Korean — their original source form.
///
/// Mobius resolved the same keys through `Bundle.module` + `.lproj` sub-bundles. That approach is
/// deliberately **not** carried over: the PokeTokenBar target ships no resource bundle, and
/// `Bundle.module`'s accessor traps with `fatalError` when it cannot find one — Mobius saw exactly
/// that crash on another Mac when a release build reached for a bundled resource.
func loc(_ key: String) -> String { key }

/// Format-argument variant — the key is a Korean format string containing `%@` / `%d`.
func loc(_ key: String, _ args: CVarArg...) -> String {
    String(format: key, arguments: args)
}
