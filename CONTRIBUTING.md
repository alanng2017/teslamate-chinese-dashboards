# 贡献指南

感谢您对 TeslaMate 中文 Dashboard 项目的关注！

## 🎯 如何贡献

### 1. 报告问题

如果您发现：
- 翻译错误或不准确
- Dashboard 显示异常
- 功能缺失

请提交 [GitHub Issue](https://github.com/wjsall/teslamate-chinese-dashboards/issues)，包含：
- 问题描述
- 截图（如有）
- 复现步骤
- 期望的改进

### 2. 改进翻译

#### 翻译流程

1. **Fork 本项目**
   ```bash
   # 点击 GitHub 页面上的 Fork 按钮
   ```

2. **克隆您的 Fork**
   ```bash
   git clone https://github.com/您的用户名/teslamate-chinese-dashboards.git
   cd teslamate-chinese-dashboards
   ```

3. **修改翻译**
   - 文件位置: `grafana/dashboards/zh-cn/*.json`
   - 修改 `title` 字段
   - 保持 JSON 格式正确

4. **提交修改**
   ```bash
   git add .
   git commit -m "fix: 改进 XX Dashboard 的翻译
   
   - 修改了 XX 面板的标题
   - 原翻译: XXX
   - 新翻译: XXX"
   
   git push origin main
   ```

5. **创建 Pull Request**
   - 访问您的 Fork 页面
   - 点击 "Contribute" → "Open pull request"
   - 填写 PR 描述

### 3. 翻译规范

#### 术语对照表

| 英文 | 建议中文 | 说明 |
|------|----------|------|
| Overview | 概览 | - |
| Status | 状态 | - |
| Charging | 充电 | - |
| Driving | 驾驶/行驶 | - |
| Consumption | 能耗 | - |
| Range | 续航里程 | - |
| Odometer | 里程表 | - |
| Temperature | 温度 | - |
| Session | 会话 | - |
| Statistics | 统计 | - |
| Summary | 汇总 | - |
| Total | 总计 | - |
| Average | 平均 | - |
| battery_heater | 电池加热器 | - |
| is_climate_on | 空调开关 | - |
| fan_status | 风扇状态 | - |
| SOC | 电量 | State of Charge |
| SoC Diff | 电量差 | - |

#### 翻译原则

1. **准确性** - 专业术语要准确
2. **简洁性** - 控制字数，不要太长
3. **一致性** - 相同术语统一翻译
4. **可读性** - 符合中文表达习惯

#### 禁止事项

- ❌ 使用繁体中文
- ❌ 混用中英文标点
- ❌ 过长的翻译（超过15个字）
- ❌ 网络用语或口语化表达

---

## ⚠️ 技术维护指南（重要）

> 本节记录项目维护中遇到的常见陷阱，收到 PR 时务必对照检查。

### 项目结构说明

```
grafana/dashboards/
├── zh-cn/          # 主要中文仪表板（用户可见）
└── internal/       # 内部仪表板（行程/充电详情页）
Dockerfile          # 构建 Docker 镜像
```

**Dockerfile 关键路径：**
```dockerfile
COPY grafana/dashboards/zh-cn/*.json /dashboards/
COPY grafana/dashboards/internal/*.json /dashboards_internal/
```
> ⚠️ internal 目录必须复制到 `/dashboards_internal/`（带下划线），写成 `/dashboards/internal/` 会导致该页面永远显示英文。

---

### 🔴 哪些地方绝对不能翻译

| 位置 | 原因 |
|------|------|
| `transformations[organize].indexByName` 的**键名** | 必须与 SQL 实际列名完全一致，否则列顺序乱掉 |
| `transformations[filterFieldsByName].include.names` 的值 | 必须与 SQL 列名一致，否则面板无数据 |
| `transformations[calculateField]` 引用的字段名 | 计算来源字段名 |
| `transformations[configFromData]` 的 `refId` | 必须匹配 target.refId |
| `options.xField` / `options.colorByField` | 引用真实字段名，翻译后图表报错 |
| `series[].x` / `series[].y` / `series[].pointColor.field` | XY 散点图轴配置 |
| `target.refId`（A/B/C 或自定义） | transformation 通过 refId 识别数据源 |

**正确做法**：如果 SQL 列名已翻译，以上引用处也必须同步改成相同的中文；反之保持英文也可以，但必须保持一致。

---

### 🔴 常见错误类型

#### 错误 1：SQL 列别名与 transformation 脱节
**症状**：面板显示"No data"或列顺序错乱

**原因**：翻译了 SQL 的 `AS "列名"` 但忘记同步更新 transformation 里的引用。

**检查要点**：
- `organize.indexByName` 的键 = SQL 列名 ✓
- `filterFieldsByName.include.names` 的值 = SQL 列名 ✓
- `xField` / `colorByField` = SQL 列名 ✓

---

#### 错误 2：rawSql 内引号是转义格式，字符串替换会漏改
**症状**：XY 图轴配置更新了，但图表仍然报错

**原因**：JSON 里 rawSql 中的引号存储为 `\"`（转义），直接替换文本只能改到 JSON 属性级别的引号，SQL 内部的转义引号改不到。

**正确修改方式（用 Python）**：
```python
import json
with open('file.json') as f:
    d = json.load(f)
# 操作 target['rawSql'] 字符串内容
for panel in d['panels']:
    for t in panel.get('targets', []):
        t['rawSql'] = t['rawSql'].replace('old', 'new')
with open('file.json', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
```

---

#### 错误 3：datasource type 填错
**症状**：模板变量报错，筛选下拉框无数据

| 位置 | 错误值 | 正确值 |
|------|--------|--------|
| `templating.list[].datasource.type` | `"postgres"` | `"grafana-postgresql-datasource"` |
| `__requires[].id` | `"postgres"` | `"grafana-postgresql-datasource"` |

**批量检查命令**：
```bash
grep -rl '"type": "postgres"' grafana/dashboards/
grep -rl '"id": "postgres"' grafana/dashboards/
```

---

#### 错误 4：datasource UID 硬编码了个人实例的 UID
**症状**：地图或特定面板无数据，报"datasource not found"

**原因**：从个人 Grafana 导出的 JSON 含私人 UID（如 `PC98BA2F4D77E1A42`），其他用户 Grafana 里不存在。

**正确值**：所有 datasource uid 必须是字符串 `"TeslaMate"`

**检查命令**：
```bash
grep -rn '"uid"' grafana/dashboards/ | grep -v '"TeslaMate"\|__inputs\|__requires'
```

---

#### 错误 5：图表图例/悬浮提示出现英文
**症状**：鼠标悬浮在图表上出现英文字段名

**原因**：SQL 列别名是英文，且没有对应的 `fieldConfig.overrides[].properties[].displayName`

**修复方式**：在对应 panel 的 `fieldConfig.overrides` 里添加：
```json
{
  "matcher": { "id": "byName", "options": "english_field_name" },
  "properties": [{ "id": "displayName", "value": "中文名称" }]
}
```

> 注意：对于 barchart 的 `xField`，不能改 SQL 列名，只能用 displayName override 改显示名。

---

#### 错误 6：Grafana 12 模板变量报错
**症状**：Query 类型模板变量出现错误提示

**修复**：每个 `type: "query"` 的变量需要加：
```json
"regexApplyTo": "value"
```

**`$aux` 变量还需要**：SQL 中 `json_build_object(...)` 后面加 `#>> '{}'`，否则返回 JSON 类型而非文本类型。

---

### ✅ 收到 PR 时的验收清单

```
□ SQL 列名改了吗？→ 检查 transformation 引用是否同步
□ 有 "type": "postgres"？→ 改为 "grafana-postgresql-datasource"
□ datasource uid 都是 "TeslaMate"？→ 不能有私人 UID
□ refId 有没有被翻译？→ 不能翻译
□ xField/colorByField/series 轴配置与 SQL 列名是否一致？
□ rawSql 里的列别名和 organize/filterFieldsByName 是否一致？
□ internal/ 里的文件是否也同步修改了？
□ JSON 格式是否合法？
```

**快速 JSON 格式验证**：
```bash
for file in grafana/dashboards/zh-cn/*.json grafana/dashboards/internal/*.json; do
    python3 -m json.tool "$file" > /dev/null || echo "❌ JSON 格式错误: $file"
done
```

### 4. 测试您的修改

#### 本地测试

```bash
# 1. 启动 Grafana
docker run -d \
  -p 3000:3000 \
  -v $(pwd)/grafana/dashboards/zh-cn:/etc/grafana/provisioning/dashboards/zh:ro \
  -e GF_DEFAULT_LANGUAGE=zh-Hans \
  grafana/grafana:latest

# 2. 访问 http://localhost:3000
# 3. 检查修改后的 Dashboard
```

#### 验证清单

- [ ] JSON 格式正确（无语法错误）
- [ ] 中文显示正常（无乱码）
- [ ] 字数适中（面板标题不超过15字）
- [ ] 术语统一（与现有翻译一致）

### 5. 提交 PR 规范

#### PR 标题格式

```
type(scope): 简短描述

# 示例:
fix(dashboard): 修复概览页面的翻译错误
feat(dashboard): 新增XX Dashboard的汉化
docs(readme): 更新安装说明
```

#### PR 描述模板

```markdown
## 修改内容
简要说明做了什么修改

## 修改原因
为什么需要这个修改

## 测试情况
- [ ] 本地测试通过
- [ ] JSON 格式验证通过
- [ ] Grafana 中显示正常

## 截图
（如有界面变化，请附截图）
```

#### Commit 规范

| 类型 | 说明 |
|------|------|
| `fix` | 修复问题 |
| `feat` | 新功能/新翻译 |
| `docs` | 文档修改 |
| `style` | 格式调整（不影响功能）|
| `refactor` | 重构 |
| `test` | 测试相关 |
| `chore` | 构建/工具相关 |

## 🔧 开发环境

### 推荐的工具

- **编辑器**: VS Code + JSON 插件
- **JSON 验证**: `python3 -m json.tool` 或 jq
- **Git 客户端**: GitHub Desktop 或命令行

### 快速验证脚本

```bash
# 验证所有 JSON 文件
for file in grafana/dashboards/zh-cn/*.json; do
    echo "检查: $file"
    python3 -m json.tool "$file" > /dev/null && echo "✅ 通过" || echo "❌ 失败"
done
```

## 📋 发布流程

维护者发布新版本时：

1. 更新 `README.md` 中的版本信息
2. 创建 Git Tag: `git tag v1.x.x`
3. 推送 Tag: `git push origin v1.x.x`
4. 在 GitHub 创建 Release

## 💬 沟通渠道

- GitHub Issues: 问题报告、功能建议
- GitHub Discussions: 一般性讨论
- PR Review: 代码审查

## 🙏 感谢

感谢所有贡献者的付出！

您的贡献将帮助更多中文用户使用 TeslaMate。
