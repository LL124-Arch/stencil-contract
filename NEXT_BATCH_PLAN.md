# 下一批次开发计划：连续嵌套数组路径

> 状态：待执行。已完成批次记录依次保存在 `BATCH_3_PLAN.md` 和 `BATCH_4_PLAN.md`。

## 背景

当前 schema 路径支持对象字段与数组通配符，例如 `users[].name` 和 `teams[].members[]`。但每个点分字段段只能带一个 `[]`，因此无法声明连续嵌套数组（例如 `matrix[][]`）。解析器、父级类型推导、样例遍历和实例路径生成都依赖这个限制。

## 目标

扩展扁平 schema 路径，使一个字段名后可以连续出现多个 `[]`，并让 schema 校验、模板引用判断、样例校验和 JSON Pointer 诊断对这些路径保持一致。

## 路径语义

- 支持 `matrix[][]`、`tensor[][][]` 和混合路径 `groups[].values[][]`。
- 每个 `[]` 表示遍历一层数组；`ContractField.kind` 描述路径末端值的类型。例如 `matrix[][]` 的类型约束作用于每个内层数组元素。
- 当路径在数组层之后还有点分子字段时，数组元素必须是 Object。例如 `matrix[][].name` 要求 `matrix` 与 `matrix[]` 为 Array，`matrix[][]` 为 Object。
- 父级声明可以省略；如果显式声明，数组层和对象层的类型必须与路径结构匹配。错误继续由 `ContractSchema::new` 以 `InvalidParentKind` 报告。
- required 继续约束字段是否存在，不要求任何数组非空。嵌套数组某一层为空时，不产生缺字段诊断。
- 对样例中的类型错误、缺失字段和额外字段，`path` 保留带 `[]` 的 schema 路径，`instance_path` 为带真实数组下标的 JSON Pointer，例如 `/matrix/1/0/name`。
- 路径模式与现有模板/partial API 的入口保持兼容；模板字段仍按现有 RootPaths 或 ContextAware 规则解析。

## 实施任务

1. 将解析后的路径段从单个 `array_item` 扩展为数组深度，并验证空键、孤立括号和非法括号序列仍会被拒绝。
2. 按每一层数组计算规范父路径和预期类型，覆盖对象字段与数组深度混合的路径。
3. 重构样例遍历，使每一层数组都能递归检查类型、必需性和额外字段，并累积对应的具体 JSON Pointer 下标。
4. 确保模板引用声明判断、未使用字段判断和 ContextAware section scope 解析能识别新增路径形态；对 Stencil 无法表达的引用形态明确保留既有行为。
5. 增加连续与混合嵌套数组测试，覆盖父类型冲突、空数组、多个错误下标、缺字段、额外字段、Any 以及 `~`、`/` 键转义。
6. 更新 API 注释、README 示例和 `pkg.generated.mbti`（如公开 API 有变化）。

## 验收标准

- `matrix[][]`、`tensor[][][]`、`groups[].values[][]` 可成功解析；非法括号、空字段和重复路径仍返回现有 schema 错误。
- 显式父级类型按每层结构校验：每个数组层为 Array；数组后继续声明子字段时，数组元素层为 Object。
- 样例中的内外层数组元素都接受正确类型校验；数组为空不误报必需成员。
- 嵌套错误使用一致的 schema 路径，并定位到完整下标，例如 `path = "matrix[][].name"`、`instance_path = "/matrix/1/0/name"`。
- 深层对象的额外字段和缺失必需字段能定位到预期的 JSON Pointer；同路径不同下标错误不会被去重合并。
- RootPaths、ContextAware、partial 与批量样例入口继续通过回归检查。
- 通过仓库 CI：`moon fmt --check`、`moon check --deny-warn --target all`、`moon build`、`moon test --deny-warn --target all`。

## 本批不包含

- 多维数组维度或元素数量约束。
- 对 `{{.}}` 或其它 Stencil 语法新增 schema 字段映射规则。
- JSON Schema 导入、CLI 或运行时模板渲染。
