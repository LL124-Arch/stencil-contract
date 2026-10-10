# 批次计划与完成记录：正则与倍数约束

> 状态：已完成（2026-10-10）。

## 目标

补齐 JSON Schema 常用字符串正则 `pattern` 和数字 `multipleOf` 断言，并沿用现有的约束诊断与实例路径定位。

## 支持范围

- `pattern` 必须是字符串；使用 MoonBit core `Regex` 语法并按子串匹配，锚点由 `^` / `$` 表达。
- 无法由正则引擎编译的 pattern 报为 `ContractError`，不静默忽略。
- `multipleOf` 必须是有限正数；小数倍数使用十进制整数运算检查。
- 两项约束适用于导入器支持的字段、数组元素以及本地 `$ref` 展开的路径。
- 不适用类型的关键字按 JSON Schema 断言语义跳过；类型本身由 `type` 约束检查。

## 完成记录

- Schema 导入器识别并校验 `pattern` 与 `multipleOf`，且在 schema 创建时编译 pattern。
- 样例检查器返回带 schema 路径和 JSON Pointer 的 `constraint_violation` 诊断。
- README 增加用法、正则语义和示例。
- `moon fmt`、`moon check --deny-warn --target all`、`moon build`、`moon info --target all` 通过；本次未运行测试套件。
