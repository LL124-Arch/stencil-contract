# 批次计划与完成记录：JSON Schema 导入与 JSON 诊断导出

> 状态：已完成（2026-10-10）。本次提交同时包含 `BATCH_5_PLAN.md` 记录的连续嵌套数组功能。

## 目标

让已有契约检查器能接入 JSON Schema，并把报告直接输出为机器可读 JSON。该批与批次 5 的嵌套数组路径共同整理为一次完整提交。

## 功能一：导入 JSON Schema 子集

- 增加 `ContractSchema::from_json_schema(schema : Json)`。
- 支持对象属性、`required`、基础 `type`、数组 `items` 和 `additionalProperties` 布尔值；`integer` 与 `number` 映射为 `ContractKind::Number`。
- `items` 可以递归嵌套；转换后沿用扁平点分路径与重复 `[]` 路径。
- JSON Schema 默认 `additionalProperties: true` 的语义需要保留；`false` 继续拒绝额外字段。原有 `ContractSchema::new` 继续默认严格。
- 根样例仍要求 JSON Object，与当前 checker 的既有契约一致。
- 对 `$schema`、`$id`、`title`、`description`、`$comment`、`default`、`examples`、`deprecated`、`readOnly`、`writeOnly` 等注释元数据允许忽略。
- 对 `$ref`、类型联合、数值/字符串/数组限制、模式、枚举、schema 形态的 `additionalProperties` 等无法表达的约束明确报 `ContractError`，不静默丢弃约束。

## 功能二：导出 JSON 报告

- 增加 `ContractReport::to_json()`。
- 顶层输出 `valid` 与 `diagnostics`；诊断包含稳定的小写 `severity`、`code`、`source`、`path`、`instance_path`、`expected`、`actual` 和 `message`。
- 无样例实例路径导出为 JSON `null`；诊断顺序与原报告完全一致。

## 实施任务

1. 为 `ContractSchema` 保存允许额外属性的对象路径；旧构造 API 初始化为空集合并保持严格行为。
2. 实现 JSON Schema 子集检查和递归扁平化，校验类型与关键字组合，生成已有 `ContractField`。
3. 让样例额外字段遍历按当前对象 schema 路径应用 `additionalProperties` 策略，同时继续校验已声明的子对象。
4. 增加结构化导入错误及 JSON Schema 不支持项错误。
5. 实现稳定诊断码与严重度名称，并生成 JSON 报告。
6. 更新 README、API 注释、测试及生成接口文件。

## 验收标准

- 嵌套 object/array JSON Schema 可导入为 `ContractSchema`，包含必需字段、类型检查和连续数组路径。
- `additionalProperties` 默认/`true` 在对应对象层允许额外字段，`false` 拒绝额外字段；内外层策略独立，且显式子字段仍递归检查。
- 原生 `ContractSchema::new` 的额外字段错误行为保持不变。
- 类型或关键字结构无效，以及超出支持子集的约束，均返回具体的 `ContractError`。
- `ContractReport::to_json()` 输出稳定字段、诊断顺序和 JSON `null` 实例路径。
- RootPaths、ContextAware、partial、批量样例以及批次 5 连续数组功能继续通过回归。
- 通过仓库 CI：`moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon test --deny-warn --target all`。

## 完成记录

- 新增 `ContractSchema::from_json_schema`，递归导入对象属性、必需字段、基础类型、连续数组 `items` 和布尔型 `additionalProperties`；`integer` 映射为 `Number`，JSON Schema 默认开放额外属性的语义按对象路径保留。
- 原生 `ContractSchema::new` 继续拒绝未声明样例字段。导入器对无效 schema 和不支持的约束返回具体 `ContractError`，不会静默丢弃 `$ref`、类型联合或验证关键字。
- 新增 `ContractReport::to_json()`，输出稳定的小写严重度和诊断码、原有诊断顺序，以及无实例位置时的 JSON `null`。
- 连续嵌套数组路径支持与本批互操作 API 一起交付；README、测试和生成接口文件均已更新。
- 验证通过：`moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon test --deny-warn --target all`（wasm、wasm-gc、js、native 各 30/30）和 `moon info --target all`；`git diff --check` 无空白错误。
