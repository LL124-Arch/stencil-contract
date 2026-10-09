# 批次计划与完成记录：JSON Schema 本地引用

> 状态：已完成（2026-10-10）。

## 目标

允许 JSON Schema 重用 `$defs` 或 `definitions` 中的对象与元素 schema，让常见本地 `$ref` 可由现有扁平契约检查器分析。

## 支持范围

- 解析 `#` 和 `#/...` 本地 JSON Pointer 引用，并按 `~1`、`~0` 解码路径 token。
- 在引用使用位置展开 schema，因此同一 schema 可被多个属性或数组 `items` 复用。
- 忽略 `$ref` 上允许的注释元数据；声明断言关键字作为 `$ref` 兄弟项时明确报不支持，避免错误地忽略交集约束。
- 外部/非 JSON Pointer 引用、无法解析或转义错误的指针、递归引用和嵌套 `$id` 资源范围返回具体导入错误。递归结构无法用有限扁平路径表达。

## 完成记录

- `ContractSchema::from_json_schema` 现在解析 `$defs` 与 `definitions` 中被引用的 schema，并沿用现有字段路径、必需性、数组通配路径及 `additionalProperties` 校验。
- 支持可重复使用的非递归本地引用，包括嵌套数组元素引用和转义的 `/`、`~` token。
- 对外部引用、未知目标、递归结构及带验证断言的 `$ref` 兄弟项报告 `ContractError`。
- README 已记录支持边界；公开 API 未变化。
- `moon check --deny-warn` 通过。按当前任务约束未运行测试套件。
