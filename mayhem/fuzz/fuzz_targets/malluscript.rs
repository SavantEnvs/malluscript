#![no_main]
//
// malluscript-fuzz: in-process libFuzzer harness for malluscript's lexer + parser.
//
// Strategy: include the upstream lexer/parser modules directly via #[path] so we
// can call them in-process without going through run_file() (which calls
// std::process::exit(1) on parse errors, terminating the libFuzzer loop).
//
// `mod executor` (declared below without #[path]) auto-resolves to
// fuzz_targets/executor.rs, which in turn includes src/executor/ast.rs via
// a scoped #[path]. grammar.rs references `crate::executor::ast::*` for AST types.
//
// The executor itself is NOT called: executor/error.rs uses process::exit(0)
// for runtime errors (overflow, div-by-zero), which would kill the libFuzzer loop.
// Fuzzing the lexer+parser is the high-value surface for a scripting language.

use libfuzzer_sys::fuzz_target;
use std::collections::HashMap;

// Resolved to fuzz_targets/executor.rs (which includes only src/executor/ast.rs).
// This satisfies grammar.rs's `use crate::executor::ast::*`.
mod executor;

// Lexer: tokenizes malluscript source (handles UTF-8/Malayalam keywords, strings,
// integers, floats). No process::exit — returns Option<Result<...>>.
#[path = "../../../src/lexer/mod.rs"]
mod lexer;

// Parser: LALRPOP-generated recursive-descent parser. Returns Result<SourceUnit,
// String> — parse errors are returned, not exit()d.
#[path = "../../../src/parser/mod.rs"]
mod parser;

fuzz_target!(|data: &[u8]| {
    // Accept both valid UTF-8 and lossy-decoded bytes — the lexer works on &str.
    let source = match std::str::from_utf8(data) {
        Ok(s) => s.to_owned(),
        Err(_) => String::from_utf8_lossy(data).into_owned(),
    };

    // Lex + parse; ignore both Ok and Err (parse errors are expected for random input).
    let mut tokens = lexer::Lexer::new(&source, HashMap::new(), 0);
    let _ = parser::parse(&source, &mut tokens);
});
