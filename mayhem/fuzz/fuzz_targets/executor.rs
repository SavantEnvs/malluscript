// Stub executor module for the fuzz harness.
// Provides `crate::executor::ast` which grammar.rs references for AST node types.
// #[path] is relative to THIS FILE's directory (fuzz_targets/), so 3 levels up
// reaches the repo root (/mayhem/).
#[path = "../../../src/executor/ast.rs"]
pub mod ast;
