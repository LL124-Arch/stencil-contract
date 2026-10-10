# 批次计划与完成记录：对象键名与条件必需字段

> 状态：已完成（2026-10-10）。

## 目标

增强 JSON Schema 对象检查，支持键名规则和由字段存在触发的条件必需性。

## 支持范围

- `propertyNames` 支持布尔 schema，以及 `type`、`enum`、`const`、`pattern`、`minLength`、`maxLength`。
- `propertyNames` 的正则采用 MoonBit core `Regex` 语法；失败诊断定位到具体键名的 JSON Pointer。
- `dependentRequired` 要求属性存在时，检查其依赖属性并返回 `missing_required_field`。
- 两项关键字都要求对象 schema；其结构类型、数组成员和受支持的约束值均在导入时校验。
- 暂不支持 `patternProperties`、schema-valued `additionalProperties`、`format` 和组合 schema。

## 完成记录

- JSON Schema 导入器将两项关键字纳入对象 schema 校验与现有约束存储。
- 样例检查覆盖根对象和嵌套对象，并保留诊断来源、schema 路径及 JSON Pointer。
- README 更新支持边界和组合示例。
- `moon fmt`、`moon check --deny-warn --target all`、`moon build`、`moon info --target all` 通过；本次未运行测试套件。
