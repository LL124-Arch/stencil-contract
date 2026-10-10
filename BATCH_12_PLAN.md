# 批次计划与完成记录：常见字符串格式断言

> 状态：已完成（2026-10-10）。

## 目标

为 JSON Schema 导入器加入常见日期、时间和 UUID 字符串格式校验，并将违反项作为普通值约束诊断返回。

## 支持范围

- 支持 `date`、`time`、`date-time` 和 `uuid`，且应用于普通字符串字段及 `propertyNames`。
- 日期与时间按 RFC 3339 结构校验；日期检查月份天数和闰年，时间检查范围、小数秒和时区偏移。
- UUID 接受大小写均可的 8-4-4-4-12 十六进制分组形式。
- 非字符串 `format` 值作为无效 schema；未知格式返回 `ContractError`，不会被忽略。
- 格式失败诊断沿用 `constraint_violation`，保留 schema 路径、来源和 JSON Pointer。

## 完成记录

- 新增字符串格式解析与验证逻辑，并接入 JSON Schema 导入和样例校验。
- README 增加支持边界和示例。
- `moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon info --target all` 通过；本次未运行测试套件。
