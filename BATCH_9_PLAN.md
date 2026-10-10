# 批次计划与完成记录：字符串、对象和数组约束

> 状态：已完成（2026-10-10）。

## 目标

补齐常见 JSON Schema 长度与集合大小限制，并校验数组元素唯一性。

## 支持范围

- 字符串 `minLength` 和 `maxLength`，按 Unicode code point 计数。
- 对象 `minProperties` 和 `maxProperties`。
- 数组 `uniqueItems: true`；每条重复项诊断定位到后续重复元素。
- 长度/属性数量限制校验为非负整数；`uniqueItems` 必须是布尔值。
- 约束可由本地 `$ref` 展开，并复用 `constraint_violation` 诊断。

## 完成记录

- 导入器支持上述五类关键字；`uniqueItems: false` 不增加限制。
- 样例校验器按 Unicode 字符数、对象属性数和 JSON 结构相等检查数组重复项。
- README 已更新约束清单和示例。
- `moon fmt`、`moon check --deny-warn` 和 `moon info --target all` 通过；本次未运行测试套件。
