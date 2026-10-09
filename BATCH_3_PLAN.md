# 批次计划与完成记录：批量样例检查与稳定诊断

> 状态：已完成（2026-10-08）。

## 现状

当前检查器已支持根路径模式和作用域感知模式，也能递归检查 partial。公开入口每次只接收一个 `Json` 样例；CI 若要验证多个样例，需要重复执行整套模板分析，而且诊断中的 `source = "sample"` 无法指出是哪份样例失败。样例对象字段遍历产生的诊断顺序也尚未作为 API 行为固定下来。

## 目标

提供一个统一的批量检查入口，在一份模板、partial 集和 schema 上验证多份 JSON 样例，并返回可区分来源、顺序稳定的诊断。现有单样例 API 保持兼容，并作为批量入口的便捷包装。

## API 方案

- 增加 `ContractPathMode`，取值为 `RootPaths` 和 `ContextAware`，复用已有两种路径解析行为。
- 增加批量入口，接收模板、partial 映射、schema、样例数组和路径模式。空 partial 映射表示没有 partial。
- 单样例入口保持签名与行为不变；内部改为调用共享的批量检查实现。
- 批量结果中的样例诊断将使用 `source = "sample[i]"`，其中 `i` 是输入数组的零起始索引。旧单样例 API 继续使用 `source = "sample"`。
- 空样例数组产生错误诊断，避免只完成模板分析却被误认为样例验证通过。
- 模板、partial、schema 的诊断只生成一次；每份样例单独生成类型、必需字段、额外字段和根类型诊断。

## 诊断排序

在返回报告前按稳定规则排序，避免 JSON map 遍历顺序影响输出：

1. 模板与 partial 诊断按 `source`、`path`、诊断码排序。
2. schema 警告按字段路径排序。
3. 样例诊断按输入样例索引、字段路径、诊断码、期望值和实际值排序。

同一报告重复运行时，诊断字段和顺序都应一致。`ContractReport::is_valid()` 的规则不变：存在错误即失败，只有警告仍通过。

## 实施任务

1. 在类型文件中加入路径模式和空样例诊断码，并更新诊断来源文档。
2. 抽出共享的模板/schema 分析与逐样例校验流程；避免批量模式重复解析模板和 partial。
3. 为样例诊断保留样例索引，并实现最终稳定排序。
4. 保持四个现有单样例入口作为兼容包装器，确认它们的 `source = "sample"` 和诊断语义未改变。
5. README 增加批量检查示例，说明路径模式、空样例行为和样例索引。
6. 更新生成的 `pkg.generated.mbti`。

## 验收标准

- 两种路径模式都能批量检查；partial 可在不同样例共享，模板与 partial 诊断不会按样例重复。
- 每个样例的失败能通过 `source = "sample[i]"` 追溯；报告中同一字段在不同样例失败时保留各自诊断。
- 空样例集合返回错误；单样例入口仍返回原有的 `source = "sample"`。
- 根 JSON 类型、必需字段、字段类型、额外字段等现有校验继续覆盖批量样例。
- 相同输入多次运行产生相同诊断顺序；测试覆盖 JSON 对象字段排列变化。
- 通过仓库 CI：`moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon test --deny-warn --target all`。

## 本批不包含

- CLI、配置文件或 JSON Schema 导入。
- 模板行列号诊断；Stencil 当前公开 AST 不携带源码范围，需另行设计位置映射或扩展依赖 API。
- 改变旧入口的根路径/作用域语义，或改变 `ContractReport::is_valid()` 的判定方式。

## 完成记录

- 新增 `ContractPathMode` 和 `check_contract_samples(...)`；原有四个单样例入口改为兼容包装器。
- 批量样例诊断使用 `sample[index]`，空数组报告 `NoSamples`；静态分析只运行一次。
- 诊断按来源阶段、样例索引、字段路径和诊断码稳定排序。
- 全目标测试通过：19/19（wasm、wasm-gc、JS、native）。
- `moon fmt --check`、`moon check --deny-warn --target all`、`moon build` 和 `moon info --target all` 均通过。
