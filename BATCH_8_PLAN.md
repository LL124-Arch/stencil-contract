# 批次计划与完成记录：JSON Schema 值约束

> 状态：已完成（2026-10-10）。

## 目标

在既有类型、必需性和对象字段检查上，增加常见 JSON Schema 值约束，并将违反项作为带具体 JSON Pointer 的诊断返回。

## 支持范围

- `enum` 和 `const`，使用 JSON 结构相等比较。
- 数字 `minimum`、`maximum`、`exclusiveMinimum` 和 `exclusiveMaximum`。
- 数组 `minItems` 和 `maxItems`。
- 在根值、普通字段及任意数组层级应用约束；保留局部 `$ref` 展开出的约束。
- 非数字边界、空或重复 `enum`、负数或非整数项目数限制作为无效 schema 报告。
- 未实现的约束继续返回 `ContractError`，避免静默漏检。

## 完成记录

- `ContractSchema` 内部保存导入的值约束；`ContractSchema::new` 和既有 `ContractField` API 保持不变。
- 新增 `ConstraintViolation` 诊断码与稳定 JSON 名称 `constraint_violation`；报告包含 schema 路径、具体实例路径、期望值和实际值。
- README 增加值约束说明与导入示例。
- `moon fmt`、`moon check --deny-warn` 和 `moon info --target all` 通过；本次未运行测试套件。
