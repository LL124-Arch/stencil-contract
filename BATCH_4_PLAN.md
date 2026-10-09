# 批次计划与完成记录：样例诊断的具体 JSON 路径

> 状态：已完成（2026-10-08）。上一批完成记录保存在 `BATCH_3_PLAN.md`。

## 背景

批量检查已通过 `source = "sample[i]"` 指出失败样例，但数组内的诊断仍使用 schema 通配路径，例如 `users[].name`。当同一份样例中多个数组元素都不符合类型或缺字段时，诊断无法指出具体元素；当前去重也可能把这些错误合并为一条。

## 目标

为样例诊断增加具体数据位置，同时保留 `ContractDiagnostic.path` 的 schema 路径语义。模板、partial、schema 诊断没有样例实例位置；批量样例索引、旧单样例来源值和 `is_valid()` 判定保持不变。

## API 方案

- 在 `ContractDiagnostic` 增加可选的 `instance_path : String?`。
- `path` 继续表示 schema/模板使用的字段路径，例如 `users[].name`；`instance_path` 表示某个 JSON 样例中的具体位置。
- `instance_path` 使用 JSON Pointer 风格的路径：对象成员用 `/` 分隔，数组项使用十进制索引；键中的 `~` 和 `/` 分别转义为 `~0` 和 `~1`。根 JSON 使用空字符串。
- 示例：schema 路径 `users[].name` 在第一个用户处报错时，诊断保留 `path = "users[].name"`，并设置 `instance_path = "/users/0/name"`。
- 对象键缺失时，实例路径指向预期成员位置；额外字段错误指向实际多出的成员；根类型不匹配指向根位置。
- 模板语法、partial、未声明路径、未使用 schema 字段和空样例诊断的 `instance_path` 为 `None`。
- 去重键加入 `instance_path`，避免不同数组元素上的相同错误被合并。
- 样例诊断排序在原有样例索引和 schema 路径之后，按具体实例路径、诊断码、期望值和实际值排序。

## 实施任务

1. 在诊断类型中加入 `instance_path`，更新文档注释和生成的 API 信息。
2. 为 JSON Pointer 成员和数组项路径添加小型内部构造函数，覆盖 `~`、`/` 转义。
3. 将当前 schema 路径前缀与实际 JSON 路径分开传入字段和额外字段遍历；数组循环携带真实下标。
4. 将实例路径传入样例诊断，并纳入诊断去重和稳定排序。
5. 保持现有 `source`、schema `path`、诊断码和 `ContractReport::is_valid()` 行为。
6. 更新 README，增加“schema 通配路径 + 样例 JSON Pointer”的诊断示例。

## 验收标准

- 同一数组中两个错误元素分别产生诊断，`source` 相同、schema `path` 相同、`instance_path` 不同。
- 缺失的数组元素子字段、类型不符、额外字段和根类型错误都携带正确实例路径。
- 对象键包含 `~` 或 `/` 时，JSON Pointer 转义正确；根位置为空字符串。
- 普通模板/partial/schema 诊断的 `instance_path` 为 `None`；旧单样例仍使用 `source = "sample"`，批量样例仍使用 `sample[i]`。
- 多样例及字段排列变化时诊断顺序稳定；不同数组下标的错误不再被去重合并。
- 通过仓库 CI：`moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon test --deny-warn --target all`。

## 本批不包含

- 改变 schema 路径语法或增加直接嵌套数组路径（例如 `matrix[][]`）。
- 模板源码行列号；Stencil 当前扫描 token 和 AST 没有保留源码范围。
- CLI、JSON Schema 导入或新的渲染行为。

## 完成记录

- `ContractDiagnostic.instance_path` 已加入公开诊断类型；静态诊断使用 `None`，样例根路径使用 `Some("")`。
- 样例校验分别追踪 schema 通配路径与真实 JSON 路径；数组元素带零起始下标，键名按 JSON Pointer 转义。
- 去重和排序包含实例路径；同一数组中同路径的错误保留为独立诊断。
- README 已说明 schema 路径与 JSON Pointer 的关系。
- 验证通过：`moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon test --deny-warn --target all`（wasm、wasm-gc、js、native 各 22/22）和 `moon info --target all`。
